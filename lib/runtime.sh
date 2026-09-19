#!/usr/bin/env bash
# Containers: one engine+gateway pair per running model, acceptance, rollback. Sourced; do not run.
#
# A running model is a slot: the recipe's engine on a private bridge network of its own, its port
# never published, and the attested gateway on 127.0.0.1:<slot port> (12434 for the first model,
# the next free port for each further one), key enforced. Slots live in the ledger under .slots,
# keyed by recipe id, with the container names, network, port, the cards they claim and the
# acceptance record. Both containers carry io.omarchy.local-ai=1, .recipe, .registry, .role; only
# labeled containers are ever touched. A Start replaces the slots whose cards it claims (its own
# earlier run included): those are set aside first and come back if the new one fails acceptance.
# Models on other cards keep running throughout.

owned() { [[ $(docker inspect -f "{{index .Config.Labels \"$LABEL\"}}" "$1" 2>/dev/null) == 1 ]]; }
exists() { docker inspect "$1" >/dev/null 2>&1; }
running() { [[ $(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null) == true ]]; }
live() { docker inspect -f "{{.State.Running}}|{{index .Config.Labels \"$LABEL\"}}|{{index .Config.Labels \"$LABEL.recipe\"}}" "$1" 2>/dev/null; }   # "true|1|<recipe>" when ours and running
owned_names() { docker ps -a --filter "label=$LABEL=1" --format '{{.Names}}' 2>/dev/null; }   # every container of ours, running or not

