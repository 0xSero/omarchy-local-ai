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
mkdir -p "$HOME" "$SHIM/containers" "$TMP/bin" "$TMP/plugin/bin" "$TMP/plugin/lib"
cp "$ROOT/bin/omarchy-remove-ai-local" "$TMP/plugin/bin/"
cp "$ROOT/lib/access.sh" "$TMP/plugin/lib/"
cp "$ROOT/bin/omarchy-local-ai" "$ROOT/manifest.json" "$TMP/plugin/" 2>/dev/null || true
mv "$TMP/plugin/omarchy-local-ai" "$TMP/plugin/bin/"
CLI=$TMP/plugin/bin/omarchy-local-ai
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

shim nvidia-smi '[[ $* == *uuid* ]] && { echo "GPU-test-${@: -1}"; exit; }
printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
# The CLI falls back to /opt/rocm/bin/amd-smi, so absence from PATH no longer
# keeps a host's real AMD card out of the sandbox; pin an empty report.
shim amd-smi 'echo "{\"gpu_data\":[]}"'
shim omarchy-setup-security-sudoless-docker 'exit 0'
# the account is listed in the docker group unless SHIM_NOGROUP (setup not run); newgrp starts the shell it is given and
# grants nothing, as when a login is still out of reach of the socket
shim getent '[[ $1 == group ]] && echo "docker:x:998:$([[ -n ${SHIM_NOGROUP:-} ]] || id -un)" || echo "$2:x:1000:1000::/home/$2:/bin/bash"'
shim newgrp 'printf "%s\n" "$*" >>"$SHIM/newgrp.log"; exec "$SHELL"'
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
info)
  # SHIM_CDI: the toolkit CDI list and no nvidia runtime, as after a fresh setup
  if [[ -n ${SHIM_CDI:-} ]]; then
    [[ $* == *DiscoveredDevices* ]] && printf "%s" "[{\"Source\":\"cdi\",\"ID\":\"nvidia.com/gpu=0\"}]"
    [[ $* == *Runtimes* ]] && printf "|%s" "{\"runc\":{}}"
    echo
  else echo "{\"nvidia\":{\"path\":\"nvidia-container-runtime\"},\"runc\":{\"path\":\"runc\"}}"; fi ;;
image) exit 1 ;;
pull) printf "latest: Pulling from x\nl1: Pulling fs layer\nl2: Pulling fs layer\nl2: Already exists\nl1: Download complete\nl1: Pull complete\n" ;;
network) : ;;
run) n=""; for ((i = 1; i <= $#; i++)); do [[ ${!i} == --name ]] && { j=$((i + 1)); n=${!j}; }; done; echo "1|$(id -u)" >"$c/$n" ;;
inspect) if [[ $* == *HostConfig.Devices* ]]; then echo "{\"devices\":[],\"requests\":null}"; exit 0; fi; n=${@: -1}; [[ -f $c/$n ]] || exit 1; [[ $* == *RestartCount* ]] && echo 0 || cat "$c/$n" ;;
logs) [[ -z ${SHIM_ENGINE_LOG:-} ]] || printf "loading shards\nRuntimeError: XPU out of memory. Tried to allocate 2.00 GiB\n"
  [[ -z ${SHIM_LOAD_LOG:-} ]] || cat "$SHIM_LOAD_LOG" ;;
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
  [[ -z ${SHIM_STOPPED:-} ]] || exit 7
  ls "$SHIM/containers" | grep -q gateway || exit 7
  [[ $key == "$(cat "$HOME/.local/state/omarchy/local-ai/gateway.key")" ]] || { [[ $* == *http_code* ]] && printf 401; exit 22; }
  if [[ $url == */v1/models ]]; then
    # SHIM_LOADING: the engine is still loading while this file exists
    if [[ -n ${SHIM_LOADING:-} && -e $SHIM_LOADING ]]; then [[ $* == *http_code* ]] && printf 503; exit 0; fi
    printf "{\"data\":[{\"id\":\"served\",\"max_model_len\":98304}]}" >"$out"
    if [[ $* == *http_code* ]]; then printf 200; fi
  else
    if [[ -n ${SHIM_EMPTY:-} ]]; then echo "{}"
    elif [[ -n ${SHIM_REASONING:-} ]]; then
      echo "{\"choices\":[{\"message\":{\"content\":null,\"reasoning\":\"The user wants 1 to 60.\"},\"finish_reason\":\"length\"}],\"usage\":{\"completion_tokens\":200}}"
    else
      echo "{\"choices\":[{\"message\":{\"content\":\"1, 2, 3\"}}],\"usage\":{\"completion_tokens\":200}}"
    fi
  fi ;;
