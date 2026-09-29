#!/bin/bash
# The backend end to end with shims for docker, curl, nvidia-smi and the Omarchy helpers: no GPU,
# no daemon, no network. A synthetic recipe runs, answers, opens an agent and stops; the failure paths
# (an unpinned image, a corrupt download, missing Docker access) end with the right reason.

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf '%s\n' "${2:-}" >&2; printf 'not ok - %s\n' "$1" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP/home SHIM=$TMP/shim XDG_RUNTIME_DIR=$TMP/run
mkdir -p "$HOME" "$SHIM/containers" "$TMP/bin" "$TMP/plugin/bin"
cp "$ROOT/bin/omarchy-remove-ai-local" "$TMP/plugin/bin/"
cp "$ROOT/bin/omarchy-local-ai" "$ROOT/manifest.json" "$TMP/plugin/" 2>/dev/null || true
mv "$TMP/plugin/omarchy-local-ai" "$TMP/plugin/bin/"
CLI=$TMP/plugin/bin/omarchy-local-ai
sed -i "s/setup_needed \&\& echo true || echo false/echo false/" "$CLI"
sed -i "s|CATALOG=\$HOME/.cache/omarchy/local-ai/recipes.json|CATALOG=$TMP/catalog.json|" "$CLI"
# the daemon's socket, reachable unless a case says otherwise
export OMARCHY_DOCKER_SOCKET=$TMP/docker.sock
: >"$OMARCHY_DOCKER_SOCKET"
STATE=$HOME/.local/state/omarchy/local-ai
ID=test-model-rtx4090
SHA=ad7facb2586fc6e966c004d7d1d16b024f5805ff7cb47c7a85dabd8b48892ca7 # 4096 zero bytes, what the Hub shim serves
PIN=ghcr.io/x/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# recipes <image>: one card kind, one recipe, in the vendored schema
recipes() {
  jq -nc --arg id "$ID" --arg img "$1" '{schemaVersion: "omarchy-local-ai/recipes/2", registryCommit: ("d" * 40),
    gateway: {image: ("ghcr.io/x/gateway@sha256:" + ("b" * 64))},
    hardware: {"rtx-4090-24gb": {match: {backend: "nvidia", vramGb: 24, names: ["rtx4090"]}, recipes: [{id: $id,
      name: "Test Model", family: "qwen", format: "EXL3", sizeGb: 0.004, cards: 1, image: $img, servedName: "served",
      weights: [{repository: "test/model", revision: ("0" * 40), layout: "dir", mountPath: "/models", dir: "", files: ""}],
      launch: {arguments: ["--port", "8000"], environment: {A: "1", NVIDIA_VISIBLE_DEVICES: "all"}, port: 8000, shm: "8g"},
      serving: {ctxTokens: 131072}, capabilities: {tools: true, vision: false}}]}}}' >"$TMP/plugin/recipes.json"
}
# wait_for <state> [id]: the detached worker's end state
wait_for() {
  local i d=$STATE/deploy/${2:-$ID}
  for ((i = 0; i < 100; i++)); do
    [[ $(jq -r .state "$d/status.json" 2>/dev/null) =~ ^(ready|error)$ ]] && break
    sleep 0.3
  done
  [[ $(jq -r .state "$d/status.json") == "$1" ]] || fail "state $1" "$(cat "$d/status.json" "$d/err" 2>/dev/null)"
}
shim() { printf '#!/bin/bash\n%s\n' "$2" >"$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

shim nvidia-smi 'printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
# SHIM_NOGROUP: the account is not in the docker group (setup not run)
shim omarchy-sudo-docker '[[ -n ${SHIM_NOGROUP:-} ]]'
shim omarchy-cmd-present 'command -v "$1" >/dev/null'
shim omarchy-cmd-missing '! command -v "$1" >/dev/null'
shim omarchy-notification-send 'echo 7'
shim omarchy-launch-tui 'printf "%s\n" "$*" >>"$SHIM/tui.log"'
# nothing may ask for a password after setup: every pkexec or sudo lands here and fails the run at its end
shim pkexec 'printf "%s\n" "$*" >>"$SHIM/prompts.log"; exit 126'
shim sudo 'printf "sudo %s\n" "$*" >>"$SHIM/prompts.log"; exit 1'
shim pi 'exit 0'
shim hermes 'exit 0'
shim lspci 'exit 0'
shim ss 'exit 0'
shim docker '
printf "%s\n" "$*" >>"$SHIM/docker.log"
c=$SHIM/containers
case $1 in
info) echo "Runtimes: nvidia runc" ;;
image) exit 1 ;;
pull) : ;;
network) : ;;
run) n=""; for ((i = 1; i <= $#; i++)); do [[ ${!i} == --name ]] && { j=$((i + 1)); n=${!j}; }; done; echo "1|$(id -u)" >"$c/$n" ;;
inspect) n=${@: -1}; [[ -f $c/$n ]] || exit 1; [[ $* == *RestartCount* ]] && echo 0 || cat "$c/$n" ;;
logs) [[ -z ${SHIM_ENGINE_LOG:-} ]] || printf "loading shards\nRuntimeError: XPU out of memory. Tried to allocate 2.00 GiB\n" ;;
rm) rm -f "$c/${@: -1}" ;;
ps) ls "$c" ;;
esac'
shim curl '
url="" out="" key=""
for ((i = 1; i <= $#; i++)); do
  j=$((i + 1))
  [[ ${!i} == http* ]] && url=${!i}
  [[ ${!i} == -o ]] && out=${!j}
  [[ ${!i} == -H && ${!j} == @* ]] && key=$(sed -n "s/^Authorization: Bearer //p" "${!j#@}")
done
printf "%s\n" "$*" >>"$SHIM/curl.log"
case $url in
*api.github.com/repos/*/commits/main) printf "{\"sha\":\"%040d\"}" 1 ;;
*raw.githubusercontent.com/*/recipes.json) cat "$SHIM/registry.json" ;;
*/api/models/*) printf "[{\"type\":\"file\",\"path\":\"model.safetensors\",\"size\":4096,\"lfs\":{\"oid\":\"%s\"}}]" '"$SHA"' ;;
*/resolve/*) if [[ -n ${SHIM_CORRUPT:-} ]]; then head -c 4096 /dev/urandom >"$out"; else head -c 4096 /dev/zero >"$out"; fi ;;
http://127.0.0.1:*)
  ls "$SHIM/containers" | grep -q gateway || exit 7
  [[ $key == "$(cat "$HOME/.local/state/omarchy/local-ai/gateway.key")" ]] || { [[ $* == *http_code* ]] && printf 401; exit 22; }
  if [[ $url == */v1/models ]]; then
    printf "{\"data\":[{\"id\":\"served\"}]}" >"$out"
    [[ $* == *http_code* ]] && printf 200
  else
    if [[ -n ${SHIM_EMPTY:-} ]]; then echo "{}"; else
      echo "{\"choices\":[{\"message\":{\"content\":\"1, 2, 3\"}}],\"usage\":{\"completion_tokens\":200}}"
    fi
  fi ;;