# ---------------------------------------------------------------- slots
slot_of() { lread | jq -c --arg id "$1" '.slots[$id] // empty'; }
slot_ids() { lread | jq -r '.slots | keys[]'; }
engine_of() { local s; s=$(slot_of "$1"); if [[ -n $s ]]; then jq -r .engine <<<"$s"; else printf '%s-%s-engine' "$CTR" "$1"; fi; }
gateway_of() { local s; s=$(slot_of "$1"); if [[ -n $s ]]; then jq -r .gateway <<<"$s"; else printf '%s-%s-gateway' "$CTR" "$1"; fi; }
net_of() { local s; s=$(slot_of "$1"); if [[ -n $s ]]; then jq -r .net <<<"$s"; else printf '%s-%s' "$NET" "$1"; fi; }
free_port() { # the lowest port from $PORT up that no slot holds and nothing listens on
  local used p; used=$(lread | jq -r '.slots[].port')
  for ((p = PORT; p < PORT + 16; p++)); do
    grep -qx "$p" <<<"$used" && continue
    [[ $(PORT=$p port_listener) == none ]] && { printf '%s' "$p"; return 0; }
  done
  fail "no free port between $PORT and $((PORT + 15))"; return 1
}
slot_port() { # slot_port <recipe-id>: its own port when it already runs (agents keep the address), else a free one
  local s; s=$(slot_of "$1"); if [[ -n $s ]]; then jq -r .port <<<"$s"; else free_port; fi
}
# slot_plan <recipe-json> -> the recipe with .slot {port, net, engine, gateway} and .victims: the slots a Start
# of it replaces, its own earlier run and every slot holding one of the cards it claims
slot_plan() {
  local r=$1 id port; id=$(jq -r .id <<<"$r"); port=$(slot_port "$id") || return 1
  jq -c --argjson p "$port" --arg net "$(net_of "$id")" --arg e "$(engine_of "$id")" --arg g "$(gateway_of "$id")" --argjson slots "$(lread | jq -c .slots)" '
    (.gpuKeys // []) as $keys
    | . + {slot:{port:$p, net:$net, engine:$e, gateway:$g},
           victims:[$slots | to_entries[] | select(.key==$id or (((.value.keys // []) | map(. as $k | $keys | index($k)) | map(select(.!=null)) | length) > 0))
                    | {id:.key, name:(.value.name // .key), engine:.value.engine, gateway:.value.gateway}]}' --arg id "$id" <<<"$r"
}
slot_record() { # slot_record <recipe-json>: the new slot in the ledger, unverified until accept() fills .accepted
  local r=$1
  lwrite '.slots[$id]={port:$r.slot.port, net:$r.slot.net, engine:$r.slot.engine, gateway:$r.slot.gateway, keys:($r.gpuKeys // []), name:($r.model.name // $id), accepted:null, startedAt:$t}' \
    --arg id "$(jq -r .id <<<"$r")" --argjson r "$r" --arg t "$(now)"
}
slot_forget() { lwrite 'del(.slots[$id])' --arg id "$1"; }
slots_file() { # the every-slot file the gateway restart phase reads (share on/off republishes every gateway)
  state_dir; local out="$STATE/gateway.recipe.json.tmp.$$" id f; echo '[' >"$out"; local first=1
  while IFS= read -r id; do [[ -n $id ]] || continue; f="$STATE/slots/$id.json"; [[ -s $f ]] || continue
    (( first )) || echo ',' >>"$out"; first=0; cat "$f" >>"$out"; done < <(slot_ids)
  echo ']' >>"$out"; mv "$out" "$STATE/gateway.recipe.json"
}

ensure_network() { # ensure_network <name>: ours, or created; a same-named network of someone else's is refused, since the engine is reachable on it
  local l; if l=$(docker network inspect -f "{{index .Labels \"$LABEL\"}}" "$1" 2>/dev/null); then [[ $l == 1 ]] || { fail "docker network $1 exists but is not managed by this plugin"; return 1; }
  else docker network create --label "$LABEL=1" "$1" >/dev/null; fi
}
drop_network() { docker network rm "$1" >/dev/null 2>&1 || true; }   # best effort: a network still in use stays

# write_assets <recipe>: config files the recipe mounts, from recipes.json, into a plugin-owned dir
write_assets() {
  local r=$1 f; state_dir; mkdir_shared "$STATE/assets"   # the engine container reads these as its own uid
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    (umask 022; jq -r --arg f "$f" '.assets[$f]' "$RECIPES" >"$STATE/assets/$f")
  done < <(jq -r '.launch.mounts[]?|.source|select(startswith("asset/"))|ltrimstr("asset/")' <<<"$r")
}

cdi_amd_available() {
  local info
  info=$(deadline 5 docker info 2>/dev/null) || return 1
  grep -q "cdi: amd.com/gpu=" <<<"$info"
}

engine_argv() { # engine_argv <recipe> -> NUL-separated docker argv
  local r=$1 id backend src tgt mode v real name net
  id=$(jq -r .id <<<"$r"); backend=$(jq -r .match.backend <<<"$r"); name=$(jq -r .slot.engine <<<"$r"); net=$(jq -r .slot.net <<<"$r")
  local -a a=(docker run --detach --name "$name" --restart unless-stopped --network "$net" --network-alias engine
    --label "$LABEL=1" --label "$LABEL.recipe=$id" --label "$LABEL.registry=$(registry_commit)" --label "$LABEL.role=engine")
  if [[ $backend == nvidia ]]; then
    # docker's --gpus value is a csv: a list of devices must be quoted as one field, or "device=0,1"
    # reads as device 0 plus count 1 ("cannot set both Count and DeviceIDs")
    local ids; ids=$(jq -r '(.gpuIndexes // [.gpuIndex]) | map(tostring) | join(",")' <<<"$r")
    if [[ $ids == *,* ]]; then a+=(--gpus "\"device=$ids\""); else a+=(--gpus "device=$ids"); fi
  elif [[ $backend == amd-rocm ]]; then
    # CDI when amd-ctk has produced a spec; KFD+render otherwise. Same HSA surface for the engine.
    if cdi_amd_available; then
      # Claimed indexes only — never amd.com/gpu=all. Tensor-parallel needs every claimed card
      # visible, but extra AMD devices (an iGPU, a third dGPU) would appear as HIP devices and
      # break vLLM's --tensor-parallel-size. NVIDIA uses the same gpuIndexes list via --gpus.
      # AMD CDI has no comma form: one --device amd.com/gpu=N per card.
      local id; local -a cdi=()
      while IFS= read -r id; do
        [[ $id =~ ^[0-9]+$ ]] || continue
        cdi+=(--device "amd.com/gpu=$id")
      done < <(jq -r '(.gpuIndexes // [.gpuIndex])[]?' <<<"$r")
      ((${#cdi[@]})) || { fail "no AMD GPU indexes for CDI"; return 1; }
      a+=("${cdi[@]}" --group-add video --group-add render)
    else
      local -a nodes=()
      while IFS= read -r real; do
        [[ $real =~ ^/dev/dri/renderD[0-9]+$ ]] || { fail "no render node for a selected AMD GPU"; return 1; }
        nodes+=(--device "$real:$real")
      done < <(jq -r '(.gpuRenderNodes // [.gpuRenderNode])[]? // empty' <<<"$r")
      ((${#nodes[@]})) || { fail "no render nodes for selected AMD GPUs"; return 1; }
      a+=(--device /dev/kfd:/dev/kfd "${nodes[@]}" --group-add video --group-add render)
    fi
  else # Intel: render nodes only, resolved per device; no card* control nodes, no whole /dev/dri
    local -a nodes=()
    for v in "${OMARCHY_AI_DRI_PATH:-/dev/dri/by-path}"/*-render; do [[ -e $v ]] || continue; real=$(canon "$v"); nodes+=(--device "$real:$real"); done
    ((${#nodes[@]})) || { fail "no render nodes found"; return 1; }
    a+=("${nodes[@]}" --volume /dev/dri/by-path:/dev/dri/by-path:ro)
  fi
  v=$(jq -r '.launch.shm//empty' <<<"$r"); [[ -n $v ]] && a+=(--shm-size "$v")
  while IFS=$'\t' read -r src tgt mode; do
    [[ -n $src && -n $tgt ]] || continue
    case $src in
      '${MODEL_ROOT}/'*|'${CACHE_ROOT}/'*) real=$(canon "$(expand_mount "$src")"); [[ -n ${OMARCHY_AI_ROOT_PHASE:-} ]] || mkdir_shared "$real" ;;
      '~/.cache/huggingface'*) real=$(canon "$HOME_DIR/${src#\~/}"); [[ -n ${OMARCHY_AI_ROOT_PHASE:-} ]] || mkdir_shared "$real" ;;
      asset/*) real="$STATE/assets/${src#asset/}"; mode=":ro" ;;
      /dev/dri/by-path) real=$src ;;
      *) fail "mount outside boundary: $src"; return 1 ;;
    esac
    a+=(--volume "$real:$tgt$mode")
  done < <(jq -r '.launch.mounts[]?|[.source,.target,(if .read_only then ":ro" else "" end)]|@tsv' <<<"$r")
  while IFS= read -r v; do a+=(--env "$v"); done < <(jq -r '.launch.environment|to_entries[]?|"\(.key)=\(.value)"' <<<"$r")
  v=$(jq -r '.launch.entrypoint//empty' <<<"$r"); [[ -n $v ]] && a+=(--entrypoint "$v")
  a+=("$(jq -r .launch.image <<<"$r")")
  local cap; cap=$(memory_cap "$r"); local prev=""
  while IFS= read -r v; do
    # a validated recipe asks for the share of the card it had on a bare machine; on a card that also
    # drives the desktop (Hyprland holds gigabytes) that share is not there, so it is lowered to what is free
    if [[ $prev == --gpu-memory-utilization && -n $cap ]] && awk -v v="$v" -v c="$cap" 'BEGIN{exit !(v>c)}'; then log "gpu memory utilization $v lowered to $cap: that is what is free on the card"; v=$cap; fi
    a+=("$v"); prev=$v
  done < <(jq -r '.launch.arguments[]?' <<<"$r")
  printf '%s\0' "${a[@]}"
}
memory_cap() { # memory_cap <recipe> -> the largest --gpu-memory-utilization the claimed NVIDIA cards can honour right now (two decimals), or empty
  local r=$1; [[ $(jq -r .match.backend <<<"$r") == nvidia ]] || return 0
  hardware_json | jq -r --argjson idx "$(jq -c '.gpuIndexes // [.gpuIndex]' <<<"$r")" '
    [.gpus[] | select(.backend=="nvidia" and (.index as $i | $idx | index($i)) != null and .freeMiB != null and .totalMiB > 0)
     | (.freeMiB / .totalMiB * 100 | floor) / 100] | if length == 0 then empty else (min | if . < 0.1 then 0.1 else . end) end'
}

gateway_argv() { # gateway_argv <recipe>
  local r=$1 img port; img=$(gateway_image); [[ -n $img ]] || { fail "recipes.json has no gateway image"; return 1; }
  port=$(jq -r .slot.port <<<"$r")
  # as this user: the image's own uid (10001) cannot read the 0600 key file, and a gateway that
  # cannot read its key silently serves keyless. The port needs no root.
  printf '%s\0' docker run --detach --name "$(jq -r .slot.gateway <<<"$r")" --restart unless-stopped --network "$(jq -r .slot.net <<<"$r")" \
    --user "$RUN_AS" --publish "127.0.0.1:$port:12434" --label "$LABEL=1" --label "$LABEL.recipe=$(jq -r .id <<<"$r")" \
    --label "$LABEL.registry=$(registry_commit)" --label "$LABEL.role=gateway"
  share_publish_argv "$port"   # the tailnet address too, while sharing is on
  printf '%s\0' --env "UPSTREAM=http://engine:$(jq -r .launch.containerPort <<<"$r")" --env "MODEL=$(jq -r .model.servedName <<<"$r")" \
    --env GATEWAY_KEY_FILE=/run/gateway.key --volume "$KEY_FILE:/run/gateway.key:ro" "$img"
}
# argv builders run in a subshell and can fail halfway (a mount root that cannot be made, a recipe
# field missing); a process substitution would hand docker the truncated half. Build into a file
# and check the builder's own status first.
read_argv() { # read_argv <builder> <recipe> -> ARGV (no namerefs: the suite runs on bash 3.2 too)
  local f; f=$(mktemp) || return 1
  if ! "$1" "$2" >"$f"; then rm -f "$f"; return 1; fi
  ARGV=(); local v; while IFS= read -r -d '' v; do ARGV+=("$v"); done <"$f"; rm -f "$f"
  ((${#ARGV[@]}))
}
start_gateway() { # start_gateway <recipe>: the slot's gateway container
  local r=$1; local -a argv=()
  read_argv gateway_argv "$r" || { fail "could not build the gateway command"; return 1; }; argv=("${ARGV[@]}")
  log "gateway: ${argv[*]}"
  run_child "${argv[@]}" >&2 2>&1
}
restart_gateways() { # every slot's gateway, fresh publish list (share on/off); engines untouched. User side: one privileged phase.
  slots_file
  [[ $(jq 'length' "$STATE/gateway.recipe.json") -gt 0 ]] || { fail "no gateway to restart"; return 1; }
  privileged restart_gateway "$STATE/gateway.recipe.json" >"$STATE/phase.out" 2>>"$LOGFILE" || { local why; why=$(grep '^reason ' "$STATE/phase.out" | tail -1 | cut -c8-); fail "${why:-the gateway did not restart (see $LOGFILE)}"; return 1; }
  local i port; port=$(jq -r '.[0].slot.port' "$STATE/gateway.recipe.json")
  for ((i=0; i<15; i++)); do PORT=$port api models 2 >/dev/null 2>&1 && return 0; sleep "${POLL:-1}"; done
  PORT=$port api models 2 >/dev/null 2>&1
}
gateway_up() { # gateway_up [port]: a slot's gateway answers (any slot's when no port is given)
  local p; if [[ -n ${1:-} ]]; then PORT=$1 api models 2 >/dev/null 2>&1; return; fi
  while IFS= read -r p; do [[ -n $p ]] && PORT=$p api models 2 >/dev/null 2>&1 && return 0; done < <(lread | jq -r '.slots[].port')
  return 1
}

# The bearer header travels to curl as a file (`-H @file`, 0600), never as an argument: argv is
# readable by every local account through /proc/<pid>/cmdline while the request runs.
AUTH_FILE="$STATE/gateway.auth"
auth_file() { # -> path of a 0600 file holding the Authorization header for the current key
  local want; want="Authorization: Bearer $(cat "$KEY_FILE")"
  [[ -f $AUTH_FILE && $(cat "$AUTH_FILE") == "$want" ]] || { state_dir; printf '%s\n' "$want" >"$AUTH_FILE.tmp.$$" && mv "$AUTH_FILE.tmp.$$" "$AUTH_FILE"; }
  printf '%s' "$AUTH_FILE"
}
api() { curl -fsS --max-time "${2:-30}" --max-filesize 1048576 -H "@$(auth_file)" "http://127.0.0.1:$PORT/v1/$1"; }
post() { curl -fsS --max-time 600 --max-filesize 4194304 -H 'Content-Type: application/json' -H "@$(auth_file)" -d "$2" "http://127.0.0.1:$PORT/v1/$1"; }

# engine_alive <engine>: the engine is up and not crash-looping. Under --restart unless-stopped docker keeps
# a container that exits at once "running" (State.Running stays true while it restarts), so a broken
# engine would otherwise wait out the whole acceptance timeout; its last log line is the reason.
engine_alive() {
  local e=$1 st running restarting count
  st=$(docker inspect -f '{{.State.Running}}|{{.State.Restarting}}|{{.RestartCount}}' "$e" 2>/dev/null) || { fail "engine exited during startup (docker logs $e)"; return 1; }
  running=${st%%|*}; restarting=${st#*|}; count=${restarting#*|}; restarting=${restarting%%|*}
  [[ $running == true ]] || { fail "engine exited during startup (docker logs $e)"; return 1; }
  [[ $restarting == true || ${count:-0} -ge 2 ]] || return 0
  fail "engine keeps crashing: $(engine_last_line "$e") (docker logs $e)"; return 1
}
engine_last_line() { docker logs --tail 40 "$1" 2>&1 | grep -v '^[[:space:]]*$' | grep -Ev '^[[:space:]]*(File "|\^+$|Traceback|return |raise |[A-Za-z_.]+\()' | tail -1 | cut -c1-140; }

# accept <recipe>: the model is what the recipe says, all three dialects answer through the slot's gateway,
# a tool call works when the recipe claims tools, and decode speed is not a CPU fallback.
accept() {
  local r=$1 id want served reply deadline=$((SECONDS+TIMEOUT)) t0 t1 toks tps floor apis='[]' engine models context expected
  local PORT; PORT=$(jq -r .slot.port <<<"$r"); engine=$(jq -r .slot.engine <<<"$r")   # every probe below goes to this slot
  id=$(jq -r .id <<<"$r"); want=$(jq -r .model.servedName <<<"$r")
  while :; do
    models=$(api models 5 2>/dev/null || true)
    served=$(jq -r '.data[0].id // empty' <<<"$models" 2>/dev/null || true)
    [[ -n $served ]] && break
    (( SECONDS < deadline )) || { fail "engine did not answer within ${TIMEOUT}s"; return 1; }
    if docker_direct; then engine_alive "$engine" || return 1; fi   # behind a prompt, the deadline decides
    op starting "$id" "loading the model" 0; sleep "$POLL"
  done
  [[ $served == "$want" || $want == */* && $served == *"${want##*/}"* ]] || { fail "served model $served is not $want"; return 1; }
  context=$(jq -r '.data[0] | .max_model_len // .meta.n_ctx // 0' <<<"$models")
  expected=$(jq -r '.serving.ctxTokens // 0' <<<"$r")
  (( context == 0 || context >= expected )) || { fail "runtime context $context is below the recipe's $expected tokens"; return 1; }
  # a gateway that cannot read its key file serves keyless without a word; sharing that on a
  # tailnet is the one thing this plugin must never do, so an unkeyed request has to be refused
  if curl -fsS --max-time 10 --max-filesize 1048576 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    fail "gateway answers without the key (docker logs $(jq -r .slot.gateway <<<"$r"))"; return 1
  fi
  op starting "$id" "chat acceptance" 0
  reply=$(post chat/completions "$(jq -nc --arg m "$served" '{model:$m,stream:false,messages:[{role:"user",content:"Reply with exactly: LOCAL_AI_READY"}]}')") || { fail "chat completion failed"; return 1; }
  jq -e '[(.choices[0].message.content//""),(.choices[0].message.reasoning_content//"")]|join(" ")|contains("LOCAL_AI_READY")' >/dev/null <<<"$reply" || { fail "chat acceptance failed"; return 1; }
  usage_note "$(jq -r '.usage.prompt_tokens // 0' <<<"$reply")" "$(jq -r '.usage.completion_tokens // 0' <<<"$reply")" "$id"
  # decode speed, coarsely: this exists to catch a CPU fallback (one or two tok/s), not to benchmark.
  # Engines do not all report usage (TabbyAPI does not), so tokens fall back to words written,
  # thinking included, at 1.3 tokens a word. Two runs, the better counts: the first is cold. The
  # floor is a tenth of the validated speed, never under 3.
  op starting "$id" "speed check" 0
  local best=0 i
  for i in 1 2; do
    t0=$(date +%s%N)
    reply=$(post chat/completions "$(jq -nc --arg m "$served" '{model:$m,stream:false,max_tokens:160,messages:[{role:"user",content:"Count from 1 to 80 separated by single spaces. Write nothing else."}]}')") || { fail "speed check request failed"; return 1; }
    t1=$(date +%s%N)
    toks=$(jq -r '.usage.completion_tokens // 0' <<<"$reply")
    (( toks > 0 )) || toks=$(jq -r '[(.choices[0].message.content//""),(.choices[0].message.reasoning_content//"")]|join(" ")|[splits("\\s+")|select(length>0)]|length|.*1.3|floor' <<<"$reply")
    tps=$(( toks * 1000000000 / (t1 - t0 + 1) )); (( tps > best )) && best=$tps
    usage_note "$(jq -r '.usage.prompt_tokens // 0' <<<"$reply")" "$toks" "$id"
  done
  tps=$best
  # a reasoning model whose engine is not splitting: the closing think tag lands in the answer text,
  # and every agent renders the model's thinking as its reply (a tester's finding on TabbyAPI)
  jq -e '(.choices[0].message.content//"")|test("</think>|<\\|end_of_thought\\|>")' >/dev/null <<<"$reply" \
    && { fail "reasoning leaks into the answer: the engine's reasoning parser is off for this model"; return 1; }
  floor=$(jq -r '[3, ((.speed.tps//0)/10|floor)]|max' <<<"$r")
  (( toks < 16 || tps >= floor )) || { fail "decode ${tps} tok/s is below the ${floor} tok/s floor: the GPU is not being used (driver too old for this image?)"; return 1; }
  apis='["chat"]'
  # prefill speed, as coarsely: a long prompt with a one-word answer, timed whole, minus the decode
  # share at the rate just measured. The panel's stats show it; nothing is gated on it.
  op starting "$id" "prefill check" 0
  local prefill=0 ptxt ptoks ctoks ns
  ptxt=$(printf 'The quick brown fox jumps over the lazy dog near the quiet river bank at dawn. %.0s' {1..80})
  t0=$(date +%s%N)
  if reply=$(post chat/completions "$(jq -nc --arg m "$served" --arg p "$ptxt" '{model:$m,stream:false,messages:[{role:"user",content:($p+"\nReply with exactly: OK")}]}')"); then
    t1=$(date +%s%N)
    ptoks=$(jq -r '.usage.prompt_tokens // 0' <<<"$reply"); (( ptoks > 0 )) || ptoks=$(( ${#ptxt} / 4 ))
    ctoks=$(jq -r '.usage.completion_tokens // 0' <<<"$reply")
    (( ctoks > 0 )) || ctoks=$(jq -r '[(.choices[0].message.content//""),(.choices[0].message.reasoning_content//"")]|join(" ")|[splits("\\s+")|select(length>0)]|length|.*1.3|floor' <<<"$reply")
    ns=$(( t1 - t0 )); (( tps > 0 )) && ns=$(( ns - ctoks * 1000000000 / tps )); (( ns < 1000000 )) && ns=1000000
    prefill=$(( ptoks * 1000000000 / ns ))
    usage_note "$ptoks" "$ctoks" "$id"
  fi
  op starting "$id" "messages acceptance" 0
  # the shapes agents really send: a system prompt plus a prior turn (Messages), instructions plus a
  # developer item after the user (Responses); a template that refuses a late system message fails here
  reply=$(post messages "$(jq -nc --arg m "$served" '{model:$m,max_tokens:2048,system:"You are a terse assistant.",messages:[{role:"user",content:"hi"},{role:"assistant",content:"hello"},{role:"user",content:"Reply with exactly: LOCAL_AI_READY"}]}')") \
    && jq -e '[.content[]?|select(.type=="text")|.text]|join(" ")|contains("LOCAL_AI_READY")' >/dev/null <<<"$reply" && apis=$(jq -c '.+["messages"]' <<<"$apis")
  op starting "$id" "responses acceptance" 0
  reply=$(post responses "$(jq -nc --arg m "$served" '{model:$m,instructions:"You are a terse assistant.",input:[{type:"message",role:"user",content:"Reply with exactly: LOCAL_AI_READY"},{type:"message",role:"developer",content:"Reply with the exact token requested."}]}')") \
    && jq -e '[.output[]?|select(.type=="message")|.content[]?|.text]|join(" ")|contains("LOCAL_AI_READY")' >/dev/null <<<"$reply" && apis=$(jq -c '.+["responses"]' <<<"$apis")
  if [[ $(jq -r '.capabilities.tools//false' <<<"$r") == true ]]; then
    op starting "$id" "tool-call acceptance" 0
    # the schema carries a regex pattern with an escape llama.cpp's grammar cannot take and a format hint,
    # as Claude Code's tools do: the gateway must scrub them or this fails here rather than in the agent
    local tools='[{"type":"function","function":{"name":"shell","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string","pattern":"^[A-Za-z0-9 _\\\\-.~:@+]+$"},"cwd":{"type":"string","format":"uri"}},"required":["command"]}}}]'
    reply=$(post chat/completions "$(jq -nc --arg m "$served" --argjson t "$tools" '{model:$m,stream:false,tools:$t,tool_choice:"auto",messages:[{role:"user",content:"Use the shell tool to run: echo LOCAL_AI_TOOL_OK"}]}')") || { fail "tool-call request failed"; return 1; }
    jq -e '[(.choices[0].message.tool_calls//[])[]|select(.function.name=="shell" and ((.function.arguments//"")|contains("LOCAL_AI_TOOL_OK")))]|length>0' >/dev/null <<<"$reply" || { fail "tool-call acceptance failed"; return 1; }
  fi
  local capability kind data
  for capability in vision video; do
    [[ $(jq -r --arg c "$capability" '.capabilities[$c] // false' <<<"$r") == true ]] || continue
    # Tiny red image/clip, embedded so readiness needs no loose media or encoder.
    if [[ $capability == vision ]]; then kind=image; data='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAABWklEQVR4nO3OQQ0AMBAEofVv+iqDxzRBALvtg/wgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwgzg/i/CDOD+L8IM4P4vwg7gEgaMOyrMtNTwAAAABJRU5ErkJggg=='
    else kind=video; data='data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAx1tZGF0AAACrQYF//+p3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTQgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTIgc2NlbmVjdXQ9NDAgaW50cmFfcmVmcmVzaD0wIHJjX2xvb2thaGVhZD00MCByYz1jcmYgbWJ0cmVlPTEgY3JmPTIzLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MToxLjAwAIAAAAA2ZYiEABX//uzPfgU2aOYvw/FFc458deOY06aGeK6v9N+afVASVgFUuILmpqmI2AAOAA7RYPe1AAAADEGaI2xBL/61KoAZkAAAAAlBnkF4gn8AB90AAAAJAZ5iakEvAAwIAAADYm1vb3YAAABsbXZoZAAAAAAAAAAAAAAAAAAAA+gAAAfQAAEAAAEAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAKNdHJhawAAAFx0a2hkAAAAAwAAAAAAAAAAAAAAAQAAAAAAAAfQAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAACAAAAAgAAAAAAAJGVkdHMAAAAcZWxzdAAAAAAAAAABAAAH0AAAQAAAAQAAAAACBW1kaWEAAAAgbWRoZAAAAAAAAAAAAAAAAAAAQAAAAIAAVcQAAAAAAC1oZGxyAAAAAAAAAAB2aWRlAAAAAAAAAAAAAAAAVmlkZW9IYW5kbGVyAAAAAbBtaW5mAAAAFHZtaGQAAAABAAAAAAAAAAAAAAAkZGluZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAFwc3RibAAAAMBzdHNkAAAAAAAAAAEAAACwYXZjMQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAACAAIAASAAAAEgAAAAAAAAAARRMYXZjNjMuMS4xMDEgbGlieDI2NAAAAAAAAAAAAAAAABj//wAAADZhdmNDAWQACv/hABlnZAAKrNlCBGwEQAAAAwBAAAADAQPEiWWAAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAAxUAAAAAAAAABhzdHRzAAAAAAAAAAEAAAAEAAAgAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAKGN0dHMAAAAAAAAAAwAAAAEAAEAAAAAAAQAAgAAAAAACAAAgAAAAABxzdHNjAAAAAAAAAAEAAAABAAAABAAAAAEAAAAkc3RzegAAAAAAAAAAAAAABAAAAusAAAAQAAAADQAAAA0AAAAUc3RjbwAAAAAAAAABAAAAMAAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAAABxkYXRhAAAAAQAAAABMYXZmNjMuMS4xMDE='; fi
    op starting "$id" "$capability acceptance" 0
    reply=$(post chat/completions "$(jq -nc --arg m "$served" --arg kind "$kind" --arg data "$data" '
      {model:$m,stream:false,max_tokens:64,chat_template_kwargs:{enable_thinking:false},messages:[{role:"user",content:[
        {type:"text",text:("What single color fills this "+$kind+"? Answer one word.")},
        {type:($kind+"_url"),($kind+"_url"):{url:$data}}]}]}')") || { fail "$capability request failed"; return 1; }
    jq -e '(.choices[0].message.content // "") | ascii_downcase | test("\\bred\\b")' <<<"$reply" >/dev/null || { fail "$capability acceptance failed"; return 1; }
  done
  lwrite '.slots[$id].accepted={servedModel:$s,registry:$g,apis:$a,tps:($t|tonumber),prefillTps:($p|tonumber),contextTokens:$ctx,at:$when}' --arg id "$id" --arg s "$served" --arg g "$(registry_commit)" --argjson a "$apis" --arg t "$tps" --arg p "$prefill" --argjson ctx "$context" --arg when "$(now)"
  log "accepted $id served=$served port=$PORT tps=$tps prefill=$prefill apis=$apis"
}


# The pair of every victim -> *-previous (removing any older previous). Phase-safe: names come from the recipe file.
set_aside() { # set_aside <recipe-json>
  local r=$1 c
  while IFS= read -r c; do
    [[ -n $c ]] || continue
    exists "$c" || continue
    owned "$c" || { fail "$c exists but is not managed by this plugin"; return 1; }
    if exists "$c-previous"; then owned "$c-previous" || { fail "$c-previous is not managed by this plugin"; return 1; }; docker rm -f "$c-previous" >/dev/null 2>&1; fi
    running "$c" && docker stop "$c" >/dev/null 2>&1
    docker rename "$c" "$c-previous" >/dev/null || { fail "could not set aside $c"; return 1; }
  done < <(jq -r '.victims[]? | .engine, .gateway' <<<"$r")
}
restore_previous() { # restore_previous <recipe-json>: the new pair goes, every set-aside pair comes back; non-zero when one could not
  local r=$1 c ok=0
  for c in $(jq -r '.slot.engine, .slot.gateway' <<<"$r"); do exists "$c" && owned "$c" && docker rm -f "$c" >/dev/null 2>&1; done
  while IFS= read -r c; do
    [[ -n $c ]] || continue
    if exists "$c-previous" && owned "$c-previous"; then docker rename "$c-previous" "$c" >/dev/null 2>&1 && docker start "$c" >/dev/null 2>&1 || ok=1; fi
  done < <(jq -r '.victims[]? | .engine, .gateway' <<<"$r")
  return $ok
}
drop_previous() { # every set-aside pair of ours goes: a Start that succeeded, or a stale one from a Start that died
  local c; while IFS= read -r c; do [[ $c == *-previous ]] && docker rm -f "$c" >/dev/null 2>&1; done < <(owned_names); return 0
}
stop_slot() { # stop_slot <recipe-json>: its pair, its set-aside pair, its network
  local r=$1 c
  for c in $(jq -r '.slot.engine, .slot.gateway' <<<"$r"); do
    exists "$c" && owned "$c" && docker rm -f "$c" >/dev/null 2>&1
    exists "$c-previous" && owned "$c-previous" && docker rm -f "$c-previous" >/dev/null 2>&1
    exists "$c" && owned "$c" && { fail "$c could not be removed"; return 1; }
  done
  drop_network "$(jq -r .slot.net <<<"$r")"; return 0
}
stop_all() { # every container of ours; non-zero when one is still there afterwards
  local c; while IFS= read -r c; do [[ -n $c ]] && docker rm -f "$c" >/dev/null 2>&1; done < <(owned_names)
  while IFS= read -r c; do [[ -n $c ]] && { fail "$c could not be removed"; return 1; }; done < <(owned_names)
  return 0
}

start_pair() { # start_pair <recipe>: network, engine, then gateway; returns non-zero on any failure. Assets and key exist already.
  local r=$1; local -a argv=()
  ensure_network "$(jq -r .slot.net <<<"$r")" || return 1
  read_argv engine_argv "$r" || { fail "could not build the engine command (see $LOGFILE)"; return 1; }; argv=("${ARGV[@]}")
  log "engine: ${argv[*]}"
  run_child "${argv[@]}" >&2 2>&1 || return 1
  start_gateway "$r" || return 1
}
