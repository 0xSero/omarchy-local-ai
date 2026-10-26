#!/bin/bash
# A llama.cpp Vulkan engine on an AMD card with Resizable BAR off keeps its buffers in card memory: llama.cpp otherwise
# fills the 256 MiB window the CPU can map and the driver puts the rest in system RAM (ggml-org/llama.cpp#27097).
# Only those engines, only on such a card; the gateway never gets the settings.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
export XDG_RUNTIME_DIR=$TMP/runtime
mkdir -m 700 "$XDG_RUNTIME_DIR"
paths "$TMP/home"
mkdir -p "$STATE"
SYS=$TMP/sys
RECIPES=$TMP/recipes.json
# vk is an amd-vulkan card kind (RX 9070 XT); rocm an amd-rocm one, whose recipes may still use llama.cpp's Vulkan
# image (RX 7900 XT)
jq -n '{hardware:{vk:{match:{backend:"amd-vulkan"}}, rocm:{match:{backend:"amd-rocm"}}}, gateway:{image:"gateway"}}' >"$RECIPES"
# the recipe id names its card kind, its engine and how many cards it runs on: vk-llama.cpp-1, rocm-vllm-1, ...
recipe() {
  local h=${1%%-*} rest=${1#*-}
  jq -nc --arg h "$h" --arg e "${rest%-*}" --argjson n "${rest##*-}" '{hw: $h, engine: $e, cards: $n, image: "engine",
    weights: [], launch: {port: 8080, environment: {}, arguments: []}}'
}
policy() { echo ok; }
owned() { :; }
remove() { :; }
gpus() { jq -nc --arg h "$HW" '[range(2) | {key: "amd-rocm:\(.)", hw: $h, held: false, usedMiB: 1, node: "/dev/dri/renderD\(128 + .)"}]'; }
docker() {
  case $1 in
    version) echo 29.0.0 ;;
    network) if [[ $2 == inspect ]]; then echo 'true false isolated'; fi ;;
    run) if [[ $* == *-engine* ]]; then printf '%s\n' "$@" >"$TMP/engine"; elif [[ $* == *-gateway* ]]; then printf '%s\n' "$@" >"$TMP/gateway"; fi ;;
  esac
}
rundir() { echo "$TMP/run/$1"; }
# the render nodes and the host's groups need not exist here
readlink() { if [[ $1 == -f ]]; then echo "$2"; else command readlink "$@"; fi; }
getent() { echo "$2:x:44:"; }
# card <node> <visible bytes> <total bytes>: amdgpu's two sizes; "-" leaves the file out
card() {
  local d=$SYS/class/drm/$1/device
  rm -rf "$d" && mkdir -p "$d"
  [[ $2 == - ]] || echo "$2" >"$d/mem_info_vis_vram_total"
  [[ $3 == - ]] || echo "$3" >"$d/mem_info_vram_total"
}
SMALL=268435456 FULL=17163091968
failed=0
check() {
  local name=$1 rc; shift
  set +e
  (set -e; "$@") >"$TMP/out" 2>&1
  rc=$?
  set -e
  if ((rc == 0)); then echo "ok - $name"; else echo "not ok - $name"; cat "$TMP/out"; failed=$((failed + 1)); fi
}
# start <hw> <recipe> <port> <card>...: the engine's and the gateway's docker run, one argument a line
start() {
  rm -f "$TMP/engine" "$TMP/gateway" "$LOG"
  HW=$1
  shift
  phase_start "$@" >/dev/null
  [[ -s $TMP/engine && -s $TMP/gateway ]]
}
kept() {
  grep -qx GGML_VK_DISABLE_HOST_VISIBLE_VIDMEM=1 "$TMP/engine"
  grep -qx GGML_VK_ALLOW_SYSMEM_FALLBACK=1 "$TMP/engine"
  [[ $(grep -c '^GGML_VK_' "$TMP/engine") == 2 ]]
  ! grep -q GGML_VK_ "$TMP/gateway"
}
untouched() { ! grep -q GGML_VK_ "$TMP/engine" && ! grep -qs 'reaches only part' "$LOG"; }

small_vulkan() {
  card renderD128 "$SMALL" "$FULL"
  start vk vk-llama.cpp-1 12434 amd-rocm:0
  kept
  grep -q "vk-llama.cpp-1: the CPU reaches only part of the memory of amd-rocm:0 (256 of 16368 MiB), so llama.cpp's Vulkan backend keeps its buffers in card memory. Turning Resizable BAR on in the firmware settings is the real fix" "$LOG"
}
check 'a Vulkan engine on a card with a 256 MiB BAR keeps its buffers in card memory, and the log says why' small_vulkan

rocm_kind() { card renderD128 "$SMALL" "$FULL"; start rocm rocm-llama.cpp-1 12434 amd-rocm:0; kept; }
check 'so does a llama.cpp engine of an amd-rocm card kind, as the RX 7900 XT runs the Vulkan image' rocm_kind

full_vulkan() { card renderD128 "$FULL" "$FULL"; start vk vk-llama.cpp-1 12434 amd-rocm:0; untouched; }
check 'a card with Resizable BAR on starts the engine unchanged' full_vulkan

unknown() {
  local p
  for p in -:- "$SMALL":- -:"$FULL" 0:"$FULL" garbage:"$FULL" "$SMALL":garbage; do
    card renderD128 "${p%:*}" "${p#*:}"
    start vk vk-llama.cpp-1 12434 amd-rocm:0
    untouched
  done
}
check 'a card that does not report both sizes, or reports nonsense, starts the engine unchanged' unknown

other_engine() { card renderD128 "$SMALL" "$FULL"; start rocm rocm-vllm-1 12434 amd-rocm:0; untouched; }
check 'an engine other than llama.cpp is not given the Vulkan settings' other_engine

pair() {
  card renderD128 "$FULL" "$FULL"
  card renderD129 "$SMALL" "$FULL"
  start vk vk-llama.cpp-2 12434 amd-rocm:0 amd-rocm:1
  kept
  grep -q 'the memory of amd-rocm:1 (256 of 16368 MiB), so' "$LOG"
}
check 'of two cards, the one with a small BAR is named and the engine gets the settings once' pair
((failed == 0))
