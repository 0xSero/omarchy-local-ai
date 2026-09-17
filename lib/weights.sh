#!/usr/bin/env bash
# Weights: the plugin downloads, containers only read. Sourced; do not run.
#
# Two mount kinds decide where a download goes:
#   ${MODEL_ROOT}/<dir>      -> $MODEL_ROOT/<dir>/<weights.subdir>   (local-dir layout, read-only in the container)
#   ~/.cache/huggingface     -> the shared HF cache                    (hub layout; the engine resolves repo@revision)
# A marker written after a verified download is the presence check; it carries the revision,
# so a revision bump re-downloads and a hand-placed copy is picked up by the idempotent download.

declare -A WDEST=()   # weights_dest answers, by recipe id: a snapshot asks several times per recipe
weights_dest() { # weights_dest <recipe> -> "dir\t<path>" or "hf\t<hf-home>"
  local id; id=$(jq -r '.id // ""' <<<"$1")
  [[ -n $id && -n ${WDEST[$id]:-} ]] && { printf '%s\n' "${WDEST[$id]}"; return; }
  local out; out=$(weights_dest_compute "$1"); [[ -n $id ]] && WDEST[$id]=$out; printf '%s\n' "$out"
}
weights_dest_compute() {
  local r=$1 src tgt sub; sub=$(jq -r '.weights.subdir // ""' <<<"$r")
  while IFS=$'\t' read -r src tgt; do
    case $src in
      '${MODEL_ROOT}/'*) printf 'dir\t%s\n' "$(expand_mount "$src")${sub:+/$sub}"; return ;;
    esac
  done < <(jq -r '.launch.mounts[]?|[.source,.target]|@tsv' <<<"$r")
  printf 'hf\t%s\n' "$HF_HOME_DIR"
}
marker_path() { printf '%s/weights/%s.json\n' "$STATE" "$1"; }
weights_marked() { # weights_marked <recipe> : a marker matches repository+revision, this recipe's own or one of a
  # recipe that shares the same weights at the same path (a TP2 variant of the same model downloads nothing)
  local r=$1 m repo rev kind base
  repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r"); m=$(marker_path "$(jq -r .id <<<"$r")")
  read -r kind base < <(weights_dest "$r")
  # every marker through one jq: the recipe's own marker matches on repository+revision alone,
  # any other marker must also carry the recipe's kind and path (it says the same weights are there);
  # if, not &&, so an unmatched entry leaves the group's status clean and pipefail reports only jq's verdict
  { if [[ -f $m ]]; then jq -c --arg own true '{marker:$own, m:.}' "$m"; fi
    for f in "$STATE"/weights/*.json; do if [[ -f $f && $f != "$m" ]]; then jq -c '{marker:"other", m:.}' "$f"; fi; done; } \
    | jq -es 'map(.m) as $ms | $ms | any(.repository==$repo and .revision==$rev and ($own=="true" or (.kind==$k and .path==$b)))' \
    --arg repo "$repo" --arg rev "$rev" --arg own "$( { [[ -f $m ]] && printf true || printf false; } )" --arg k "$kind" --arg b "$base" >/dev/null 2>/dev/null
}
dir_bytes() { [[ -d $1 ]] && du -skL "$1" 2>/dev/null | awk '{print $1*1024}' || printf 0; }
file_bytes() { wc -c <"$1" 2>/dev/null | tr -d ' ' || printf 0; }
sha_file() { { command -v sha256sum >/dev/null 2>&1 && sha256sum -- "$1" || shasum -a 256 -- "$1"; } | cut -c1-64; }
# weights_files_ok <recipe>: the bytes the marker promises are really there. A marker outlives a
# deleted directory (a cache wipe, a hand-made cleanup), and an engine started over an empty
# read-only mount tries to download into it, crashes, and restarts forever. So presence is the
# marker AND the files: the served GGUF for a single-file recipe, otherwise at least one non-empty
# file in the recipe's directory (downloads land whole; partial ones stay under .cache).
weights_files_ok() {
  local r=$1 kind base f
  read -r kind base < <(weights_dest "$r")
  if [[ $kind == hf ]]; then base="$base/hub/models--$(jq -r '.model.repository' <<<"$r" | sed 's|/|--|g')/snapshots/$(jq -r .model.revision <<<"$r")"
  else f=$(jq -r '.model.servedName // ""' <<<"$r"); if [[ $f == *.gguf ]]; then [[ -s "$base/${f##*/}" ]]; return; fi; fi
  [[ -d $base ]] && [[ -n $(find -L "$base" -maxdepth 3 -name .cache -prune -o -type f -size +0 -print 2>/dev/null | head -1) ]]   # .cache: hf's own partials and metadata
}
weights_present() { weights_marked "$1" && weights_files_ok "$1"; }

