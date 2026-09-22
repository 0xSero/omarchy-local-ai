#!/bin/bash
# Sourced by every local-ai test after base-test.sh. An isolated home, a copy of the plugin with a
# synthetic recipes.json beside it, and shims for docker, curl, nvidia-smi, lspci, pkexec, ss, the
# package tools and the agents, so the whole load/accept/rollback/unload path runs anywhere with
# bash and jq. No GPU, no daemon, no network.

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export SHIM="$TMP/shim" HOME="$TMP/home"
mkdir -p "$TMP/bin" "$HOME" "$SHIM" "$TMP/plugin/bin"
cp "$ROOT/bin/omarchy-local-ai" "$TMP/plugin/bin/omarchy-local-ai"; chmod +x "$TMP/plugin/bin/omarchy-local-ai"
CLI="$TMP/plugin/bin/omarchy-local-ai"
RECIPES="$TMP/plugin/recipes.json"
STATE="$HOME/.local/state/omarchy/local-ai"
MODELS="$HOME/.cache/omarchy/local-ai/models"
export OMARCHY_AI_USER_HOME="$HOME" OMARCHY_AI_POLL=0 OMARCHY_AI_TIMEOUT=5 OMARCHY_AI_FOREGROUND=1 OMARCHY_AI_DOCKER=direct OMARCHY_AI_DRI_PATH="$TMP/dri"
unset OMARCHY_AI_STATE OMARCHY_AI_MODEL_ROOT OMARCHY_AI_RECIPES XDG_STATE_HOME HF_TOKEN
ln -s "$BASH" "$TMP/bin/bash"
ln -s "$(command -v jq)" "$TMP/bin/jq"
export PATH="$TMP/bin:/usr/bin:/bin"

snap() { jq -r "$1" "$STATE/snapshot.json"; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
FILE_SHA=ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7   # 4096 zero bytes, what the curl shim serves

# recipe <id> [layout dir|hub] [extra jq] -> one schema-2 recipe
recipe() {
  local id=$1 layout=${2:-dir} extra=${3:-.}
  jq -nc --arg id "$id" --arg layout "$layout" '{
    id:$id, name:"Test Model", engine:"llama.cpp", servedName:"Test-Model", sizeGb:0.004, cards:1,
    image:"ghcr.io/x/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", minDriver:"",
    weights:[{repository:"test/model", revision:"0123456789abcdef0123456789abcdef01234567", sizeGb:0.004, layout:$layout,
              mountPath:(if $layout=="hub" then "/root/.cache/huggingface" else "/models" end), dir:"", files:""}],
    asset:null, scratch:null,
    launch:{entrypoint:null, arguments:["main.py"], environment:{A:"1"}, port:8000, shm:"8g"},
    serving:{ctxTokens:131072, kvTokens:131072}, capabilities:{chat:true, tools:true, vision:false, reasoning:false}}' | jq -c "$extra"
}
# write_recipes <hardware-id> <recipe-json>... : the synthetic catalog, one card type
write_recipes() {
  local hw=$1; shift
  jq -nc --arg hw "$hw" --argjson recipes "$(printf '%s\n' "$@" | jq -sc .)" '{
    schemaVersion:"omarchy-local-ai/recipes/2", registryCommit:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", generatedAt:"2026-09-22T00:00:00Z",
    gateway:{image:"ghcr.io/0xsero/gateway@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
    hardware:{($hw):{match:(if $hw=="intel-arc-pro-b70-32gb" then {backend:"intel-xpu",vramGb:32,names:["arcprob70"],name:"Intel Arc Pro B70"}
                             else {backend:"nvidia",vramGb:24,names:["rtx4090"],name:"NVIDIA GeForce RTX 4090"} end), recipes:$recipes}}}' >"$RECIPES"
}
# the Hub's tree of the pinned revision: one 4096-byte file, sha known
printf '[{"type":"file","path":"model.safetensors","size":4096,"lfs":{"oid":"%s"},"oid":"0000000000000000000000000000000000000000"}]\n' "$FILE_SHA" >"$SHIM/tree.json"

