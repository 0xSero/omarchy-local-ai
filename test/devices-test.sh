#!/bin/bash
# Running containers reserve GPUs across accounts, even when VRAM use is unknown or low.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
source "$ROOT/lib/access.sh"
export PANEL=$ROOT
RECIPES=$TMP/recipes.json
paths "$TMP/home"
mkdir -p "$STATE/deploy"
jq -n '{hardware:{
  nv:{match:{backend:"nvidia",names:["rtx4090"],vramGb:24},recipes:[{id:"nv",name:"NVIDIA",cards:1,weights:[]}]},
  xe:{match:{backend:"intel-xpu",names:["arcprob70"],vramGb:32},recipes:[{id:"xe",name:"Intel",cards:1,weights:[]}]}
}}' >"$RECIPES"
nvidia() { printf '%s\n' '0, NVIDIA GeForce RTX 4090, 24576, 20, 35' '1, NVIDIA GeForce RTX 4090, 24576, 20, 35'; }
intel() { printf 'null\t/dev/dri/renderD128\nnull\t/dev/dri/renderD129\n'; }
amd() { echo '[]'; }
docker_reachable() { return 0; }
readiness() { printf 'ready\t\n'; }
omarchy-cmd-present() { return 1; }
adopt() { :; }
host() { echo '{"have":[],"got":{},"freeRamGb":1024,"diskFreeGb":1024}'; }
tokens() { echo '{}'; }
get() { echo ''; }
bin() { return 1; }
policy() { echo ok; }
# No launch is ever allowed, including a regressed implementation under test.
setsid() { return 1; }
ss() { :; }
docker() {
  case $1 in
  ps) [[ ${DAEMON_DOWN:-0} == 0 ]] || return 1; [[ ${EMPTY:-0} == 1 ]] || echo foreign-container ;;
  inspect) [[ ${INSPECT_DOWN:-0} == 0 ]] || return 1; printf '%s\n' "$CLAIMS" ;;
  *) echo "unexpected Docker mutation: $1" >&2; return 99 ;;
  esac
}
failed=0
check() {
  local name=$1 rc; shift
  set +e
  (set -e; "$@") >"$TMP/out" 2>&1
  rc=$?
  set -e
  if ((rc == 0)); then echo "ok - $name"; else echo "not ok - $name"; cat "$TMP/out"; failed=$((failed + 1)); fi
}
reserved() {
  local expected=$1
  cmd_snapshot >"$TMP/snapshot"
  jq -e --argjson expected "$expected" '[.kinds[].taken[]] | sort == ($expected | sort)' "$TMP/snapshot" >/dev/null
  jq -e --argjson expected "$expected" '[.kinds[].free[]] | all(. as $k | $expected | index($k) == null)' "$TMP/snapshot" >/dev/null
}
refused() {
  local rc
  set +e
  (set -e; cmd_run "$1" "$2") >"$TMP/run-out" 2>&1
  rc=$?
  set -e
  [[ $rc != 0 ]]
  grep -q 'in use by another program' "$TMP/run-out"
  [[ ! -f $STATE/deploy/$1/config.json ]]
}
CLAIMS='{"devices":[{"PathOnHost":"/dev/dri/renderD129"}],"requests":null}'
check 'a foreign render-node allocation reserves only that Intel card' reserved '["intel-xpu:1"]'
check 'run refuses an occupied Intel card with unknown VRAM use' refused xe intel-xpu:1
# Remove only this fixture deployment if the baseline regressed into starting it.
rm -rf "$STATE/deploy/xe"
CLAIMS='{"devices":[{"PathOnHost":"/dev/dri"}],"requests":null}'
check 'a whole DRI allocation reserves all Intel cards' reserved '["intel-xpu:0","intel-xpu:1"]'
CLAIMS='{"devices":[],"requests":[{"Driver":"","Count":0,"DeviceIDs":["0"],"Capabilities":[["gpu"]]}]}'
check 'NVIDIA device requests reserve only the requested index' reserved '["nvidia:0"]'
check 'run refuses a requested NVIDIA card even with low VRAM use' refused nv nvidia:0
rm -rf "$STATE/deploy/nv"
CLAIMS='{"devices":[],"requests":[{"Driver":"nvidia","Count":-1,"DeviceIDs":null,"Capabilities":[["gpu"]]}]}'
check 'an all-GPU request reserves every NVIDIA card' reserved '["nvidia:0","nvidia:1"]'
CLAIMS='{"devices":[],"requests":[{"Driver":"nvidia","Count":0,"DeviceIDs":["GPU-unknown"],"Capabilities":[["gpu"]]}]}'
check 'unresolved NVIDIA UUIDs conservatively reserve NVIDIA cards' reserved '["nvidia:0","nvidia:1"]'
CLAIMS='{"devices":[],"requests":null,"privileged":true}'
check 'privileged containers reserve every exposed GPU' reserved '["nvidia:0","nvidia:1","intel-xpu:0","intel-xpu:1"]'
CLAIMS='{"devices":[],"requests":null}'
check 'a container without GPUs leaves all cards free' reserved '[]'
EMPTY=1 check 'an empty daemon leaves all cards free' reserved '[]'
unavailable() {
  local rc
  set +e
  (set -e; gpus) >"$TMP/probe" 2>&1
  rc=$?
  set -e
  [[ $rc != 0 ]]
  grep -q 'could not check Docker GPU allocations' "$TMP/probe"
}
DAEMON_DOWN=1 check 'a daemon failure cannot turn held cards into free cards' unavailable
INSPECT_DOWN=1 check 'an inspection failure cannot turn held cards into free cards' unavailable
((failed == 0))
