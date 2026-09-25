#!/bin/bash
# The backend end to end with shims for docker, curl, nvidia-smi, pkexec and the Omarchy helpers: no GPU,
# no daemon, no network. A synthetic recipe runs, answers, opens an agent and stops; the failure paths
# (an unpinned image, a corrupt download, a dismissed password prompt) end with the right reason.

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf '%s\n' "${2:-}" >&2; printf 'not ok - %s\n' "$1" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP/home SHIM=$TMP/shim XDG_RUNTIME_DIR=$TMP/run
mkdir -p "$HOME" "$SHIM/containers" "$TMP/bin" "$TMP/plugin/bin"
cp "$ROOT/bin/omarchy-local-ai" "$ROOT/manifest.json" "$TMP/plugin/" 2>/dev/null || true
mv "$TMP/plugin/omarchy-local-ai" "$TMP/plugin/bin/"
CLI=$TMP/plugin/bin/omarchy-local-ai
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
shim omarchy-sudo-docker '[[ -n ${SHIM_PROMPT:-} ]]'
shim omarchy-cmd-present 'command -v "$1" >/dev/null'
shim omarchy-cmd-missing '! command -v "$1" >/dev/null'
shim omarchy-notification-send 'echo 7'
shim omarchy-launch-tui 'printf "%s\n" "$*" >>"$SHIM/tui.log"'
shim pkexec 'printf "%s\n" "$*" >>"$SHIM/pkexec.log"; exit 126'
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
*/api/models/*) printf "[{\"type\":\"file\",\"path\":\"model.safetensors\",\"size\":4096,\"lfs\":{\"oid\":\"%s\"}}]" '"$SHA"' ;;
*/resolve/*) if [[ -n ${SHIM_CORRUPT:-} ]]; then head -c 4096 /dev/urandom >"$out"; else head -c 4096 /dev/zero >"$out"; fi ;;
http://127.0.0.1:*)
  ls "$SHIM/containers" | grep -q gateway || exit 7
  [[ $key == "$(cat "$HOME/.local/state/omarchy/local-ai/gateway.key")" ]] || { [[ $* == *http_code* ]] && printf 401; exit 22; }
  if [[ $url == */v1/models ]]; then
    printf "{\"data\":[{\"id\":\"served\"}]}" >"$out"
    [[ $* == *http_code* ]] && printf 200
  else
    echo "{\"usage\":{\"completion_tokens\":60}}"
  fi ;;
esac'
! command -v node >/dev/null || ln -s "$(command -v node)" "$TMP/bin/node"
export PATH=$TMP/bin:/usr/bin:/bin

recipes "$PIN"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r '.kinds[0].hw, .kinds[0].free[0], .kinds[0].models[0].id, (.gpus[] | select(.hw == "") | .name)' "$TMP/snap.json" | paste -sd' ') == "rtx-4090-24gb nvidia:0 $ID GT 710" ]] ||
  fail "snapshot" "$(jq -c . "$TMP/snap.json")"
pass "the snapshot matches the card to its kind and its one recipe, and lists a card with no recipe"

# The panel's view model reads this exact snapshot: a shape the backend changed and Model.js did not is a
# view that throws, which the panel can only show as an error
view() {
  node -e 'const fs = require("fs"), vm = require("vm"), c = {}; vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), c)
    const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), v = c.build(s, {view: process.argv[3], id: process.argv[4] || "", open: "", key: "", problem: ""})
    console.log(v.mark + " " + v.rows.map(r => r.type).join(","))' "$ROOT/Model.js" "$TMP/snap.json" "$@"
}
if command -v node >/dev/null; then
  [[ $(view home) == " sec,slot,slot,field" ]] || fail "home view" "$(view home 2>&1)"
  [[ $(view kind rtx-4090-24gb) == " sec,gpu,sec,field,field,sec,field,acts" ]] || fail "kind view" "$(view kind rtx-4090-24gb 2>&1)"
  pass "the view model builds home and the free card's page from the backend's own snapshot"
else
  echo "ok - the view model builds from the backend's snapshot # SKIP node is not installed"
fi

"$CLI" run "$ID" nvidia:0
wait_for ready
"$CLI" snapshot >"$TMP/snap.json"
if command -v node >/dev/null; then
  [[ $(view home) == "ready run,sec,slot,field" && $(view run "$ID") == "ready grid,sec,gpu,sec,field,field,sec,field,sec,field"*",acts" ]] ||
    fail "running views" "$(view home 2>&1; view run "$ID" 2>&1)"
  pass "the view model builds home and the model's page for a running model"
fi
pass "run downloads the weights, starts the engine and the gateway, and waits until the model answers"
[[ -f $HOME/.cache/omarchy/local-ai/models/test--model@000000000000/model.safetensors ]] || fail "weights" "$(find "$HOME/.cache" -type f)"
pass "the weights land under the model cache, checked against the Hub's size and sha256"
engine=$(grep -- '--name omarchy-local-ai-.*-engine' "$SHIM/docker.log")
[[ $engine == *"--gpus \"device=0\""* && $engine == *"--security-opt no-new-privileges"* && $engine == *":/models:ro"* &&
  $engine == *"--shm-size 8g"* && $engine == *"--env A=1"* && $engine != *NVIDIA_VISIBLE_DEVICES* && $engine != *--publish* &&
  $engine == *"$PIN --port 8000" ]] || fail "engine argv" "$engine"
pass "the engine gets its card, a read-only weights mount and the recipe's options, never a published port or its own card choice"
gateway=$(grep -- '--name omarchy-local-ai-.*-gateway' "$SHIM/docker.log")
[[ $gateway == *"--publish 127.0.0.1:12434:12434"* && $gateway == *"--user $(id -u):$(id -g)"* && $gateway == *"gateway.key:/run/gateway.key:ro"* ]] ||
  fail "gateway argv" "$gateway"
pass "the gateway runs as the user on 127.0.0.1 with the key mounted read-only"
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

"$CLI" stop "$ID"
[[ ! -d $STATE/deploy/$ID && -z $(ls "$SHIM/containers") ]] || fail "stop" "$(ls "$SHIM/containers" "$STATE/deploy")"
pass "stop removes both containers and the model's folder"

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
rm -rf "$HOME/.cache/omarchy"
SHIM_CORRUPT=1 "$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == *"does not match the pinned revision"* ]] || fail "corrupt reason" "$(cat "$STATE/deploy/$ID/status.json")"
pass "a download that does not match the Hub's hash is deleted and reported"
"$CLI" stop "$ID"

SHIM_PROMPT=1 "$CLI" run "$ID" nvidia:0
wait_for error
grep -qx "$CLI __start $ID 12434 nvidia:0" "$SHIM/pkexec.log" || fail "pkexec argv" "$(cat "$SHIM/pkexec.log")"
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == *"password prompt was dismissed"* ]] || fail "dismissed" "$(cat "$STATE/deploy/$ID/status.json")"
pass "without the docker group a start is one pkexec of this file with the recipe, port and card; a dismissed prompt is the reason shown"