# ---------------------------------------------------------------- shims
cat >"$TMP/bin/nvidia-smi" <<'EOF'
#!/bin/bash
if [[ -n ${SHIM_GPUS:-} ]]; then sed "s/$/, ${SHIM_DRIVER:-580.65.06}/" <<<"$SHIM_GPUS"; else echo "0, NVIDIA GeForce RTX 4090, 24564, 300, 24264, ${SHIM_DRIVER:-580.65.06}"; fi
EOF
cat >"$TMP/bin/docker" <<'EOF'
#!/bin/bash
# a docker that remembers containers in $SHIM/containers/<name> (labels, state) and images in $SHIM/images
echo "docker $*" >>"$SHIM/docker.log"
[[ ${OMARCHY_AI_DOCKER:-} == prompt && ${SHIM_ROOT:-} != 1 ]] && { echo "permission denied while trying to connect to the Docker daemon socket" >&2; exit 1; }
label_of() { grep -E "^$2=" "$SHIM/containers/$1/labels" 2>/dev/null | head -1 | cut -d= -f2-; }
render() { # render <name> <format>: {{.Names}} and {{.Label "k"}}
  local n=$1 f=$2; f=${f//'{{.Names}}'/$n}
  while [[ $f =~ \{\{\.Label\ \"([^\"]+)\"\}\} ]]; do f=${f/"${BASH_REMATCH[0]}"/$(label_of "$n" "${BASH_REMATCH[1]}")}; done
  printf '%b\n' "$f"
}
matches() { # matches <name> <filter>...: every label=K=V filter holds
  local n=$1; shift; local x; for x in "$@"; do [[ $x == label=* ]] || continue; x=${x#label=}; [[ $(label_of "$n" "${x%%=*}") == "${x#*=}" ]] || return 1; done
}
case "$1" in
  network) case $2 in
    inspect) nn=${@: -1}; [[ -f $SHIM/net-$nn ]] && { echo 1; exit 0; } || exit 1 ;;
    create) nn=${@: -1}; touch "$SHIM/net-$nn" ;;
    rm) shift 2; for nn in "$@"; do rm -f "$SHIM/net-$nn"; done ;;
    ls) for f in "$SHIM"/net-*; do [[ -e $f ]] && basename "$f" | sed 's/^net-//'; done ;;
    esac; exit 0 ;;
  ps) filters=(); fmt='{{.Names}}'; shift
    while (( $# )); do case $1 in --filter) filters+=("$2"); shift 2 ;; --format) fmt=$2; shift 2 ;; *) shift ;; esac; done
    for d in "$SHIM"/containers/*/; do [[ -d $d ]] || continue; n=${d%/}; n=${n##*/}; matches "$n" "${filters[@]}" && render "$n" "$fmt"; done; exit 0 ;;
  image) case $2 in inspect) grep -qxF "$3" "$SHIM/images" 2>/dev/null; exit $? ;; ls) cat "$SHIM/images" 2>/dev/null; exit 0 ;; esac; exit 0 ;;
  images) exit 0 ;;
  rmi) shift; for i in "$@"; do grep -vxF "$i" "$SHIM/images" >"$SHIM/images.tmp" 2>/dev/null; mv -f "$SHIM/images.tmp" "$SHIM/images"; done; exit 0 ;;
  info) [[ -n ${SHIM_DOCKER_DOWN:-} ]] && { echo "$SHIM_DOCKER_DOWN" >&2; exit 1; }; echo "Runtimes: io.containerd.runc.v2 ${SHIM_RUNTIMES:-nvidia} runc"; exit 0 ;;
  pull) [[ ${SHIM_PULL_FAIL:-} == 1 ]] && { echo "${SHIM_PULL_ERR:-error pulling image configuration: no space left on device}" >&2; exit 1; }; echo "$2" >>"$SHIM/images"; exit 0 ;;
  run) name=""; labels=""; args=("$@")
    for ((i=0;i<${#args[@]};i++)); do [[ ${args[$i]} == --name ]] && name=${args[$((i+1))]}; [[ ${args[$i]} == --label ]] && labels+="${args[$((i+1))]}"$'\n'; done
    [[ ${SHIM_RUN_FAIL:-} == "$name" ]] && exit 125
    mkdir -p "$SHIM/containers/$name"; printf '%s' "$labels" >"$SHIM/containers/$name/labels"; echo running >"$SHIM/containers/$name/state"
    [[ ${SHIM_CRASHLOOP:-} == 1 && $name == *-engine ]] && { echo restarting >"$SHIM/containers/$name/state"; echo 3 >"$SHIM/containers/$name/restarts"; }
    exit 0 ;;
  inspect) fmt=""; name=""
    for a in "$@"; do case $a in -f) ;; '{{'*) fmt=$a ;; inspect) ;; *) name=$a ;; esac; done
    [[ -d $SHIM/containers/$name ]] || exit 1
    st=$(cat "$SHIM/containers/$name/state"); [[ $st == running || $st == restarting ]] && r=true || r=false
    case $fmt in
      *Restarting*) [[ $st == restarting ]] && rs=true || rs=false; echo "$r|$rs|$(cat "$SHIM/containers/$name/restarts" 2>/dev/null || echo 0)" ;;
      *Labels*) key=${fmt#*\"}; key=${key%%\"*}; label_of "$name" "$key" ;;
      *Running*) echo "$r" ;;
      *) echo "[]" ;;
    esac; exit 0 ;;
  logs) printf 'engine: something went wrong\n'; exit 0 ;;
  stop) echo stopped >"$SHIM/containers/$2/state"; exit 0 ;;
  start) echo running >"$SHIM/containers/$2/state"; exit 0 ;;
  rename) mv "$SHIM/containers/$2" "$SHIM/containers/$3"; exit 0 ;;
  rm) rm -rf "$SHIM/containers/${@: -1}"; exit 0 ;;