esac'
! command -v node >/dev/null || ln -s "$(command -v node)" "$TMP/bin/node"
# jq logs every argument it is given: a secret in a jq argv is readable by other local users in
# /proc/<pid>/cmdline while jq runs, so the key must only ever reach it as a file path
REAL_JQ=$(command -v jq)
shim jq "printf '%s\n' \"\$*\" >>\"\$SHIM/jq.log\"; exec $REAL_JQ \"\$@\""
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
shim amd-smi 'echo "{\"gpu_data\":[]}"'
shim nvidia-smi '[[ $* == *uuid* ]] && { echo "GPU-test-${@: -1}"; exit; }
printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
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
shim amd-smi 'echo "{\"gpu_data\":[]}"'
shim nvidia-smi '[[ $* == *uuid* ]] && { echo "GPU-test-${@: -1}"; exit; }
printf "0, NVIDIA GeForce RTX 4090, 24564, 300, 41\n1, NVIDIA GeForce GT 710, 2048, 10, 30\n2, NVIDIA GeForce RTX 4090, 24564, 300, 38\n"'
recipes "$PIN"
pass "amd-smi 7.2's cards: an RX 7600 XT runs its recipes, an 8 GB RX 7600 is listed as a card with none"

# The panel's view model reads this exact snapshot: a shape the backend changed and Model.js did not is a
# view that throws, which the panel can only show as an error
view() {
  node -e 'const fs = require("fs"), vm = require("vm"), c = {}; vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), c)
    const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), v = c.build(s, {view: process.argv[3], id: process.argv[4] || "", open: "", key: "", problem: ""})
    console.log(v.mark + " " + v.rows.map(r => r.type).join(","))' "$ROOT/Model.js" "$TMP/snap.json" "$@"
}
# js <expression>: its value, with the view model's functions under c, the snapshot as s and ui(patch) a ui state
js() {
  node -e 'const fs = require("fs"), vm = require("vm"), c = {}; vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), c)
    const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), ui = p => Object.assign({view: "home", id: "", open: "", key: "", problem: ""}, p)
    const x = eval(process.argv[3]); console.log(typeof x === "string" ? x : JSON.stringify(x))' "$ROOT/Model.js" "$TMP/snap.json" "$1"
}
if command -v node >/dev/null; then
  [[ $(view home) == " sec,slot,slot,field,field,acts" ]] || fail "home view" "$(view home 2>&1)"
  [[ $(view kind rtx-4090-24gb) == " sec,gpu,sec,agent,links,field,sec,field,acts" ]] || fail "kind view" "$(view kind rtx-4090-24gb 2>&1)"
  pass "the view model builds home and the free card's page from the backend's own snapshot"
  # a crashed model whose card no GPU row shows (nvidia-smi failing after a driver update, a card taken out, a card
  # with no kind) is a row of its own with its reason and dismiss; a state the panel does not know yet still shows
  [[ $(js 's.deployments = [{id: "m", name: "M", keys: ["nvidia:9"], state: "error", error: "gone"}]; var v = c.build(s, ui())
    v.mark + " " + v.rows.map(r => r.type + (r.crashed ? ":" + r.label + ":" + r.dismiss : r.type === "error" ? ":" + r.label : "")).join(",")') == "failed sec,slot,slot,slot:M:stop|m,error:gone,field,field,acts" &&
    $(js 's.gpus = []; s.deployments = [{id: "m", name: "M", keys: ["nvidia:0"], state: "error", error: "gone"}];
    c.build(s, ui({open: "lost:m"})).rows.map(r => r.type + ":" + (r.label || r.items[0].label)).join(",")') == "sec:AVAILABLE,slot:M,error:gone,links:View logs,field:Agents,acts:Refresh models" &&
    $(js 's.deployments = [{id: "m", name: "M", keys: ["nvidia:1"], state: "error", error: "gone"}]; c.build(s, ui()).rows.filter(r => r.crashed).length') == 1 ]] ||
    fail "a crashed model on no listed card" "$(js 's.deployments = [{id: "m", name: "M", keys: ["nvidia:9"], state: "error"}]; c.build(s, ui())')"
  [[ $(js 's.deployments = [{id: "m", name: "M", keys: [], state: "pulling", detail: "pulling image"}]; var v = c.build(s, ui())
    v.mark + " " + v.rows.filter(r => r.type === "run").map(r => r.sub + " " + r.primary.action)') == "busy pulling image stop|m" ]] ||
    fail "an unknown state" "$(js 's.deployments = [{id: "m", name: "M", keys: [], state: "pulling"}]; c.build(s, ui())')"
  pass "a crashed model no GPU row shows can be dismissed from home, and a state the panel does not know shows as working"
  [[ $(js '[c.k(999950), c.k(950000), c.k(999), c.gb(0.004), c.gb(13.84)].join(" ")') == "1M 950K 999 <0.1 GB 14 GB" ]] || fail "rounding" "$(js '[c.k(999950), c.gb(0.004)]')"
  # the weeks after daylight saving ends (Sydney, April 5 2026) are an hour longer: June still starts at its first week
  [[ $(TZ=Australia/Sydney js 's.total = 1; s.life = {requests: 1, since: "Feb 3", start: Date.parse("2026-02-02T00:00:00+11:00") / 1000, today: 138,
    days: Array(140).fill(1)}; c.build(s, ui()).rows[0].months.map(m => m.label + m.col).join(" ")') == "Feb0 Mar4 Apr9 May13 Jun17" ]] || fail "months after a DST end"
  # a model whose recipe is gone and whose config has no start: no empty chip, no NaN; one stopping has no Stop
  [[ $(js 's.deployments = [{id: "gone--2", name: "gone", keys: ["nvidia:0"], state: "ready", port: 1, agent: "pi"}];
    var v = c.build(s, ui({view: "run", id: "gone--2"})); v.hero.chips.map(x => x.text).join(",") + " " + v.rows[0].cells[5].v') == "1 × RTX 4090 –" ]] ||
    fail "a model with no recipe or start" "$(js 's.deployments = [{id: "gone--2", keys: ["nvidia:0"], state: "ready"}]; c.build(s, ui({view: "run", id: "gone--2"}))')"
  [[ $(js 's.deployments = [{id: "m", name: "M", keys: ["nvidia:0"], state: "stopping"}];
    [c.build(s, ui()).rows.find(r => r.type === "run").primary.action, c.build(s, ui({view: "run", id: "m"})).rows.pop().items.pop().action,
      c.build(s, ui({view: "gpus", open: "gpu:nvidia:0"})).rows.find(r => r.type === "links").items.pop().action].join(",")') == ",," ]] ||
    fail "Stop while stopping"
  pass "the view model rounds before picking a unit, keeps months on their weeks across DST, and shows a model with no recipe or start"
  # Panel.qml: a refresh asked for while a snapshot runs (the one after a verb) runs once that one ends
  [[ $(js 'var q = fs.readFileSync(process.argv[1].replace(/Model\.js$/, "Panel.qml"), "utf8"), p = {Model: c, snap: {}, ui: {}, poll: {running: true},
    pollOut: {text: fs.readFileSync(process.argv[2], "utf8")}, Qt: {callLater: f => f()}}; p.root = p; vm.createContext(p)
    ;[q.match(/function refresh\(\) \{.*\}/)[0], q.match(/function polled\([^]*?\n  \}/)[0], "var exited = " + q.match(/id: poll\n[^]*?onExited: (function\(code\) \{.*\})/)[1]].forEach(f => vm.runInContext(f, p))
    p.refresh(); p.poll.running = false; p.exited(0); p.poll.running + " " + p.snap.gpus.length') == "true 3" ]] || fail "a refresh while a snapshot runs"
  # the plugin's path as Qt's URL gives it, for a folder named a%25b#c: its "%" and "#" stay encoded
  [[ $(js 'vm.runInNewContext(fs.readFileSync(process.argv[1].replace(/Model\.js$/, "Panel.qml"), "utf8").match(/property string cli: (.*)/)[1],
    {Qt: {resolvedUrl: u => "file:///home/a%2525b%23c/" + u}})') == "/home/a%25b#c/bin/omarchy-local-ai" ]] || fail "the backend's path"
  pass "the panel refreshes once a running snapshot ends when a verb asked meanwhile, and finds its backend in any folder"
  # The folder dialog preserves reserved characters through its URL and sends one path argument.
  [[ $(js 's.defaults.folder = "/home/x/My Projects/a|b#c?d%"; var a = c.build(s, ui({view: "kind", id: s.kinds[0].hw})).rows.find(r => r.icon === "folder").action
    var p = {ui: {}, nav() {}, run(x) { p.args = x }, folderDialog: {open() {}}, Quickshell: {env() {return "/home/x"}}}; vm.createContext(p)
    var q=fs.readFileSync(process.argv[1].replace(/Model\.js$/, "Panel.qml"), "utf8");
    for(var name of ["activate", "pickedFolder"]) vm.runInContext(q.match(new RegExp("function " + name + "\\([^]*?\\n  \\}"))[0],p);
    p.activate(a); p.pickedFolder(p.folderDialog.currentFolder,p.folderDialog.recipe); p.args.join(",")') == "set,folder,/home/x/My Projects/a|b#c?d%" ]] || fail "folder dialog URL round trip"
  pass "folder dialog preserves spaces, pipes, hashes, question marks and percent signs"

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
grep -q "regenerate it as root: nvidia-ctk cdi generate --output=$CDI_DIRS/nvidia.yaml" "$STATE/log" || fail "CDI repair log"
pass "a stale NVIDIA CDI spec stops before the engine, with the repair command in the log"
"$CLI" stop "$ID"

"$CLI" run "$ID" nvidia:0
wait_for ready
"$CLI" snapshot >"$TMP/snap.json"
if command -v node >/dev/null; then
  [[ $(view home) == "ready run,sec,slot,field,field,acts" && $(view run "$ID") == "ready grid,sec,gpu,sec,agent,links,field,acts,sec,field,sec,field"*",acts" ]] ||
    fail "running views" "$(view home 2>&1; view run "$ID" 2>&1)"
  pass "the view model builds home and the model's page for a running model"
fi
pass "run downloads the weights, starts the engine and the gateway, and waits until the model answers"
[[ $(grep -o "starting .*" "$STATE/log" | paste -sd'|') == *"|starting downloading the engine (first start only)|starting downloading the engine: 1 of 2 layers|starting downloading the engine: 2 of 2 layers|starting downloading the gateway (first start only)|starting downloading the gateway: 1 of 2 layers|starting downloading the gateway: 2 of 2 layers|starting starting the engine|"* ]] ||
  fail "start steps" "$(cat "$STATE/log")"
pass "the start reports each image's download, a line as each layer lands (once each), then the engine's start"
[[ $(SHIM_STOPPED=1 "$CLI" snapshot | jq -r '.deployments[0].error') == 'the engine stopped' ]] || fail "stopped engine message"
pass "a stopped engine has one concise recovery message"

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
! grep -q "$key" "$SHIM/curl.log" "$SHIM/docker.log" "$SHIM/jq.log" "$STATE/log" || fail "key leaked" "the key appears in an argv or the log"
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
# a copy whose recipe recipes.json no longer has is named after that recipe, not <recipe>--2
jq -c '.hardware["rtx-4090-24gb"].recipes[0].id = "renamed"' "$TMP/plugin/recipes.json" >"$TMP/r2" && mv "$TMP/r2" "$TMP/plugin/recipes.json"
"$CLI" snapshot >"$TMP/snap-gone.json"
[[ $(jq -r --arg id "$ID--2" '.deployments[] | select(.id == $id) | .name' "$TMP/snap-gone.json") == "$ID" ]] || fail "name of a gone recipe" "$(jq -c .deployments "$TMP/snap-gone.json")"
recipes "$PIN"
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

# after a fresh setup Docker knows the cards only through the toolkit's CDI list: each goes by its UUID
"$CLI" stop "$ID"
SHIM_CDI=1 "$CLI" run "$ID" nvidia:2
wait_for ready
engine=$(grep -- "--name omarchy-local-ai-$ID-engine" "$SHIM/docker.log" | tail -1)
[[ $engine == *"--device nvidia.com/gpu=GPU-test-2"* && $engine != *--gpus* ]] || fail "CDI device by UUID" "$engine"
[[ $(SHIM_CDI=1 "$CLI" snapshot | jq -r .readiness.state) == ready ]] || fail "a CDI list is ready"
"$CLI" stop "$ID"
"$CLI" run "$ID" nvidia:0
wait_for ready
pass "with only the toolkit's CDI list, a card goes to Docker by its UUID and the machine is ready"

# a model's week is its own: another copy's tokens count in the machine's week, not on this model's page
usage() { mkdir -p "$STATE/usage/$1"; printf '{"t":%d,"prompt":%d,"completion":10,"ms":500,"ttft_ms":50}\n' "$EPOCHSECONDS" "$2" >"$STATE/usage/$1/usage.jsonl"; }
usage "$ID" 990
usage "$ID--2" 49990
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r '"\(.week) \(.deployments[0].session.week)"' "$TMP/snap.json") == "51000 1000" ]] || fail "week per model" "$(jq -c '{week, d: .deployments}' "$TMP/snap.json")"
if command -v node >/dev/null; then
  [[ $(js 'c.build(s, ui({view: "run", id: s.deployments[0].id})).rows[0].cells[4].v') == 1K ]] || fail "week on the model's page" "$(js 'c.build(s, ui({view: "run", id: s.deployments[0].id})).rows[0]')"
fi
rm -rf "$STATE/usage/$ID--2"
pass "a model's page counts its own week, not every model's on the machine"

"$CLI" set agent pi "$ID"
"$CLI" open "$ID"
sleep 0.5
[[ -f $STATE/agents/pi/models.json && $(jq -r '.providers["omarchy-local"].baseUrl' "$STATE/agents/pi/models.json") == "http://127.0.0.1:12434/v1" ]] ||
  fail "pi config" "$(cat "$STATE/agents/pi/models.json" 2>/dev/null)"
grep -q -- "--provider omarchy-local --model Test Model" "$SHIM/tui.log" && ! grep -q "$key" "$SHIM/tui.log" || fail "open argv" "$(cat "$SHIM/tui.log")"
"$CLI" set agent pi
[[ $(jq -r .agent "$STATE/settings.json") == pi ]] || fail "explicit default agent"
pass "open starts the chosen agent on the gateway in a terminal, with the key only in its private config; the default is explicitly selected"

"$CLI" set agent hermes "$ID"
"$CLI" open "$ID"
sleep 0.5
grep -q -- "CUSTOM_BASE_URL=http://127.0.0.1:12434/v1 OPENAI_BASE_URL=http://127.0.0.1:12434/v1 .*hermes chat --provider custom --model Test Model" "$SHIM/tui.log" &&
  ! grep -q "$key" "$SHIM/tui.log" || fail "hermes argv" "$(tail -1 "$SHIM/tui.log")"
pass "Hermes opens on the gateway through --provider custom, without its own config.yaml, the key only in the environment"

# a registry update that renames a running model's recipe leaves its Open as it was; one started before its config
# kept what Open needs, whose recipe is gone since, still opens, under its id
"$CLI" set agent pi "$ID"
cp "$TMP/plugin/recipes.json" "$TMP/recipes.keep"
cp "$STATE/deploy/$ID/config.json" "$TMP/config.keep"
jq -c --arg id "$ID" '(.hardware[].recipes[] | select(.id == $id) | .id) |= . + "-renamed"' "$TMP/recipes.keep" >"$TMP/plugin/recipes.json"
"$CLI" open "$ID" || fail "open after a rename"
sleep 0.5
tail -1 "$SHIM/tui.log" | grep -q -- "--provider omarchy-local --model Test Model" || fail "open after a rename" "$(tail -1 "$SHIM/tui.log")"
jq -c 'del(.serve)' "$TMP/config.keep" >"$STATE/deploy/$ID/config.json"
"$CLI" open "$ID" || fail "open with no recipe"
sleep 0.5
tail -1 "$SHIM/tui.log" | grep -q -- "--provider omarchy-local --model $ID " || fail "open with no recipe" "$(tail -1 "$SHIM/tui.log")"
[[ $(jq '.providers["omarchy-local"].models[0].contextWindow' "$STATE/agents/pi/models.json") == 98304 ]] ||
  fail "open with no recipe takes the engine's context" "$(jq -c '.providers[].models[0]' "$STATE/agents/pi/models.json")"
cp "$TMP/recipes.keep" "$TMP/plugin/recipes.json"
cp "$TMP/config.keep" "$STATE/deploy/$ID/config.json"
pass "open keeps working when the registry renames or drops a running model's recipe, with the engine's own context"

# All supported agent adapters stay in private config or keyed environments: the gateway key reaches neither the
# terminal's argv nor a helper's, and the keyed environments are the only place it is handed over at all.
for agent in pi claude codex opencode omp crush grok copilot hermes; do
  shim "$agent" 'exit 0'
  "$CLI" set agent "$agent" "$ID"
  : >"$SHIM/jq.log"
  "$CLI" open "$ID"
  ! grep -q "$key" "$SHIM/tui.log" || fail "agent key leaked" "$agent"
  ! grep -q "$key" "$SHIM/jq.log" || fail "agent key leaked to jq argv" "$(cat "$SHIM/jq.log")"
done
pass "every supported agent opens without exposing the gateway key in terminal or helper arguments"
# the key is still where each agent can read it: the config file only this user reads
[[ $(jq -r '.providers["omarchy-local"].apiKey' "$STATE/agents/pi/models.json") == "$key" ]] ||
  fail "pi key in config" "$(jq -c '.providers["omarchy-local"]' "$STATE/agents/pi/models.json" 2>/dev/null)"
[[ $(jq -r '.providers["omarchy-local"].api_key' "$STATE/agents/crush/crush/crush.json") == "$key" ]] ||
  fail "crush key in config" "$(jq -c '.providers["omarchy-local"]' "$STATE/agents/crush/crush/crush.json" 2>/dev/null)"
pass "pi and Crush still get the gateway key, read from its 0600 file by the helper rather than passed to it"
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

# the engine restarts with the machine, so what it mounts (a config asset, by-path links) must outlive a reboot:
# a source in /run or XDG_RUNTIME_DIR is gone after one, and Docker mounts an empty directory in its place
jq -c '.hardware["rtx-4090-24gb"].recipes[0].asset = {name: "config.yml", mountPath: "/app/config.yml", text: "model: x"}' \
  "$TMP/plugin/recipes.json" >"$TMP/r2" && mv "$TMP/r2" "$TMP/plugin/recipes.json"
: >"$SHIM/docker.log"
"$CLI" run "$ID" nvidia:0
wait_for ready
engine=$(grep -- '--name omarchy-local-ai-.*-engine' "$SHIM/docker.log")
src=$(grep -o -- '--volume [^ ]*:/app/config.yml:ro' <<<"$engine" | cut -d' ' -f2 | cut -d: -f1)
[[ -n $src && $(cat "$src") == "model: x" && $src != "$XDG_RUNTIME_DIR"/* && $src != /run/* ]] || fail "asset mount" "$engine"
! grep -qE -- "--volume ($XDG_RUNTIME_DIR|/run)/" <<<"$engine" || fail "engine mounts from a tmpfs" "$engine"
"$CLI" stop "$ID"
[[ ! -e $src && ! -e ${src%/*} ]] || fail "stop leaves the engine's files" "$(ls -la "${src%/*}")"
recipes "$PIN"
pass "the engine's config asset lives in the user's state, so it outlives a reboot, and stop removes it"

SHIM_EMPTY=1 "$CLI" run "$ID" nvidia:0
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == "the model returned no answer" ]] || fail "empty answer reason"
[[ -z $(ls "$SHIM/containers") ]] || fail "empty answer cleanup"
"$CLI" stop "$ID"
pass "an empty completion is rejected and its containers are removed"

SHIM_REASONING=1 "$CLI" run "$ID" nvidia:0
wait_for ready
"$CLI" stop "$ID"
pass "a check answer that is all thinking, in vLLM's reasoning field, counts as an answer"


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
pass "a Vulkan recipe receives its render node without ROCm or NVIDIA devices"

# ROCm images need not share the host's group names (Halogen has no "render"
# group), so membership goes in as host GIDs; the shimmed getent answers 998.
jq '.hardware["rtx-4090-24gb"].match.backend = "amd-rocm"' "$TMP/plugin/recipes.json" >"$TMP/r2"
mv "$TMP/r2" "$TMP/plugin/recipes.json"
"$CLI" run "$ID" amd-rocm:0
wait_for ready
engine=$(grep -- "--name omarchy-local-ai-$ID-engine" "$SHIM/docker.log" | tail -1)
[[ $engine == *'--device /dev/kfd --group-add 998 --group-add 998'* && $engine != *'--group-add video'* ]] ||
  fail "ROCm group GIDs" "$engine"
"$CLI" stop "$ID"
pass "a ROCm recipe passes the video and render groups by host GID"

# the bar follows the engine's own log, and a card its driver resets mid-load ends the start at once, not after 30 minutes
export LOCAL_AI_SYSFS=$TMP/sys
mkdir -p "$LOCAL_AI_SYSFS/class/drm/renderD129/device"
printf '%s\n' "INFO Starting to load model /models..." \
  "Loading safetensors checkpoint shards:  50% Completed | 1/2 [00:51<00:51, 51.39s/it]" >"$TMP/engine.log"
: >"$TMP/loading"
SHIM_LOAD_LOG=$TMP/engine.log SHIM_LOADING=$TMP/loading "$CLI" run "$ID" amd-rocm:0
for ((i = 0; i < 50; i++)); do
  [[ $(jq -r '"\(.detail) \(.percent)"' "$STATE/deploy/$ID/status.json" 2>/dev/null) == "reading the weights: file 2 of 2 35" ]] && break
  sleep 0.2
done
[[ $(jq -r '"\(.detail) \(.percent)"' "$STATE/deploy/$ID/status.json") == "reading the weights: file 2 of 2 35" ]] ||
  fail "load step" "$(cat "$STATE/deploy/$ID/status.json")"
ln -s ../../../virtual/devcoredump/devcd1 "$LOCAL_AI_SYSFS/class/drm/renderD129/device/devcoredump"
wait_for error
[[ $(jq -r .error "$STATE/deploy/$ID/status.json") == "the GPU driver reset the card while the model loaded (kernel lines in the log)" ]] ||
  fail "reset reason" "$(cat "$STATE/deploy/$ID/status.json")"
! compgen -G "$SHIM/containers/*engine" >/dev/null || fail "hung engine left running" "$(ls "$SHIM/containers")"
grep -q "starting reading the weights: file 2 of 2" "$STATE/log" || fail "load step logged" "$(tail -5 "$STATE/log")"
pass "loading shows the engine's own step and percent, and a GPU reset mid-load fails the start at once"
"$CLI" stop "$ID"
rm -f "$TMP/loading" "$LOCAL_AI_SYSFS/class/drm/renderD129/device/devcoredump"
unset LOCAL_AI_SYSFS
shim amd-smi 'echo "{\"gpu_data\":[]}"'
rm -f "$TMP/bin/readlink"
recipes "$PIN"

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

# set up, but Docker is not running (no socket): the panel and a start both say so, no group is tried, and nobody is
# asked to log in again
: >"$SHIM/newgrp.log"
[[ $(OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$CLI" snapshot | jq -r .readiness.state) == docker-down ]] || fail "docker down"
[[ ! -s $SHIM/newgrp.log ]] || fail "newgrp has nothing to fix without a socket" "$(cat "$SHIM/newgrp.log")"
if OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$CLI" run "$ID" nvidia:0 2>"$TMP/down.err"; then fail "started without docker"; fi
grep -q "Docker is not running" "$TMP/down.err" || fail "docker down reason" "$(cat "$TMP/down.err")"
! grep -qi "log out" "$TMP/down.err" || fail "asked for a new login"
pass "set up but Docker unreachable: the panel and a start both say so, and nobody is asked to log in again"

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
mkdir -p "${fresh%/*}" "$TMP/fresh/lib"
cp "$ROOT/bin/omarchy-local-ai" "$fresh"
cp "$ROOT/lib/access.sh" "$TMP/fresh/lib/"
cp "$TMP/plugin/recipes.json" "$TMP/plugin/manifest.json" "$TMP/fresh/"
sed -i "s|CATALOG=\$HOME/.cache/omarchy/local-ai/recipes.json|CATALOG=$TMP/catalog.json|" "$fresh"
[[ $(SHIM_NOGROUP=1 "$fresh" snapshot | jq -r .readiness.state) == needs-setup ]] || fail "setup before setup"
[[ $(SHIM_NOGROUP=1 OMARCHY_DOCKER_SOCKET=$TMP/no-socket "$fresh" snapshot | jq -r .readiness.state) == needs-setup ]] || fail "setup before setup, socket out of reach"
[[ $("$fresh" snapshot | jq -r .readiness.state) == ready ]] || fail "setup after setup"
printf '\n# an update\n' >>"$fresh"
[[ $("$fresh" snapshot | jq -r .readiness.state) == ready ]] || fail "setup asked again after an update"
pass "setup is needed before it runs, and neither after it nor after an update"
echo 'Setup did not finish' >"$STATE/setup-error"
[[ $("$fresh" snapshot | jq -r .setupError) == 'Setup did not finish' ]] || fail "setup error missing from snapshot"
[[ $("$fresh" snapshot | jq -r .readiness.state) == needs-setup ]] || fail "a failed setup is not ready"
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
