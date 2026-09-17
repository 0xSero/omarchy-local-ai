#!/usr/bin/env bash
# Agents: launch-only. Sourced; do not run.
#
# The local model reaches an agent only when the agent is launched from the panel: the endpoint,
# key, and model travel in the launch command's environment and flags. Nothing on disk that the
# user owns is edited, so nothing has to be restored when the plugin stops. Agents whose API
# dialect failed acceptance are hidden; the rest are the agents Omarchy itself knows how to launch.

AGENTS=(pi omp opencode ori claude codex grok agy hermes copilot crush)
ENDPOINT="http://127.0.0.1:$PORT"   # open_agent points it at the model's own port before building the command

agents_json() { # agents_json <apis-json> -> {"default":"pi","installed":["pi",...],"launchable":[...]} against a model's accepted dialects
  local apis=${1:-[]} def="" found=""
  for a in "${AGENTS[@]}"; do bin_of "$a" >/dev/null 2>&1 && found+="$a "; done   # installed only; one jq pass below splits installed from launchable
  command -v omarchy-default-agent >/dev/null 2>&1 && def=$(omarchy-default-agent 2>/dev/null || true)
  jq -nc --arg found "$found" --arg d "${def:-}" --argjson apis "$apis" '
    ($found|split(" ")|map(select(.!=""))) as $i
    | {default:$d, installed:$i,
       launchable:[$i[]|. as $a|select($apis|index((if $a=="claude" then "messages" elif $a=="codex" then "responses" else "chat" end))!=null)]}'
}