esac'
! command -v node >/dev/null || ln -s "$(command -v node)" "$TMP/bin/node"
export PATH=$TMP/bin:/usr/bin:/bin
# NVIDIA CDI specs are read from here, not /etc/cdi: one device, /dev/null, at its real numbers (1:3)
export CDI_DIRS=$TMP/cdi
cdi() { mkdir -p "$CDI_DIRS"; printf 'devices:\n  - name: "0"\n    containerEdits:\n      deviceNodes:\n        - path: /dev/null\n          major: %s\n          minor: 3\n' "$1" >"$CDI_DIRS/nvidia.yaml"; }
cdi 1

recipes "$PIN"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r '.kinds[0].hw, .kinds[0].free[0], .kinds[0].models[0].id, (.gpus[] | select(.hw == "") | .name)' "$TMP/snap.json" | paste -sd' ') == "rtx-4090-24gb nvidia:0 $ID GT 710" ]] ||
  fail "snapshot" "$(jq -c . "$TMP/snap.json")"
pass "the snapshot matches the card to its kind and its one recipe, and lists a card with no recipe"

# A probe that answers with something other than its own format is no cards, never a snapshot the panel
# cannot read: nvidia-utils without a driver prints its failure on stdout, and amd-smi prints an import
# error when its python module is out of reach (the AMD probe already reads that as no cards, held here
# so it stays that way)
shim nvidia-smi 'printf "NVIDIA-SMI has failed because it couldn'\''t communicate with the NVIDIA driver. Make sure that the latest NVIDIA driver is installed and running.\n"'
"$CLI" snapshot >"$TMP/snap-nosmi.json" 2>"$TMP/nosmi.err" || fail "a failed nvidia-smi broke the snapshot" "$(cat "$TMP/nosmi.err")"
[[ $(jq -r '.gpus | length' "$TMP/snap-nosmi.json") == 0 ]] || fail "a failed nvidia-smi is no NVIDIA cards" "$(jq -c . "$TMP/snap-nosmi.json")"
shim amd-smi 'printf "Unhandled import error: No module named '\''amdsmi'\''\n"'
"$CLI" snapshot >"$TMP/snap-nosmi.json" || fail "a failed amd-smi broke the snapshot"
[[ $(jq -r '.gpus | length' "$TMP/snap-nosmi.json") == 0 ]] || fail "a failed amd-smi is no AMD cards" "$(jq -c . "$TMP/snap-nosmi.json")"
rm -f "$TMP/bin/amd-smi"
shim nvidia-smi 'printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
pass "a probe that fails (nvidia-smi's and amd-smi's own error text) reads as no cards, not as a broken snapshot"