esac
exit 0
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/bash
# the Hub (tree and file downloads) and the gateway (healthy when an engine+gateway pair runs)
url=${@: -1}; out=""; data=""; auth=""
for ((i=1;i<=$#;i++)); do
  [[ ${!i} == -o ]] && { j=$((i+1)); out=${!j}; }
  [[ ${!i} == -d ]] && { j=$((i+1)); data=${!j}; }
  [[ ${!i} == -H ]] && { j=$((i+1)); h=${!j}; [[ $h == @* ]] && h=$(cat "${h#@}" 2>/dev/null); [[ $h == "Authorization: Bearer "* ]] && auth=${h#Authorization: Bearer }; }
done
printf '%s\n' "$*" >>"$SHIM/curl.log"   # this argv is what /proc/<pid>/cmdline would show
if [[ $url == */api/models/*/tree/* ]]; then [[ ${SHIM_HUB_DOWN:-} == 1 ]] && exit 6; cat "$SHIM/tree.json"; exit 0; fi
if [[ $url == https://huggingface.co/*/resolve/* ]]; then
  [[ ${SHIM_DOWNLOAD_FAIL:-} == 1 ]] && exit 56
  [[ -n ${SHIM_DOWNLOAD_SLOW:-} ]] && { head -c 1024 /dev/zero >"$out"; sleep "$SHIM_DOWNLOAD_SLOW"; }
  if [[ ${SHIM_CORRUPT:-} == 1 ]]; then head -c 4096 /dev/urandom >"$out"; else head -c 4096 /dev/zero >"$out"; fi; exit 0
fi
key=$(cat "$HOME/.local/state/omarchy/local-ai/gateway.key" 2>/dev/null)
if [[ $auth != "$key" && ${SHIM_KEYLESS_GATEWAY:-} != 1 ]]; then exit 22; fi
up=0; for g in "$SHIM"/containers/*-gateway/; do [[ -d $g ]] || continue; n=${g%/}; n=${n##*/}; e=${n%-gateway}-engine
  [[ $(cat "$SHIM/containers/$n/state" 2>/dev/null) == running && $(cat "$SHIM/containers/$e/state" 2>/dev/null) == running ]] && up=1; done
(( up )) || exit 7
apis=${SHIM_APIS:-chat,messages,responses}
case $url in
  */v1/models) echo "{\"data\":[{\"max_model_len\":${SHIM_CONTEXT:-0},\"id\":\"${SHIM_SERVED:-Test-Model}\"}]}" ;;
  */v1/chat/completions)
    if [[ $data == *'"tools"'* ]]; then echo '{"choices":[{"message":{"content":null,"tool_calls":[{"function":{"name":"shell","arguments":"{\"command\":\"echo LOCAL_AI_TOOL_OK\"}"}}]}}],"usage":{"completion_tokens":12}}'
    elif [[ $data == *"Count from 1 to 80"* ]]; then [[ -n ${SHIM_SLOW:-} ]] && sleep "$SHIM_SLOW"; words=$(seq -s ' ' 1 80); [[ ${SHIM_LEAK_THINK:-} == 1 ]] && words="I should count.</think>$words"
      echo "{\"choices\":[{\"message\":{\"content\":\"$words\"}}],\"usage\":{\"completion_tokens\":${SHIM_TOKENS:-60}}}"
    else echo "{\"choices\":[{\"message\":{\"content\":\"${SHIM_REPLY:-LOCAL_AI_READY}\"}}],\"usage\":{\"completion_tokens\":12}}"; fi ;;
  */v1/messages) [[ $apis == *messages* ]] || exit 22; echo '{"content":[{"type":"text","text":"LOCAL_AI_READY"}]}' ;;
  */v1/responses) [[ $apis == *responses* ]] || exit 22; echo '{"output":[{"type":"message","content":[{"type":"output_text","text":"LOCAL_AI_READY"}]}]}' ;;
esac
EOF
cat >"$TMP/bin/pkexec" <<'EOF'
#!/bin/bash
# polkit: dismissed when SHIM_PKEXEC_FAIL=1; otherwise the target runs from a scrubbed environment, marked as the root side
echo "pkexec $*" >>"$SHIM/pkexec.log"
[[ ${SHIM_PKEXEC_FAIL:-} == 1 ]] && { echo "Error executing command as another user: Request dismissed" >&2; exit 126; }
args=(); for v in "${!SHIM_@}"; do args+=("$v=${!v}"); done
exec env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" SHIM="$SHIM" OMARCHY_AI_TEST_ROOT=1 OMARCHY_AI_TEST_HOME="$HOME" SHIM_ROOT=1 PKEXEC_UID="${SHIM_PKEXEC_UID:-$(id -u)}" "${args[@]}" "$@"
EOF
cat >"$TMP/bin/lspci" <<'EOF'
#!/bin/bash
[[ -n ${SHIM_LSPCI:-} ]] || exit 0
printf '0000:84:00.0 VGA compatible controller [0300]: Intel Corporation Device [8086:e223]\n0000:c3:00.0 VGA compatible controller [0300]: Intel Corporation Battlemage G31 [Arc Pro B70] [8086:e223]\n0000:c4:00.0 VGA compatible controller [0300]: Intel Corporation Device [8086:e223]\n'
EOF
printf '#!/bin/bash\n[[ ${SHIM_PORT_BUSY:-} == 1 && "$*" == *:12434* ]] && echo "LISTEN 0 4096 127.0.0.1:12434 0.0.0.0:*"\nexit 0\n' >"$TMP/bin/ss"
for tk in omarchy-pkg-add nvidia-ctk systemctl; do printf '#!/bin/bash\necho "%s $*" >>"$SHIM/toolkit.log"\n' "$tk" >"$TMP/bin/$tk"; done
printf '#!/bin/bash\necho "launch-tui $*" >>"$SHIM/tui.log"\n' >"$TMP/bin/omarchy-launch-tui"
printf '#!/bin/bash\n[[ ${SHIM_SUDOLESS:-} == 1 ]] && exit 1\nexit 0\n' >"$TMP/bin/omarchy-sudo-docker"
for a in pi omp opencode ori claude codex grok agy hermes copilot crush muse cursor-agent; do
  printf '#!/bin/bash\necho "$0 $* ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-} ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:-} LOCAL_AI_KEY=${LOCAL_AI_KEY:-} OPENAI_API_KEY=${OPENAI_API_KEY:-}"\n' >"$TMP/bin/$a"
done
find "$TMP/bin" -type f -exec chmod +x {} +