# agent_command <name> <served-model> <key-file> -> prints the argv (NUL-separated) to run in a terminal.
# Each agent gets its own spelling of "use this endpoint". The key never enters argv: with_key
# prefixes a tiny bash stage that reads the key file into the named variables and execs the agent,
# so /proc/<pid>/cmdline shows the file's path and the variable names, nothing more. Agents that
# take the key only from a file get it in a 0600 plugin-owned file.
with_key() { # with_key <VAR>... : the stage, then the caller appends the agent's own argv
  printf '%s\0' bash -c 'k=$(cat "$1") || exit 1; shift; while [[ $1 != -- ]]; do export "$1=$k"; shift; done; shift; exec "$@"' omarchy-local-ai-agent "$KEY_FILE" "$@" --
}
agent_command() {
  local name=$1 model=$2 key_file=$3 context=${4:-131072} vision=${5:-false} bin cfg key
  bin=$(bin_of "$name") || { fail "$name is not installed"; return; }
  key=$(cat "$key_file")   # for the files written below only; it goes into no argument
  case $name in
    claude)
      # a bearer token, not an API key: Claude Code asks "use this API key?" for every new
      # ANTHROPIC_API_KEY and remembers a refusal, while ANTHROPIC_AUTH_TOKEN is its documented form
      # for gateways and is used as-is. The gateway accepts Authorization: Bearer.
      with_key ANTHROPIC_AUTH_TOKEN
      printf '%s\0' env "ANTHROPIC_BASE_URL=$ENDPOINT" "ANTHROPIC_MODEL=$model" \
        "ANTHROPIC_DEFAULT_SONNET_MODEL=$model" "ANTHROPIC_DEFAULT_OPUS_MODEL=$model" "ANTHROPIC_DEFAULT_HAIKU_MODEL=$model" \
        "$bin" --model "$model" ;;
    codex)
      with_key LOCAL_AI_KEY
      printf '%s\0' "$bin" \
        -c "model_providers.local.name=Omarchy Local" -c "model_providers.local.base_url=$ENDPOINT/v1" \
        -c "model_providers.local.wire_api=responses" -c "model_providers.local.env_key=LOCAL_AI_KEY" \
        -c "model_provider=local" -c "model=$model" -c "model_context_window=$context" ;;
    opencode)
      # opencode resolves {env:NAME} inside its config, so the key stays out of the config text too
      cfg=$(jq -nc --arg u "$ENDPOINT/v1" --arg m "$model" --argjson ctx "$context" --argjson vision "$vision" \
        '{"$schema":"https://opencode.ai/config.json",provider:{"omarchy-local":{npm:"@ai-sdk/openai-compatible",name:"Omarchy Local",options:{baseURL:$u,apiKey:"{env:OMARCHY_LOCAL_AI_KEY}"},models:{($m):{name:$m,limit:{context:$ctx,output:$ctx},modalities:{input:(if $vision then ["text","image"] else ["text"] end),output:["text"]}}}}}}')
      with_key OMARCHY_LOCAL_AI_KEY
      printf '%s\0' env "OPENCODE_CONFIG_CONTENT=$cfg" "$bin" --model "omarchy-local/$model" ;;
    pi|omp)
      # pi reads providers from its agent dir; a plugin-owned dir keeps the user's own untouched.
      # omp also wants a config.yml there, or it opens its first-run wizard.
      local dir="$STATE/agents/$name"; mkdir -p "$dir"
      # OMP infers reasoning settings from model names; leave those to the engine's defaults.
      jq -nc --arg a "$name" --arg u "$ENDPOINT/v1" --arg m "$model" --arg k "$key" --argjson ctx "$context" --argjson vision "$vision" \
        '{providers:{"omarchy-local":{baseUrl:$u,apiKey:$k,api:"openai-completions",models:[({id:$m,name:($m+" · local"),contextWindow:$ctx,input:(if $vision then ["text","image"] else ["text"] end),cost:{input:0,output:0,cacheRead:0,cacheWrite:0}} + (if $a=="omp" then {compat:{supportsReasoningParams:false}} else {} end))]}}}' \
        >"$dir/models.json"
      if [[ $name == omp ]]; then
        # OMP migrates JSON once, then prefers models.yml on subsequent launches.
        cp "$dir/models.json" "$dir/models.yml"
        printf 'modelRoles:\n  default: omarchy-local/%s\nsetupVersion: 2\n' "$model" >"$dir/config.yml"
      fi
      printf '%s\0' env "PI_CODING_AGENT_DIR=$dir" "OMP_CODING_AGENT_DIR=$dir"
      # Local llama.cpp decoders cannot read WebP; OMP can preserve PNG/JPEG instead.
      [[ $name == omp ]] && printf '%s\0' OMP_NO_WEBP=1
      printf '%s\0' "$bin" --provider omarchy-local --model "$model" ;;
    crush)
      # crush takes providers from XDG config only, not from OPENAI_BASE_URL, and its XDG data file pins the
      # last chosen model over the config: give it a plugin-owned config and data home
      local dir="$STATE/agents/crush/crush"; mkdir -p "$dir"
      # a mise shim would reinstall crush under the new data home: launch the real binary instead
      if { [[ $bin == */mise/shims/* ]] || grep -Iq 'mise.*crush' "$bin"; } && command -v mise >/dev/null 2>&1; then
        bin=$(mise which crush 2>/dev/null || printf '%s' "$bin")
      fi
      jq -nc --arg u "$ENDPOINT/v1" --arg m "$model" --arg k "$key" --argjson ctx "$context" --argjson vision "$vision" \
        '{providers:{"omarchy-local":{type:"openai",name:"Omarchy Local",base_url:$u,api_key:$k,models:[{id:$m,name:$m,context_window:$ctx,default_max_tokens:8192,supports_attachments:$vision}]}},models:{large:{provider:"omarchy-local",model:$m},small:{provider:"omarchy-local",model:$m}}}' \
        >"$dir/crush.json"
      with_key OPENAI_API_KEY
      printf '%s\0' env "XDG_CONFIG_HOME=$STATE/agents/crush" "XDG_DATA_HOME=$STATE/agents/crush" "$bin" ;;
    copilot)
      with_key COPILOT_PROVIDER_API_KEY
      printf '%s\0' env "COPILOT_PROVIDER_BASE_URL=$ENDPOINT/v1" "$bin" --model "$model" ;;
    grok)
      local dir="$STATE/agents/grok"; mkdir -p "$dir"
      # A chat-proxy override still selects Grok's cloud catalog and OAuth token.
      # Use its custom-model config so both the model and authentication are local.
      printf '[models]\ndefault = "omarchy-local"\n[features]\nremote_fetch = false\nmanaged_config = false\ntelemetry = false\n[model.omarchy-local]\nmodel = %s\nname = "Omarchy Local"\nbase_url = %s\nenv_key = "XAI_API_KEY"\napi_backend = "chat_completions"\ncontext_window = %s\n' \
        "$(jq -Rn --arg v "$model" '$v')" "$(jq -Rn --arg v "$ENDPOINT/v1" '$v')" "$context" >"$dir/config.toml"
      with_key XAI_API_KEY
      printf '%s\0' env "GROK_HOME=$dir" "$bin" --model omarchy-local ;;
    *) # OpenAI-compatible by convention: hermes, ori, agy read the standard variables
      with_key OPENAI_API_KEY
      printf '%s\0' env "OPENAI_BASE_URL=$ENDPOINT/v1" "OPENAI_API_BASE=$ENDPOINT/v1" "OPENAI_MODEL=$model" "$bin" ;;
  esac
}

open_agent() { # open_agent [name] [recipe]: default agent when omitted, the model the card looks at when no recipe is named; refuses out loud
  local name=${1:-} which=${2:-} snap model key m
  snap=$(cat "$SNAPSHOT" 2>/dev/null || printf '{}')
  if [[ -n $which ]]; then m=$(jq -c --arg id "$which" '[.models[]? | select(.recipeId == $id)] | .[0] // null' <<<"$snap")
  else m=$(jq -c '(.running.recipeId // "") as $id | [.models[]? | select(.recipeId == $id)] | .[0] // null' <<<"$snap"); fi
  [[ $m != null && $(jq -r .state <<<"$m") == ready ]] || { fail "load a model first"; return; }
  [[ -n $name ]] || { name=$(jq -r '.agents.default // ""' <<<"$snap"); name=${name:-pi}; }
  jq -e --arg a "$name" '.launchable|index($a)!=null' <<<"$m" >/dev/null \
    || { fail "$name cannot use this model: its API dialect did not pass acceptance"; return; }
  model=$(jq -r '.servedModel' <<<"$m"); ENDPOINT="http://127.0.0.1:$(jq -r .port <<<"$m")"
  local -a argv=(); while IFS= read -r -d '' v; do argv+=("$v"); done < <(agent_command "$name" "$model" "$KEY_FILE" "$(jq -r '.ctxTokens // 131072' <<<"$m")" "$(jq -r '.caps.vision // false' <<<"$m")") || return 1
  # the person's own flags for this agent (`omarchy-local-ai agent-args <name> -- <flags>`), e.g. a yolo mode
  if [[ -s $STATE/agents/args/$name ]]; then while IFS= read -r -d '' v; do argv+=("$v"); done <"$STATE/agents/args/$name"; fi
  log "open-agent $name"
  if [[ ${OMARCHY_AI_FOREGROUND:-0} == 1 ]]; then printf '%q ' "${argv[@]}"; echo; return 0; fi
  # the agent works where the person works: OMARCHY_AI_AGENT_DIR, else the directory recorded by
  # `omarchy-local-ai agent-dir <path>`, else wherever the shell was started (usually home)
  local dir=${OMARCHY_AI_AGENT_DIR:-$(cat "$STATE/agent-dir" 2>/dev/null)}
  [[ -n $dir && -d $dir ]] && cd "$dir"
  # the launcher's exit code is the terminal handshake (uwsm-app), not the agent: when it fails,
  # say what it said, so a stuck app daemon is not reported as a broken agent
  # omarchy-launch-tui blocks for the terminal's whole life and exits with the terminal's status, so
  # it is detached and its exit is not the launch result. It goes through uwsm's fast app daemon,
  # which can wedge ("Timed out waiting for pipes", ten seconds per call): a two-second ping decides,
  # and a wedged daemon gets the same terminal command through the plain uwsm client instead.
  local -a detach=(); command -v setsid >/dev/null 2>&1 && detach=(setsid)   # its own session where util-linux is there (Omarchy always)
  if ! command -v uwsm-app >/dev/null 2>&1 || timeout 2 uwsm-app ping >/dev/null 2>&1; then
    command -v omarchy-launch-tui >/dev/null 2>&1 || { fail "could not open a terminal for $name: omarchy-launch-tui is missing"; return 1; }
    "${detach[@]}" omarchy-launch-tui --app-id=org.omarchy.agent "${argv[@]}" >/dev/null 2>>"$LOGFILE" </dev/null & disown
  elif command -v uwsm >/dev/null 2>&1 && command -v xdg-terminal-exec >/dev/null 2>&1; then
    log "uwsm app daemon is not answering; opening $name through uwsm app"
    "${detach[@]}" uwsm app -- xdg-terminal-exec --app-id=org.omarchy.agent -e "${argv[@]}" >/dev/null 2>>"$LOGFILE" </dev/null & disown
  else fail "could not open a terminal for $name: the uwsm app daemon is not answering"; return 1; fi
  lwrite '.error=""'; snapshot_write   # a launch that worked retires an earlier refusal
}