# AMD cards come from amd-smi 7.2 (ROCm 7.2, what Arch ships), which wraps both listings in gpu_data. Against
# the vendored recipes an RX 7600 XT 16 GB is its card kind and an 8 GB RX 7600 is a card with no recipe, not
# an XT (issue #12)
shim amd-smi 'case $1 in
static) printf "{\"gpu_data\":[{\"gpu\":0,\"asic\":{\"market_name\":\"AMD Radeon RX 7600 XT\"},\"vram\":{\"size\":{\"value\":16368,\"unit\":\"MB\"}},\"bus\":{\"bdf\":\"0000:03:00.0\"}},{\"gpu\":1,\"asic\":{\"market_name\":\"AMD Radeon RX 7600\"},\"vram\":{\"size\":{\"value\":8176,\"unit\":\"MB\"}},\"bus\":{\"bdf\":\"0000:07:00.0\"}}]}" ;;
metric) printf "{\"gpu_data\":[{\"gpu\":0,\"mem_usage\":{\"used_vram\":{\"value\":210,\"unit\":\"MB\"}},\"temperature\":{\"edge\":{\"value\":41,\"unit\":\"C\"}}},{\"gpu\":1,\"mem_usage\":{\"used_vram\":{\"value\":90,\"unit\":\"MB\"}},\"temperature\":{\"edge\":{\"value\":38,\"unit\":\"C\"}}}]}" ;;
esac'
shim nvidia-smi 'exit 9'
cp "$ROOT/recipes.json" "$TMP/plugin/recipes.json"
"$CLI" snapshot >"$TMP/snap-amd.json" || fail "the AMD snapshot"
[[ $(jq -r '.gpus | map("\(.key)=\(.hw)=\(.vramGb)=\(.tempC)") | join(" ")' "$TMP/snap-amd.json") == "amd-rocm:0=rx-7600-xt-16gb=16=41 amd-rocm:1==8=38" ]] ||
  fail "RX 7600 XT and RX 7600" "$(jq -c .gpus "$TMP/snap-amd.json")"
jq -e '[.kinds[] | select(.hw == "rx-7600-xt-16gb") | .free[0], (.models | length > 0)] == ["amd-rocm:0", true]' "$TMP/snap-amd.json" >/dev/null ||
  fail "the RX 7600 XT kind" "$(jq -c .kinds "$TMP/snap-amd.json")"
# A Vulkan recipe uses the same physical AMD detector, without requiring ROCm at launch.
shim amd-smi 'case $1 in
static) printf "{\"gpu_data\":[{\"gpu\":0,\"asic\":{\"market_name\":\"AMD Radeon RX 9070 XT\"},\"vram\":{\"size\":{\"value\":16368}},\"bus\":{\"bdf\":\"0000:03:00.0\"}}]}" ;;
metric) echo "{}" ;;
esac'
"$CLI" snapshot >"$TMP/snap-vulkan.json"
[[ $(jq -r '.gpus[0].hw' "$TMP/snap-vulkan.json") == rx-9070-xt-16gb ]] || fail "AMD Vulkan card match"
pass "AMD discovery matches the RX 9070 XT Vulkan recipes"
rm -f "$TMP/bin/amd-smi"
shim nvidia-smi 'printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
recipes "$PIN"
pass "amd-smi 7.2's cards: an RX 7600 XT runs its recipes, an 8 GB RX 7600 is listed as a card with none"