# Weights you already have. Before any download, the recipe's file list is taken from the Hub's
# tree of the pinned revision (path, size, SHA-256 for LFS files, git blob id for the rest), and
# every directory under the usual places (~/models, the plugin's model root, the HF cache's
# snapshots of the same repository, ~/.cache/llama.cpp; OMARCHY_AI_WEIGHTS_PATHS adds more,
# colon-separated) that holds the recipe's largest file is checked file by file: same size, then
# same checksum. A match is adopted into the layout the engine expects, by reflink (free on
# btrfs), else a hard link, else a copy: the recipe's directory for ${MODEL_ROOT} mounts, the HF
# cache's blobs+snapshots for hub-layout recipes. A same-named older quant fails the size or the
# checksum and is refused, never served. Offline, nothing can be verified and nothing is adopted.
TREES="$STATE/trees"
hub_tree() { # hub_tree <repo> <rev> -> "path\tsize\tsha256-or--\tblob-oid" per file; cached per revision
  local repo=$1 rev=$2 f="$TREES/${repo//\//--}@$rev.tsv" tmp
  [[ -s $f ]] && { cat "$f"; return 0; }
  state_dir; mkdir -p "$TREES"; tmp=$(mktemp)
  curl -fsSL --max-time 30 --max-filesize 4194304 ${HF_TOKEN:+-H "Authorization: Bearer $HF_TOKEN"} "https://huggingface.co/api/models/$repo/tree/$rev?recursive=1" 2>/dev/null \
    | jq -r '.[] | select(.type=="file") | [.path, .size, (.lfs.oid // "-"), (.oid // "-")] | @tsv' >"$tmp" 2>/dev/null
  [[ -s $tmp ]] || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$f"; cat "$f"
}
weights_needed() { # weights_needed <recipe> -> the tree lines a launch needs: the served GGUF alone, else everything but docs
  local r=$1 repo rev f
  repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r"); f=$(jq -r '.model.servedName // ""' <<<"$r")
  if [[ $f == *.gguf ]]; then f=${f##*/}
    local want; want=$(jq -r '.model.sha256 // ""' <<<"$r")
    if [[ $want =~ ^[0-9a-f]{64}$ ]]; then printf '%s\t%s\t%s\t-\n' "$f" "$(jq -r '.model.sizeBytes // 0' <<<"$r")" "$want"; return 0; fi   # the recipe says; no network needed
    hub_tree "$repo" "$rev" | awk -F'\t' -v f="$f" '$1==f'
  else
    hub_tree "$repo" "$rev" | awk -F'\t' '$1 !~ /^(README|LICENSE|NOTICE|\.gitattributes)/ && $1 !~ /\.(md|png|jpg|jpeg|gif|svg|webp)$/'
  fi
}
blob_sha1() { { printf 'blob %d\0' "$(file_bytes "$1")"; cat -- "$1"; } | { command -v sha1sum >/dev/null 2>&1 && sha1sum || shasum -a 1; } | cut -c1-40; }
place_file() { # place_file <src> <dest>: reflink, else hard link, else copy; world-readable for the engine's uid
  mkdir_shared "$(dirname "$2")"; rm -f "$2"
  (umask 022; cp --reflink=always -- "$1" "$2" 2>/dev/null || ln -- "$1" "$2" 2>/dev/null || cp -- "$1" "$2") || { rm -f "$2"; return 1; }
  chmod go+r "$2" 2>/dev/null || true
}
weights_find() { # weights_find <recipe>: adopt a verified copy from this machine; 0 when the recipe's weights are now in place
  local r=$1 id kind base repo rev needed n big bigname root d c cand line path size sha oid csize ok i dest cache
  id=$(jq -r .id <<<"$r"); repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r")
  read -r kind base < <(weights_dest "$r")
  needed=$(weights_needed "$r") || { log "cannot list $repo@$rev on the Hub (offline?); nothing adopted"; return 1; }
  n=$(grep -c . <<<"$needed"); (( n > 0 )) || return 1
  big=$(sort -t$'\t' -k2,2nr <<<"$needed" | head -1 | cut -f1); bigname=${big##*/}   # the largest file names a candidate directory
  local -a roots=("$HOME_DIR/models" "$MODEL_ROOT" "$HF_HOME_DIR/hub/models--${repo//\//--}/snapshots" "$HOME_DIR/.cache/llama.cpp") extra=() cands=()
  IFS=: read -ra extra <<<"${OMARCHY_AI_WEIGHTS_PATHS:-}"; roots+=(${extra[@]+"${extra[@]}"})
  for root in "${roots[@]}"; do
    [[ -n $root && -d $root ]] || continue
    while IFS= read -r c; do
      [[ -n $c ]] || continue; d=${c%/"$big"}; [[ $d == "$c" ]] && d=$(dirname "$c")   # the tree's own subpath stripped
      [[ $(canon "$d") != "$(canon "$base")" && $d != "$HF_HOME_DIR/hub/"*"/blobs" ]] || continue   # not the destination, not the cache's blob store
      cands+=("$d")
    done < <(find -L "$root" -maxdepth 5 -type f -name "$bigname" -size +0 2>/dev/null | head -20)
  done
  ((${#cands[@]})) || return 1
  for cand in "${cands[@]}"; do
    ok=1
    while IFS=$'\t' read -r path size sha oid; do   # sizes first: cheap, and a wrong quant fails here
      [[ -n $path ]] || continue; c="$cand/$path"
      [[ -f $c && ( $size == 0 || $(file_bytes "$c") == "$size" ) ]] || { ok=0; log "found $cand but $path is missing or its size differs from the pinned file; skipped"; break; }
    done <<<"$needed"
    (( ok )) || continue
    i=0
    while IFS=$'\t' read -r path size sha oid; do   # then every checksum
      [[ -n $path ]] || continue; c="$cand/$path"; i=$((i+1))
      op download "$id" "checking a copy at ${cand/#$HOME_DIR/\~} · $i/$n" $(( i * 100 / n ))
      if [[ $sha != - ]]; then [[ $(sha_file "$c") == "$sha" ]] || { ok=0; log "found $cand but $path's checksum differs from the pinned file; skipped"; break; }
      elif [[ $oid != - ]]; then [[ $(blob_sha1 "$c") == "$oid" ]] || { ok=0; log "found $cand but $path's content differs from the pinned file; skipped"; break; }; fi
    done <<<"$needed"
    (( ok )) || continue
    op download "$id" "using the copy at ${cand/#$HOME_DIR/\~}" 100
    if [[ $kind == dir ]]; then
      while IFS=$'\t' read -r path size sha oid; do [[ -n $path ]] || continue; place_file "$cand/$path" "$base/$path" || { ok=0; break; }; done <<<"$needed"
    else # hub layout: blobs named by their etag (the SHA-256 of an LFS file, the blob id otherwise), snapshots/<rev>/<path> pointing at them
      cache="$HF_HOME_DIR/hub/models--${repo//\//--}"; mkdir_shared "$cache/blobs" "$cache/snapshots/$rev"
      while IFS=$'\t' read -r path size sha oid; do
        [[ -n $path ]] || continue; local etag=$sha; [[ $etag == - ]] && etag=$oid
        [[ -s $cache/blobs/$etag ]] || place_file "$cand/$path" "$cache/blobs/$etag" || { ok=0; break; }
        mkdir_shared "$(dirname "$cache/snapshots/$rev/$path")"
        local up=""; local rest=$path; while [[ $rest == */* ]]; do up+="../"; rest=${rest#*/}; done
        ln -sfn "../../${up}blobs/$etag" "$cache/snapshots/$rev/$path" || { ok=0; break; }
      done <<<"$needed"
    fi
    if (( ok )); then log "adopted $cand as $([[ $kind == dir ]] && printf '%s' "$base" || printf '%s' "$cache/snapshots/$rev") ($n files, verified against $repo@${rev:0:12})"; weights_dest_vars "$r"; weights_mark "$r"; return 0; fi
    log "could not place the copy from $cand; downloading instead"; return 1
  done
  return 1
}

# download_weights <recipe>: host `hf` when present, else the recipe's own image, which always carries
# huggingface_hub because the engine loads from the Hub. Progress is reported through op().
# mount_dirs <recipe>: the host directories the recipe mounts, made before any container (as this user, shared)
mount_dirs() {
  local r=$1 src tgt real
  while IFS=$'\t' read -r src tgt; do
    case $src in
      '${MODEL_ROOT}/'*|'${CACHE_ROOT}/'*) real=$(canon "$(expand_mount "$src")"); mkdir_shared "$real" ;;
      '~/.cache/huggingface'*) real=$(canon "$HOME_DIR/${src#\~/}"); mkdir_shared "$real" ;;
    esac
  done < <(jq -r '.launch.mounts[]?|[.source,.target]|@tsv' <<<"$r")
}
weights_plan() { # weights_plan <recipe>: sets WKIND WBASE WEXP WPATTERN, makes the base dir, checks free space
  local r=$1 served
  WEXP=$(jq -r '((.model.sizeGb//0)*1073741824)|floor' <<<"$r")
  read -r WKIND WBASE < <(weights_dest "$r")
  mkdir_shared "$WBASE"; state_dir; mkdir -p "$(dirname "$(marker_path "$(jq -r .id <<<"$r")")")"
  # in hub mode the base is the whole HF cache, shared with everything else on the machine: measure
  # this repository's own cache directory, not the cache
  WMEASURE=$WBASE; [[ $WKIND == hf ]] && WMEASURE="$WBASE/hub/models--$(jq -r '.model.repository' <<<"$r" | sed 's|/|--|g')"
  local free bytes; free=$(df -Pk "$WBASE" 2>/dev/null | awk 'NR==2{print $4*1024}'); bytes=$(dir_bytes "$WMEASURE")
  if (( WEXP > 0 && ${free:-0} > 0 && free < WEXP - bytes )); then fail "need $(( (WEXP-bytes+1073741823)/1073741824 )) GB free under $WBASE"; return 1; fi
  # a GGUF recipe serves one file out of a repo full of quants: fetch only that file (and any mmproj)
  WPATTERN=""; served=$(jq -r .model.servedName <<<"$r"); [[ $served == *.gguf ]] && WPATTERN="${served##*/}"
  return 0
}
weights_mark() { # weights_mark <recipe>: the completion marker, written by this user after a verified download
  local r=$1
  jq -nc --arg repo "$(jq -r .model.repository <<<"$r")" --arg rev "$(jq -r .model.revision <<<"$r")" --arg t "$(now)" --arg k "$WKIND" --arg b "$WBASE" \
    '{repository:$repo,revision:$rev,completedAt:$t,kind:$k,path:$b}' >"$(marker_path "$(jq -r .id <<<"$r")")"
}
weights_partial_bytes() { # weights_partial_bytes <recipe> -> bytes already on disk for a recipe that is not marked complete
  local r=$1 kind base
  read -r kind base < <(weights_dest "$r")
  [[ $kind == hf ]] && base="$base/hub/models--$(jq -r '.model.repository' <<<"$r" | sed 's|/|--|g')"
  dir_bytes "$base"
}
# cancel_download <worker-pid>: stop the download worker and everything it spawned; partial weights
# stay where they are and the next load resumes (hf and the hub downloader both pick up what is
# there). The cancel marker tells the worker's exit trap this was asked for, not a crash.
cancel_download() {
  local p=$1 i c
  if ! docker_direct && ! host_hf >/dev/null; then refuse "the download runs behind the password prompt and cannot be stopped from here"; return 1; fi
  state_dir; : >"$STATE/cancel"; log "cancel: stopping download worker $p"
  kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || true
  for ((i=0; i<100; i++)); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$p" 2>/dev/null && { kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null || true; sleep 0.2; }
  if docker_direct; then for c in $(docker ps -q --filter "label=$LABEL.download=1" 2>/dev/null); do docker rm -f "$c" >/dev/null 2>&1 || true; done; fi
  lwrite '.op={name:"",recipeId:"",pid:0,startedAt:"",detail:"",percent:0} | .error=""'; rm -f "$STATE/cancel"
  log "download stopped; partial weights kept"; snapshot_write
}
host_hf() { [[ -z ${OMARCHY_AI_NO_HOST_HF:-} ]] && bin_of hf 2>/dev/null; }

# download_host <recipe>: the host `hf` tool, as this user, with progress on the card. No docker.
download_host() {
  local r=$1 id hf repo rev pid bytes pct prev=0 rate eta detail
  id=$(jq -r .id <<<"$r"); repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r"); hf=$(host_hf)
  local -a cmd
  if [[ $WKIND == dir ]]; then cmd=("$hf" download "$repo" --revision "$rev" --local-dir "$WBASE" ${WPATTERN:+--include "$WPATTERN" --include "*mmproj*"})
  else cmd=(env HF_HOME="$WBASE" "$hf" download "$repo" --revision "$rev" ${WPATTERN:+--include "$WPATTERN" --include "*mmproj*"}); fi
  op download "$id" "downloading weights" 0; log "download: ${cmd[*]}"
  spawn_child "${cmd[@]}" >>"$LOGFILE" 2>&1; pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    bytes=$(dir_bytes "${WMEASURE:-$WBASE}")
    if (( WEXP > 0 )); then
      pct=$(( bytes*100/WEXP )); (( pct > 100 )) && pct=100
      detail="$((bytes/1073741824)) / $((WEXP/1073741824)) GB"
      if (( POLL > 0 && bytes > prev && prev > 0 )); then rate=$(( (bytes - prev) / POLL )); eta=$(( (WEXP - bytes) / rate )); (( eta < 0 )) && eta=0; detail+=" · about $((eta/60))m$((eta%60))s left"; fi
      op download "$id" "$detail" "$pct"
    fi
    prev=$bytes; sleep "$POLL"
  done
  wait "$pid" || { fail "weight download failed for $id (see $LOGFILE)"; return 1; }
}

# download_run <recipe>: the recipe's own image downloads the weights (it always carries huggingface_hub);
# runs inside a phase, blocking; the user's side reports progress from the directory's size.
download_run() {
  local r=$1 id repo rev img err
  id=$(jq -r .id <<<"$r"); repo=$(jq -r .model.repository <<<"$r"); rev=$(jq -r .model.revision <<<"$r"); img=$(jq -r .launch.image <<<"$r")
  weights_dest_vars "$r"
  local py="import os; from huggingface_hub import snapshot_download as d; d(os.environ['HF_REPO'], revision=os.environ['HF_REV']"
  [[ -n $WPATTERN ]] && py+=", allow_patterns=[os.environ['HF_PATTERN'], '*mmproj*']"
  if [[ $WKIND == dir ]]; then py+=", local_dir='/weights')"; else py+=")"; fi
  # HF_HOME must be writable for the hub cache and xet chunks: the mounted /hf in hub mode, /tmp in dir mode
  local -a cmd=(docker run --rm --user "$RUN_AS" --label "$LABEL.download=1" --network bridge
       --env HF_HOME="$([[ $WKIND == dir ]] && echo /tmp/hf || echo /hf)" --env HOME=/tmp
       ${HF_TOKEN:+--env HF_TOKEN} --env "HF_REPO=$repo" --env "HF_REV=$rev" ${WPATTERN:+--env "HF_PATTERN=$WPATTERN"}
       --volume "$WBASE:$([[ $WKIND == dir ]] && echo /weights || echo /hf)"
       --entrypoint python3 "$img" -c "$py")
  log "download: ${cmd[*]}"
  err=$(mktemp)
  if ! run_child "${cmd[@]}" >&2 2>"$err"; then printf 'reason %s\n' "$(docker_reason "$err" "weight download for $id")"; rm -f "$err"; return 1; fi
  rm -f "$err"
}
weights_dest_vars() { # the plan's variables from the recipe alone (a phase has no user-side state)
  local r=$1 served
  read -r WKIND WBASE < <(weights_dest "$r")
  WPATTERN=""; served=$(jq -r .model.servedName <<<"$r"); [[ $served == *.gguf ]] && WPATTERN="${served##*/}"
}

# docker_reason <stderr-file> <what>: docker's own last line, turned into the sentence a person can act on.
# The card has three lines; the fix comes first, the raw line goes to the log.
docker_reason() {
  local last; last=$(grep -v '^\s*$' "$1" 2>/dev/null | tail -1 | cut -c1-200)
  log "$2: ${last:-no output from docker}"
  case $last in
    *permission\ denied*docker.sock*|*permission\ denied*Docker\ daemon*) printf 'Docker refuses your user: sudo usermod -aG docker $USER, then log out and in' ;;
    *could\ not\ select\ device\ driver*|*nvidia-container*|*unknown\ or\ invalid\ runtime*) printf 'the NVIDIA container toolkit is not set up: sudo pacman -S nvidia-container-toolkit; sudo nvidia-ctk runtime configure --runtime=docker; sudo systemctl restart docker' ;;
    *Cannot\ connect\ to\ the\ Docker\ daemon*|*Is\ the\ docker\ daemon\ running*) printf 'Docker is not running: sudo systemctl enable --now docker' ;;
    *no\ space\ left*|*No\ space\ left*) printf 'out of disk space for %s' "$2" ;;
    *unauthorized*|*denied:*|*authentication\ required*) printf 'the registry refused the pull: run docker logout ghcr.io and try again' ;;
    *TLS\ handshake*|*no\ such\ host*|*i/o\ timeout*|*dial\ tcp*|*connection\ refused*|*network\ is\ unreachable*) printf 'no route to the image registry: check the network and try again' ;;
    *manifest\ unknown*|*not\ found*) printf 'the pinned image is missing from the registry: report this' ;;
    "") printf '%s failed (see %s)' "$2" "$LOGFILE" ;;
    *) printf '%s failed: %s' "$2" "$(cut -c1-90 <<<"$last")" ;;
  esac
}
docker_ok() { # docker_ok [nvidia]: the daemon answers this process, and the NVIDIA runtime is there when the recipe needs it
  local info err; info=$(mktemp); err=$(mktemp)
  docker info >"$info" 2>"$err" || { docker_reason "$err" "docker"; rm -f "$info" "$err"; return 1; }
  if [[ ${1:-} == nvidia ]] && ! grep -qi 'nvidia' "$info"; then rm -f "$info" "$err"
    printf 'the NVIDIA container toolkit is not set up: sudo pacman -S nvidia-container-toolkit; sudo nvidia-ctk runtime configure --runtime=docker; sudo systemctl restart docker'
    return 1
  fi
  rm -f "$info" "$err"
}

ensure_image() { # pull once; the digest guarantees what we get. Phase-safe: no state files, reason on stdout
  local img=$1 id=$2 out
  docker image inspect "$img" >/dev/null 2>&1 && return 0
  echo "step pulling image"; out=$(mktemp)
  if ! run_child docker pull "$img" >"$out" 2>&1; then printf 'reason %s\n' "$(docker_reason "$out" "image pull for $id")"; rm -f "$out"; return 1; fi
  rm -f "$out"
}
