#!/usr/bin/env bash
# The vendored recipe file, the hardware match, and the safety gate. Sourced; do not run.

# The vendored file is the floor: what the release shipped and the marketplace reviewed. A newer
# copy is fetched from the registry repository (one fixed HTTPS origin, size-capped, schema-checked,
# accepted only when its generatedAt is newer than what is in use), kept 0600 under the state dir,
# and used in its place. Every recipe is still re-gated at launch (gate_reason), so a fetched file
# can add validated recipes but cannot widen what a launch may do. OMARCHY_AI_RECIPES_URL= disables.
RECIPES_VENDORED="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/recipes.json"
RECIPES_LIVE="$STATE/recipes.json"
RECIPES_URL="${OMARCHY_AI_RECIPES_URL-https://raw.githubusercontent.com/0xSero/local-ai-registry/main/plugin/recipes.json}"
RECIPES_TTL="${OMARCHY_AI_RECIPES_TTL:-21600}"   # seconds between checks: six hours
recipes_ok_file() { jq -e '.schemaVersion=="omarchy-local-ai/recipes/1" and (.hardware|type=="object") and (.gateway.image|type=="string" and test("@sha256:[0-9a-f]{64}$")) and (.generatedAt|type=="string")' "$1" >/dev/null 2>&1; }
recipes_generated() { jq -r '.generatedAt // ""' "$1" 2>/dev/null; }
recipes_select() { # the file in use: an explicit one, else the live copy when it is valid and newer than the vendored one
  if [[ -n ${OMARCHY_AI_RECIPES:-} ]]; then printf '%s' "$OMARCHY_AI_RECIPES"; return; fi
  if [[ -f $RECIPES_LIVE ]] && recipes_ok_file "$RECIPES_LIVE" && [[ $(recipes_generated "$RECIPES_LIVE") > $(recipes_generated "$RECIPES_VENDORED") ]]; then printf '%s' "$RECIPES_LIVE"; else printf '%s' "$RECIPES_VENDORED"; fi
}
RECIPES=$(recipes_select)
recipes_source() { [[ $RECIPES == "$RECIPES_LIVE" ]] && printf live || printf vendored; }
recipes_ok() { recipes_ok_file "$RECIPES"; }
recipes_count() { jq -r '[.hardware[] | .recipe, (.recipes[]?)] | length' "$RECIPES" 2>/dev/null || printf 0; }
# recipes_refresh: fetch the registry's copy; adopt it when it is valid and newer. Prints one line.
recipes_refresh() {
  [[ -n $RECIPES_URL ]] || { printf 'recipes: refresh is off (OMARCHY_AI_RECIPES_URL is empty)\n'; return 0; }
  state_dir; local tmp="$RECIPES_LIVE.tmp.$$" err rc=0; date -u +%s >"$STATE/recipes.checked"
  if ! err=$(curl -fsSL --max-time 20 --max-filesize 8388608 --proto =https -o "$tmp" "$RECIPES_URL" 2>&1); then
    rm -f "$tmp"; log "recipes: fetch failed: ${err:-no route}"; printf 'recipes: could not fetch the registry (%s); keeping %s\n' "${err:-no route}" "$(recipes_source)"; return 1
  fi
  if ! recipes_ok_file "$tmp"; then rm -f "$tmp"; log "recipes: the fetched file is not a recipes file; kept $(recipes_source)"; printf 'recipes: the fetched file is not a recipes file; keeping %s\n' "$(recipes_source)"; return 1; fi
  local got have; got=$(recipes_generated "$tmp"); have=$(recipes_generated "$RECIPES")
  if [[ ! $got > $have ]]; then rm -f "$tmp"; printf 'recipes: %s is current (registry %s, %s)\n' "$(recipes_source)" "$(registry_commit | cut -c1-12)" "$have"; return 0; fi
  chmod 600 "$tmp"; mv "$tmp" "$RECIPES_LIVE"; RECIPES=$RECIPES_LIVE
  log "recipes: refreshed to registry $(registry_commit) ($got, $(recipes_count) recipes)"
  printf 'recipes: updated to registry %s (%s, %s recipes)\n' "$(registry_commit | cut -c1-12)" "$got" "$(recipes_count)"
}
recipes_autorefresh() { # from snapshot: at most one detached fetch per TTL, never on the card's critical path
  [[ -n $RECIPES_URL && -z ${OMARCHY_AI_RECIPES:-} ]] || return 0
  local last=0; last=$(cat "$STATE/recipes.checked" 2>/dev/null || printf 0); [[ $last =~ ^[0-9]+$ ]] || last=0
  (( $(date -u +%s) - last >= RECIPES_TTL )) || return 0
  state_dir; date -u +%s >"$STATE/recipes.checked"   # claimed now, so concurrent snapshots do not all fetch
  if command -v setsid >/dev/null 2>&1; then setsid "$SELF" recipes update >/dev/null 2>>"$LOGFILE" </dev/null & disown
  else "$SELF" recipes update >/dev/null 2>>"$LOGFILE" </dev/null & disown; fi
}
registry_commit() { jq -r '.registryCommit' "$RECIPES"; }
gateway_image() { jq -r '.gateway.image // empty' "$RECIPES"; }