# The panel's view model reads this exact snapshot: a shape the backend changed and Model.js did not is a
# view that throws, which the panel can only show as an error
view() {
  node -e 'const fs = require("fs"), vm = require("vm"), c = {}; vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), c)
    const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), v = c.build(s, {view: process.argv[3], id: process.argv[4] || "", open: "", key: "", problem: ""})
    console.log(v.mark + " " + v.rows.map(r => r.type).join(","))' "$ROOT/Model.js" "$TMP/snap.json" "$@"
}
if command -v node >/dev/null; then
  [[ $(view home) == " sec,slot,slot,field,acts" ]] || fail "home view" "$(view home 2>&1)"
  [[ $(view kind rtx-4090-24gb) == " sec,gpu,sec,field,field,sec,field,acts" ]] || fail "kind view" "$(view kind rtx-4090-24gb 2>&1)"
  pass "the view model builds home and the free card's page from the backend's own snapshot"
else
  echo "ok - the view model builds from the backend's snapshot # SKIP node is not installed"
fi

# A CDI spec whose device numbers no longer match /dev (a driver update moved /dev/nvidia-uvm from 237 to 238 in
# issue #17) stops the start at once with the command that regenerates it, before an engine container exists
cdi 237
"$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == "the NVIDIA device list is out of date; see the log for the repair command" ]] ||
  fail "stale CDI reason" "$(cat "$STATE/deploy/$ID/status.json")"
! grep -q "^run .*--name $(printf 'omarchy-local-ai-%s-engine' "$ID")" "$SHIM/docker.log" 2>/dev/null || fail "an engine started on a stale CDI spec" "$(cat "$SHIM/docker.log")"
cdi 1
grep -q "sudo nvidia-ctk cdi generate --output=$CDI_DIRS/nvidia.yaml" "$STATE/log" || fail "CDI repair log"
pass "a stale NVIDIA CDI spec stops before the engine, with the repair command in the log"
"$CLI" stop "$ID"

"$CLI" run "$ID" nvidia:0
wait_for ready
"$CLI" snapshot >"$TMP/snap.json"
if command -v node >/dev/null; then
  [[ $(view home) == "ready run,sec,slot,field,acts" && $(view run "$ID") == "ready grid,sec,gpu,sec,field,field,sec,field,sec,field"*",acts" ]] ||
    fail "running views" "$(view home 2>&1; view run "$ID" 2>&1)"
  pass "the view model builds home and the model's page for a running model"
fi
pass "run downloads the weights, starts the engine and the gateway, and waits until the model answers"
[[ -f $HOME/.cache/omarchy/local-ai/models/test--model@000000000000/model.safetensors ]] || fail "weights" "$(find "$HOME/.cache" -type f)"
pass "the weights land under the model cache, checked against the Hub's size and sha256"
if "$CLI" forget "$ID" 2>"$TMP/forget.err"; then fail "removed running weights"; fi
grep -q 'stop models using these weights' "$TMP/forget.err" || fail "forget reason"
pass "running models protect their shared download from removal"
engine=$(grep -- '--name omarchy-local-ai-.*-engine' "$SHIM/docker.log")
[[ $engine == *"--gpus \"device=0\""* && $engine == *"--security-opt no-new-privileges"* && $engine == *":/models:ro"* &&
  $engine == *"--shm-size 8g"* && $engine == *"--env A=1"* && $engine != *NVIDIA_VISIBLE_DEVICES* && $engine != *--publish* &&
  $engine == *"$PIN --port 8000" ]] || fail "engine argv" "$engine"
pass "the engine gets its card, a read-only weights mount and the recipe's options, never a published port or its own card choice"
gateway=$(grep -- '--name omarchy-local-ai-.*-gateway' "$SHIM/docker.log")
[[ $gateway == *"--publish 127.0.0.1:12434:12434"* && $gateway == *"--user $(id -u):$(id -g)"* && $gateway == *"gateway.key:/run/gateway.key:ro"* ]] ||
  fail "gateway argv" "$gateway"
[[ $gateway == *"--cap-drop ALL"* && $gateway == *"--read-only"* &&
  $gateway == *"--tmpfs /tmp:rw,nosuid,nodev,size=64m"* && $gateway == *"--dns 127.0.0.1"* ]] ||
  fail "gateway isolation" "$gateway"
pass "the gateway runs as the user with a read-only root, no capabilities and no external DNS"
key=$(cat "$STATE/gateway.key")
! grep -q "$key" "$SHIM/curl.log" "$SHIM/docker.log" "$STATE/log" || fail "key leaked" "the key appears in an argv or the log"
[[ $(stat -c %a "$STATE/gateway.key") == 600 ]] || fail "key mode"
pass "the gateway key stays in a 0600 file, out of every argv and the log"
grep -q -- "-fsS --max-time 5 http://127.0.0.1:12434/v1/models" "$SHIM/curl.log" || fail "keyless check" "$(cat "$SHIM/curl.log")"
pass "a gateway that answers without the key would be refused"

"$CLI" run "$ID" nvidia:0 2>"$TMP/err" && fail "second run"
grep -q "nvidia:0 is in use" "$TMP/err" || fail "second run reason" "$(cat "$TMP/err")"
pass "a card that is running a model cannot be claimed twice"

"$CLI" run "$ID" nvidia:2
wait_for ready "$ID--2"
grep -q -- "--name omarchy-local-ai-$ID--2-engine .*--gpus \"device=2\"" "$SHIM/docker.log" && [[ $(jq -r .port "$STATE/deploy/$ID--2/config.json") == 12435 ]] ||
  fail "second copy" "$(grep -- "$ID--2-engine" "$SHIM/docker.log")"
"$CLI" stop "$ID--2"
pass "the same model runs a second copy on a second card of the same kind, on its own port"

# a group: one model across two cards of the kind
"$CLI" stop "$ID"
jq -c --arg id "$ID-tp2" '.hardware["rtx-4090-24gb"].recipes += [.hardware["rtx-4090-24gb"].recipes[0] + {id: $id, cards: 2}]' "$TMP/plugin/recipes.json" >"$TMP/r2" && mv "$TMP/r2" "$TMP/plugin/recipes.json"
"$CLI" run "$ID-tp2" nvidia:0 2>"$TMP/err" && fail "one card for a two-card recipe"
grep -q "runs on 2 card" "$TMP/err" || fail "card count reason" "$(cat "$TMP/err")"
"$CLI" run "$ID-tp2" nvidia:0,nvidia:2
wait_for ready "$ID-tp2"
grep -q -- '--name omarchy-local-ai-'"$ID"'-tp2-engine .*--gpus "device=0,2"' "$SHIM/docker.log" && [[ $(jq -c .keys "$STATE/deploy/$ID-tp2/config.json") == '["nvidia:0","nvidia:2"]' ]] ||
  fail "group run" "$(grep -- "$ID-tp2-engine" "$SHIM/docker.log")"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r '.kinds[0].groups[0] | "\(.id) \(.cards)"' "$TMP/snap.json") == "$ID-tp2 2" ]] || fail "groups in snapshot" "$(jq -c .kinds "$TMP/snap.json")"
"$CLI" stop "$ID-tp2"
recipes "$PIN"
"$CLI" run "$ID" nvidia:0
wait_for ready
pass "a group runs one model across two cards of a kind, refuses the wrong number of cards, and is in the snapshot"

"$CLI" set agent pi "$ID"
"$CLI" open "$ID"
sleep 0.5
[[ -f $STATE/agents/pi/models.json && $(jq -r '.providers["omarchy-local"].baseUrl' "$STATE/agents/pi/models.json") == "http://127.0.0.1:12434/v1" ]] ||
  fail "pi config" "$(cat "$STATE/agents/pi/models.json" 2>/dev/null)"
grep -q -- "--provider omarchy-local --model Test Model" "$SHIM/tui.log" && ! grep -q "$key" "$SHIM/tui.log" || fail "open argv" "$(cat "$SHIM/tui.log")"
[[ $(jq -r .agent "$STATE/settings.json") == pi ]] || fail "default agent"
pass "open starts the chosen agent on the gateway in a terminal, with the key only in its private config; the choice becomes the default"

"$CLI" set agent hermes "$ID"
"$CLI" open "$ID"
sleep 0.5
grep -q -- "CUSTOM_BASE_URL=http://127.0.0.1:12434/v1 OPENAI_BASE_URL=http://127.0.0.1:12434/v1 .*hermes chat --provider custom --model Test Model" "$SHIM/tui.log" &&
  ! grep -q "$key" "$SHIM/tui.log" || fail "hermes argv" "$(tail -1 "$SHIM/tui.log")"
pass "Hermes opens on the gateway through --provider custom, without its own config.yaml, the key only in the environment"