# match_hardware -> {"hardwareId":..,"gpu":{..},"reason":"..","gpus":[..]}
# gpus lists every card seen, each with its recipe's hardware id (or "") and whether it is the one
# in use, so the card can say what was detected and let the person choose. The default is the
# largest card that has a recipe (the tier map gives it the biggest model), ties by device order.
# `omarchy-local-ai gpu <backend:index>` pins a card; a pinned card without a recipe is still
# honoured, and the reason says so, because that is what the person asked to see.
GPU_PICK="$STATE/gpu"
gpu_pick() { printf '%s' "${OMARCHY_AI_GPU:-$(cat "$GPU_PICK" 2>/dev/null || true)}"; }
match_hardware() {
  local hw; hw=$(hardware_json)
  jq -c --argjson hw "$hw" --arg pick "$(gpu_pick)" '
    def norm: ascii_downcase|gsub("nvidia|geforce|intel|amd|radeon|generation|workstation|edition|[0-9]+gb|[^a-z0-9]";"");
    . as $file
    | [$hw.gpus | to_entries[] as $gi | $gi.value as $g
        | ([$file.hardware|to_entries[] as $e
            | select($g.backend==$e.value.match.backend)
            | select(($e.value.match.names|index($g.product|norm))!=null)
            | select(((($e.value.match.vramGb*1024)-$g.totalMiB)|fabs)<=1024)
            | $e.key] | .[0] // "") as $id
        | $g + {hardwareId:$id, key:($g.backend+":"+($g.index|tostring)), order:$gi.key,
                vramGb:(if $g.totalMiB==null then null else (($g.totalMiB/1024)+0.5|floor) end)}] as $gpus
    | ([$gpus[]|select(.key==$pick)]|.[0]) as $pinned
    | ([$gpus[]|select(.hardwareId!="")] | sort_by(-.totalMiB, -(.freeMiB // 0), .order) | .[0]) as $auto
    | ($pinned // $auto) as $use
    | {hardwareId:($use.hardwareId // ""), driver:($hw.driver // ""),
       gpu:(if $use==null then null else ($use|del(.hardwareId,.key,.order,.vramGb,.chosen)) end),
       reason:(if $use!=null and $use.hardwareId!="" then ""
               elif ($gpus|length)==0 then "no supported GPU detected"
               else ("no validated recipe for "+(($use // $gpus[0]).product)+" yet") end),
       pinned:($pinned!=null),
       gpus:[$gpus[] | {key, backend, index, product, vramGb, hardwareId, chosen:(.key==($use.key // "")), tempC:(.tempC // null), utilPct:(.utilPct // null),
                       usedGb:(if .usedMiB==null then null else ((.usedMiB/1024*10|round)/10) end)}]}' "$RECIPES"
}

# One card can carry more than one validated recipe: `.recipe` is the recommended one, `.recipes[]`
# the alternates. `omarchy-local-ai recipe <id>` picks one; a pick that is not among the chosen
# card's recipes is ignored (the card just changed), so the recommended one is the fallback.
RECIPE_PICK="$STATE/recipe-pick"
recipe_pick() { printf '%s' "${OMARCHY_AI_RECIPE:-$(cat "$RECIPE_PICK" 2>/dev/null || true)}"; }
# offered(): the shape checks of gate_reason a file can fail on its own (host networking or IPC, extra
# capabilities, a weakened profile): such a recipe is not offered at all rather than refused at Start
OFFERED='select(((.launch.networkMode//"bridge")=="bridge") and ((.launch.ipc//"")!="host") and (((.launch.capAdd//[])|length)==0) and (((.launch.securityOpt//[])|length)==0))'
recipes_for() { jq -c --arg h "$1" "[.hardware[\$h] | select(.!=null) | (.recipe // empty), (.recipes[]? // empty | $OFFERED)]" "$RECIPES"; }   # every recipe of a card, recommended first; a refused alternate is left out, a refused recommendation stays with its reason
# claimed_indexes <recipe-json> <match-json> -> {"indexes":[..],"backends":[..],"short":""}: every card the
# recipe claims (claims per hardware id, or `cards` of its own type), resolved to device indexes:
# the chosen card first, then the other cards of that type in device order. `short` names the
# first group that cannot be satisfied; a claim across backends cannot run in one container.
claimed_indexes() {
  jq -nc --argjson r "$1" --argjson m "$2" '
    ($r.claims // {($m.hardwareId): ($r.cards // 1)}) as $claims
    | ($claims | length) as $groups
    | reduce ($claims | to_entries[]) as $c ({indexes:[], backends:[], keys:[], short:""};
        ([$m.gpus[] | select(.hardwareId == $c.key)] | sort_by(if .chosen then 0 else 1 end)) as $pool
        | if ($pool|length) < $c.value then
            .short = (if .short != "" then .short else "recipe needs \($c.value) \(if $groups > 1 then $c.key + " " else "" end)cards, \($pool|length) detected" end)
          else .indexes += ($pool[:$c.value] | map(.index)) | .backends += ($pool[:$c.value] | map(.backend)) | .keys += ($pool[:$c.value] | map(.key)) end)
    | .backends |= unique
    | if .short == "" and (.backends|length) > 1 then .short = "recipe claims cards of different backends" else . end'
}
recipe_by_id() { jq -c --arg id "$1" '[.hardware[] | .recipe, (.recipes[]?)] | map(select(.id==$id)) | .[0] // null' "$RECIPES"; }   # the file's recipe of that id, or null
recipe_for() { jq -c --arg h "$1" --arg p "$(recipe_pick)" ".hardware[\$h] as \$c | if \$c==null then empty else (([\$c.recipes[]? | $OFFERED | select(.id==\$p)] | .[0]) // \$c.recipe // empty) end" "$RECIPES"; }

# gate_reason <recipe-json> -> one-line refusal on stdout; empty means launchable.
# Fail closed: anything malformed is refused. This is the trust boundary the marketplace reviewed.
gate_reason() {
  local r=$1 reason src tgt ro plug_root hf_root real
  plug_root=$(canon "$(dirname "$MODEL_ROOT")"); hf_root=$(canon "$HF_HOME_DIR")
  reason=$(jq -r '
    if (.id|test("^[a-z0-9][a-z0-9-]*$")|not) then "invalid recipe id"
    elif (.model.repository|test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")|not) then "invalid model repository"
    elif ((.weights.subdir//"")|test("^([A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*)?$")|not) then "invalid weights directory"
    elif ((.model.servedName//"")|test("[\"\\\\\\x27]")) then "invalid served model name"
    elif (.launch.image|test("@sha256:[0-9a-f]{64}$")|not) then "image is not digest-pinned"
    elif (.model.revision|test("^[0-9a-f]{40,64}$")|not) then "model revision is not pinned"
    elif ((.launch.networkMode//"bridge")!="bridge") then "requires \(.launch.networkMode) networking"
    elif ((.launch.ipc//"")=="host") then "requires host IPC"
    elif ((.launch.capAdd//[])|length)>0 then "requires extra kernel capabilities"
    elif ((.launch.securityOpt//[])|length)>0 then "requires a weakened security profile"
    elif ((.launch.containerPort|type)!="number") then "invalid container port"
    elif ([.launch.arguments[]?|select(test("enforce.eager|disable.?cuda.?graph";"i"))]|length)>0 then "disallowed launch argument"
    elif ([.launch|..|strings|select(test("\\$\\{(?!MODEL_ROOT\\}|CACHE_ROOT\\})"))]|length)>0 then "needs an unsupported placeholder"
    else empty end' <<<"$r" 2>/dev/null) || { printf 'recipe data failed validation\n'; return; }
  [[ -z $reason ]] || { printf '%s\n' "$reason"; return; }
  while IFS=$'\t' read -r src tgt ro; do
    case $src in
      '${MODEL_ROOT}/'*|'${CACHE_ROOT}/'*)
        [[ $src != *..* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        real=$(canon "$(expand_mount "$src")")
        [[ $real == "$plug_root"/* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        [[ $src != '${MODEL_ROOT}/'* || $ro == true ]] || { printf 'model weights must be mounted read-only\n'; return; } ;;
      '~/.cache/huggingface'|'~/.cache/huggingface/'*)
        [[ $src != *..* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; }
        real=$(canon "$HOME_DIR/${src#\~/}")
        [[ $real == "$hf_root" || $real == "$hf_root"/* ]] || { printf 'mounts unsafe host path %s\n' "$src"; return; } ;;
      asset/*) [[ ${src#asset/} != *..* && ${src#asset/} != */* && -n ${src#asset/} ]] || { printf 'unsafe asset path %s\n' "$src"; return; }
        jq -e --arg f "${src#asset/}" '.assets[$f]|type=="string"' "$RECIPES" >/dev/null || { printf 'asset %s is not shipped\n' "$src"; return; } ;;
      /dev/dri/by-path) ;;
      *) printf 'mounts unsafe host path %s\n' "$src"; return ;;
    esac
  done < <(jq -r '.launch.mounts[]?|[.source,.target,(.read_only//false|tostring)]|@tsv' <<<"$r")
}

expand_mount() { local s=$1; s=${s//'${MODEL_ROOT}'/$MODEL_ROOT}; s=${s//'${CACHE_ROOT}'/$CACHE_ROOT}; printf '%s' "$s"; }