# All supported agent adapters stay in private config or keyed environments, never a gateway key in argv.
for agent in pi claude codex opencode omp crush grok copilot hermes; do
  shim "$agent" 'exit 0'
  "$CLI" set agent "$agent" "$ID"
  "$CLI" open "$ID"
  ! grep -q "$key" "$SHIM/tui.log" || fail "agent key leaked" "$agent"
done
pass "every supported agent opens without exposing the gateway key in terminal arguments"
shim omarchy-launch-tui 'exit 1'
if "$CLI" open "$ID" 2>"$TMP/open.err"; then fail "a failed launcher looked successful"; fi
grep -qx 'local-ai: could not open the agent terminal; try again' "$TMP/open.err" || fail "launcher error"
shim omarchy-launch-tui 'printf "%s\n" "$*" >>"$SHIM/tui.log"'
"$CLI" setup
"$CLI" log
grep -q -- '--app-id=org.omarchy.local-ai-setup' "$SHIM/tui.log" || fail "setup terminal"
grep -q -- '--app-id=org.omarchy.local-ai-log less +G' "$SHIM/tui.log" || fail "log terminal"
pass "setup and log launch their dedicated terminals; a failed agent launcher reports its error"
mkdir -p "$HOME/Work with spaces"
"$CLI" set folder "$HOME/Work with spaces" "$ID"
[[ $(jq -r .folder "$STATE/deploy/$ID/config.json") == "$HOME/Work with spaces" ]] || fail "folder update"
[[ $(jq -r '.folders[0]' "$STATE/settings.json") == "$HOME/Work with spaces" ]] || fail "recent folder"
pass "folder changes update both the running model and recent defaults without a prompt"

"$CLI" stop "$ID"
[[ ! -d $STATE/deploy/$ID && -z $(ls "$SHIM/containers") ]] || fail "stop" "$(ls "$SHIM/containers" "$STATE/deploy")"
pass "stop removes both containers and the model's folder"

SHIM_EMPTY=1 "$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == "the model returned no answer" ]] || fail "empty answer reason"
[[ -z $(ls "$SHIM/containers") ]] || fail "empty answer cleanup"
"$CLI" stop "$ID"
pass "an empty completion is rejected and its containers are removed"


# a 5.x install left a model running: its ledger names it, its containers carry no uid label
echo '{"slots":{"old-model":{"keys":["nvidia:0"],"port":12434,"engine":"omarchy-local-ai-old-model-engine"}}}' >"$STATE/ledger.json"
echo "1|" >"$SHIM/containers/omarchy-local-ai-old-model-engine"
echo "1|" >"$SHIM/containers/omarchy-local-ai-old-model-gateway"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r '.deployments[0] | "\(.id) \(.state) \(.keys[0])"' "$TMP/snap.json") == "old-model ready nvidia:0" && -f $STATE/ledger.json.5x && ! -f $STATE/ledger.json ]] ||
  fail "adopt" "$(jq -c .deployments "$TMP/snap.json")"
pass "a model a 5.x install left running shows as running after the upgrade"
"$CLI" stop old-model
[[ -z $(ls "$SHIM/containers") && ! -d $STATE/deploy/old-model ]] || fail "stop 5.x" "$(ls "$SHIM/containers")"
pass "and stop takes its containers down"

recipes "ghcr.io/x/engine:latest"
"$CLI" run "$ID" nvidia:0 2>"$TMP/err" && fail "unpinned run"
grep -q "image is not pinned by digest" "$TMP/err" || fail "unpinned reason" "$(cat "$TMP/err")"
pass "a recipe whose image is not pinned by digest is refused before anything runs"

recipes "$PIN"
jq '.hardware["rtx-4090-24gb"].match = {backend:"amd-vulkan", names:["rx9070xt"], vramGb:16}' "$TMP/plugin/recipes.json" >"$TMP/r2"
mv "$TMP/r2" "$TMP/plugin/recipes.json"
shim amd-smi 'case $1 in
static) printf "{\"gpu_data\":[{\"gpu\":0,\"asic\":{\"market_name\":\"AMD Radeon RX 9070 XT\"},\"vram\":{\"size\":{\"value\":16368}},\"bus\":{\"bdf\":\"0000:03:00.0\"}}]}" ;;
metric) echo "{}" ;;
esac'
shim readlink 'if [[ $1 == -f && $2 == /dev/dri/by-path/* ]]; then echo /dev/dri/renderD129; else /usr/bin/readlink "$@"; fi'
"$CLI" run "$ID" amd-rocm:0
wait_for ready
engine=$(grep -- "--name omarchy-local-ai-$ID-engine" "$SHIM/docker.log" | tail -1)
[[ $engine == *'--device /dev/dri/renderD129'* && $engine != *'/dev/kfd'* && $engine != *'--gpus'* ]] || fail "Vulkan devices" "$engine"
"$CLI" stop "$ID"
rm -f "$TMP/bin/amd-smi" "$TMP/bin/readlink"
recipes "$PIN"
pass "a Vulkan recipe receives its render node without ROCm or NVIDIA devices"

rm -rf "$HOME/.cache/omarchy"
SHIM_CORRUPT=1 "$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == *"does not match the pinned revision"* ]] || fail "corrupt reason" "$(cat "$STATE/deploy/$ID/status.json")"
pass "a download that does not match the Hub's hash is deleted and reported"
"$CLI" stop "$ID"

# before setup (not in the docker group) a start asks for nothing and says what to do
if SHIM_NOGROUP=1 "$CLI" run "$ID" nvidia:0 2>"$TMP/nogroup.err"; then fail "started before setup"; fi
grep -q "not set up yet: choose Set up Local AI" "$TMP/nogroup.err" || fail "setup reason" "$(cat "$TMP/nogroup.err")"
[[ ! -d $STATE/deploy/$ID ]] || fail "a deployment before setup"
pass "before setup a start asks for no password and says to set up Local AI"

# after setup the account is in the docker group, but a login from before it cannot reach the daemon unless setup
# gave it the socket: the panel says to log in again, and a start says the same instead of failing inside docker
[[ $(OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$CLI" snapshot | jq -c '[.setupNeeded, .relogin]') == "[false,true]" ]] || fail "relogin"
if OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$CLI" run "$ID" nvidia:0 2>"$TMP/relogin.err"; then fail "started without docker"; fi
grep -q "log out and back in once" "$TMP/relogin.err" || fail "relogin reason" "$(cat "$TMP/relogin.err")"
pass "set up but unreachable from this login: the panel and a start both say to log in again"

recipes "$PIN"
mkdir -p "$STATE/deploy" "$HOME/.cache/omarchy/local-ai/models/test--model@000000000000" "$HOME/.cache/huggingface"
# Prior tests finish with no managed deployment.
rm -rf "$STATE/deploy"/*
echo keep >"$HOME/.cache/huggingface/keep"
echo weights >"$HOME/.cache/omarchy/local-ai/models/test--model@000000000000/weights"
"$CLI" forget "$ID"
[[ ! -e $HOME/.cache/omarchy/local-ai/models/test--model@000000000000 && -f $HOME/.cache/huggingface/keep ]] || fail "forget scope"
pass "forget removes stopped managed weights and preserves the external Hugging Face cache"

ln -s "$HOME/.cache/huggingface" "$HOME/.cache/omarchy/local-ai/models/test--model@000000000000"
if "$CLI" forget "$ID" 2>"$TMP/forget.err"; then fail "followed a symlink while deleting"; fi
[[ -f $HOME/.cache/huggingface/keep ]] || fail "symlink target deleted"
pass "forget refuses a symlink outside the managed download"

# The whole life of an install, counting password prompts: before setup, after it, after an update, then run,
# share, unshare, refresh the catalog, stop and remove. Setup is judged by the machine, so a changed backend (an
# update) does not ask for it again.
shim omarchy-hw-nvidia 'exit 1'
shim tailscale 'printf "%s\n" "$*" >>"$SHIM/tailscale.log"'
fresh=$TMP/fresh/bin/omarchy-local-ai
mkdir -p "${fresh%/*}"
cp "$ROOT/bin/omarchy-local-ai" "$fresh"
cp "$TMP/plugin/recipes.json" "$TMP/plugin/manifest.json" "$TMP/fresh/"
sed -i "s|CATALOG=\$HOME/.cache/omarchy/local-ai/recipes.json|CATALOG=$TMP/catalog.json|" "$fresh"
[[ $(SHIM_NOGROUP=1 "$fresh" snapshot | jq .setupNeeded) == true ]] || fail "setup before setup"
[[ $(SHIM_NOGROUP=1 OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$fresh" snapshot | jq -c '[.setupNeeded, .relogin]') == "[true,false]" ]] || fail "setup before relogin"
[[ $("$fresh" snapshot | jq .setupNeeded) == false ]] || fail "setup after setup"
printf '\n# an update\n' >>"$fresh"
[[ $("$fresh" snapshot | jq .setupNeeded) == false ]] || fail "setup asked again after an update"
pass "setup is needed before it runs, and neither after it nor after an update"
echo 'Setup did not finish' >"$STATE/setup-error"
[[ $("$fresh" snapshot | jq -r .setupError) == 'Setup did not finish' ]] || fail "setup error missing from snapshot"
rm "$STATE/setup-error"
pass "a failed setup terminal leaves its reason in the next snapshot"

rm -f "$HOME/.cache/omarchy/local-ai/models/test--model@000000000000" # the symlink the case above left
"$CLI" run "$ID" nvidia:0
wait_for ready
"$CLI" share "$ID"
grep -q "^serve --bg --https=12434 http://127.0.0.1:12434" "$SHIM/tailscale.log" || fail "share" "$(cat "$SHIM/tailscale.log" 2>/dev/null)"
"$CLI" share "$ID" off
grep -q "^serve --https=12434 off" "$SHIM/tailscale.log" || fail "unshare" "$(cat "$SHIM/tailscale.log")"
cp "$TMP/plugin/recipes.json" "$SHIM/registry.json"
"$CLI" registry
jq -e '.registryCommit == "0000000000000000000000000000000000000001"' "$TMP/catalog.json" >/dev/null || fail "refresh" "$(head -c 300 "$TMP/catalog.json" 2>/dev/null)"
"$CLI" stop "$ID"
# an engine that fails leaves its last lines in the log and its first error in the message, though its container is gone
SHIM_ENGINE_LOG=1 SHIM_EMPTY=1 "$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == "the model returned no answer: RuntimeError: XPU out of memory. Tried to allocate 2.00 GiB" ]] ||
  fail "crash reason" "$(cat "$STATE/deploy/$ID/status.json")"
grep -q "^loading shards" "$STATE/deploy/$ID/err" || fail "engine log kept" "$(cat "$STATE/deploy/$ID/err")"
! compgen -G "$SHIM/containers/*engine" >/dev/null || fail "engine left running" "$(ls "$SHIM/containers")"
pass "a failed engine's last lines stay in the log and its first error is the reason shown"
"$CLI" stop "$ID"
"$CLI" run "$ID" nvidia:0
wait_for ready

# a load whose worker is gone reads as one line: a status from before this boot is a restart, a pid that is not a
# worker of ours (after a reboot the number can belong to anything) stopped unexpectedly, and a live worker is left be
st() { jq -c --arg a "$1" --argjson p "$2" '.state = "starting" | .at = $a | .pid = $p' "$STATE/deploy/$ID/status.json" >"$TMP/st" &&
  cp "$TMP/st" "$STATE/deploy/$ID/status.json"; "$CLI" snapshot | jq -r --arg id "$ID" '.deployments[] | select(.id == $id) | "\(.state) \(.error)"'; }
cp "$STATE/deploy/$ID/status.json" "$TMP/ready.json"
sleep 30 & other=$!
bash -c 'exec -a omarchy-local-ai-worker sleep 30' & ours=$!
[[ $(st 2000-01-01T00:00:00Z "$other") == "error the machine restarted while it was starting" ]] || fail "restart" "$(st 2000-01-01T00:00:00Z "$other")"
[[ $(st "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$other") == "error stopped unexpectedly" ]] || fail "reused pid" "$(st "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$other")"
[[ $(st "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ours") == "starting " ]] || fail "live worker" "$(st "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ours")"
kill "$other" "$ours" 2>/dev/null || true
cp "$TMP/ready.json" "$STATE/deploy/$ID/status.json"
pass "a load cut by a restart says so, a pid that is not ours reads as stopped, and a live worker keeps loading"

"$CLI" stop "$ID"
"$TMP/plugin/bin/omarchy-remove-ai-local"
[[ ! -d $STATE && -z $(ls "$SHIM/containers") ]] || fail "remove" "$(ls "$SHIM/containers")"
pass "run, share, unshare, refresh the catalog, stop and remove, as you"

[[ ! -s $SHIM/prompts.log ]] || fail "a password prompt" "$(cat "$SHIM/prompts.log")"
pass "no step asked for a password: setup is the only one, and it is not part of any of these"
