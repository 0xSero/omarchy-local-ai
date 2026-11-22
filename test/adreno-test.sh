#!/bin/bash
# Snapdragon X / Adreno detection, the one 16 GB recipe, and the Vulkan device flags.
# No GPU and no Docker daemon: sysfs and the engine log are fixtures.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
# shellcheck disable=SC1091
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE" "$TMP/run" "$TMP/sys/class/drm"
export XDG_RUNTIME_DIR=$TMP/run
RECIPES=$TMP/recipes.json
MEMINFO=$TMP/meminfo
APPLEMODEL=$TMP/no-model
SYS=$TMP/sys
jq -s '{schemaVersion: .[0].schemaVersion, registryCommit: .[0].registryCommit, gateway: .[0].gateway, hardware: .[1].hardware}' \
  "$ROOT/recipes.json" "$ROOT/recipes.snapdragon.json" >"$RECIPES"

card() {
  local name=$1 driver=$2 vendor=$3 chip=$4 render=$5 primary=$6
  local d=$SYS/class/drm/$name/device
  mkdir -p "$d/drm/${render:-none}" "$d/drm/${primary:-none}"
  [[ -n $render ]] || rm -rf "$d/drm/${render:-none}"
  printf 'DRIVER=%s\nPCI_ID=17CB:0C3F\n' "$driver" >"$d/uevent"
  printf '%s\n' "$vendor" >"$d/vendor"
  [[ -z $chip ]] || printf '%s' "$chip" >"$d/chip_id"
}

card card0 msm 0x17cb 0xffff43050c01 renderD128 card0
mkdir -p "$SYS/class/drm/card0-DP-1/device"
printf 'DRIVER=msm\n' >"$SYS/class/drm/card0-DP-1/device/uevent"
card card1 virtio_gpu 0x1af4 "" renderD129 card1
printf 'MemTotal: 32000000 kB\nMemAvailable: 24000000 kB\n' >"$MEMINFO"
uname() { echo aarch64; }
nvidia() { :; }
intel() { :; }
amd() { echo '[]'; }
docker_reachable() { return 1; }

got=$(gpus none | jq -c '[.[] | select(.backend=="adreno-vulkan") | {key, hw, backend, name}]')
[[ $got == '[{"key":"adreno-vulkan:0","hw":"snapdragon-x-16gb","backend":"adreno-vulkan","name":"Qualcomm Adreno X1-85"}]' ]] || {
  echo "not ok - 32 GB X1-85 match" >&2
  echo "$got" >&2
  exit 1
}
echo 'ok - a 32 GB Adreno X1-85 matches the one 16 GB recipe'

printf 'MemTotal: 16000000 kB\nMemAvailable: 10000000 kB\n' >"$MEMINFO"
[[ $(gpus none | jq -r '[.[] | select(.backend=="adreno-vulkan") | .hw][0]') == snapdragon-x-16gb ]]
echo 'ok - a 16 GB machine matches the 16 GB tier'

printf 'MemTotal: 64000000 kB\nMemAvailable: 50000000 kB\n' >"$MEMINFO"
[[ $(gpus none | jq -r '[.[] | select(.backend=="adreno-vulkan") | .hw][0]') == snapdragon-x-16gb ]]
echo 'ok - a 64 GB machine also matches the one shipped tier'

printf 'MemTotal: 7000000 kB\nMemAvailable: 4000000 kB\n' >"$MEMINFO"
[[ $(gpus none | jq -r '[.[] | select(.backend=="adreno-vulkan" and .hw != "")] | length') == 0 ]]
echo 'ok - a machine too small for the 16 GB tier is not offered the GPU recipe'

printf 'MemTotal: 32000000 kB\n' >"$MEMINFO"
printf '0xffff43030c00' >"$SYS/class/drm/card0/device/chip_id"
[[ $(gpus none | jq -r '.[] | select(.backend=="adreno-vulkan") | .name') == 'Qualcomm Adreno X1-45' ]]
echo 'ok - chip id 0xffff43030c00 is named Adreno X1-45'

rm -f "$SYS/class/drm/card0/device/chip_id"
[[ $(gpus none | jq -r '.[] | select(.backend=="adreno-vulkan") | .name') == 'Qualcomm Adreno X1' ]]
echo 'ok - an msm Qualcomm GPU without a chip id is still Adreno X1'

saved=$SYS
SYS=/sys
real=$(adreno 2>"$TMP/real.err")
SYS=$saved
jq -e 'type == "array"' <<<"$real" >/dev/null
[[ ! -s $TMP/real.err ]]
echo 'ok - probing the real sysfs returns a JSON array and stays quiet'

vivo=$TMP/vivo
disp=$vivo/devices/platform/soc@0/ae00000.display-subsystem/ae01000.display-controller
mkdir -p "$disp/drm/card1" "$disp/drm/renderD128" "$vivo/class/drm" "$vivo/bus/platform/devices/3d00000.gpu"
printf 'DRIVER=msm_dpu\nOF_NAME=display-controller\nOF_COMPATIBLE_0=qcom,x1e80100-dpu\n' >"$disp/uevent"
ln -s ../.. "$disp/drm/card1/device"
ln -s ../../devices/platform/soc@0/ae00000.display-subsystem/ae01000.display-controller/drm/card1 "$vivo/class/drm/card1"
ln -s ../../devices/platform/soc@0/ae00000.display-subsystem/ae01000.display-controller/drm/renderD128 "$vivo/class/drm/renderD128"
printf 'DRIVER=adreno\nOF_NAME=gpu\nOF_COMPATIBLE_0=qcom,adreno-43030c00\nMODALIAS=of:NgpuT(null)Cqcom,adreno-43030c00\n' \
  >"$vivo/bus/platform/devices/3d00000.gpu/uevent"
[[ ! -e $disp/vendor && ! -e $disp/drm/card1/device/vendor ]]
printf 'MemTotal: 15728640 kB\nMemAvailable: 9000000 kB\n' >"$MEMINFO"
SYS=$vivo
adreno >"$TMP/vivo.json" 2>"$TMP/vivo.err"
[[ ! -s $TMP/vivo.err ]] || { echo "not ok - vivobook probe wrote to stderr: $(cat "$TMP/vivo.err")" >&2; exit 1; }
got=$(gpus none | jq -c '[.[] | select(.backend=="adreno-vulkan") | {key, hw, name, node, primary}]')
[[ $got == '[{"key":"adreno-vulkan:0","hw":"snapdragon-x-16gb","name":"Qualcomm Adreno X1-45","node":"/dev/dri/renderD128","primary":"/dev/dri/card1"}]' ]] || {
  echo "not ok - X1 Plus msm_dpu" >&2
  echo "$got" >&2
  exit 1
}
[[ $(jq -r '.hardware["snapdragon-x-16gb"].recipes[0].id' "$RECIPES") == lfm25-26b-qad-q4-adreno-16gb ]]
echo 'ok - a 15 GB X1 Plus (msm_dpu + adreno-43030c00) is X1-45 on the 16 GB tier and stays quiet'
SYS=$saved
printf 'MemTotal: 32000000 kB\n' >"$MEMINFO"

for f in \
  /usr/lib/firmware/qcom/gen71500_sqe.fw \
  /usr/lib/firmware/qcom/gen71500_gmu.bin \
  /usr/lib/firmware/qcom/x1p42100/gen71500_zap.mbn
do
  grep -qF -- "$f" "$ROOT/bin/omarchy-local-ai" || { echo "not ok - firmware path missing: $f" >&2; exit 1; }
done
echo 'ok - gpu lists gen71500 sqe, gmu and the x1p42100 ZAP firmware'

valid_key adreno-vulkan:0 && valid_key cpu:0 && ! valid_key adreno-vulkan:x && ! valid_key adreno:0
echo 'ok - adreno-vulkan keys are accepted'

jq -e 'any(.hardware[]; .match.names | index("aarch64cpu") != null) | not' "$RECIPES" >/dev/null
jq -e 'any(.hardware[]; .match.backend == "hexagon-npu") | not' "$ROOT/recipes.snapdragon.json" >/dev/null
echo 'ok - this catalog adds no aarch64 CPU recipe and no Hexagon recipe'

r=$(recipe lfm25-26b-qad-q4-adreno-16gb)
[[ $(policy "$r") == ok ]] || { echo "not ok - policy: $(policy "$r")" >&2; exit 1; }
echo 'ok - the Adreno recipe passes the launch policy'

docker() { cat "$TMP/engine.log"; }
printf '%s\n' 'ggml_vulkan: No devices found.' >"$TMP/engine.log"
[[ $(adreno_offload demo) == fail\ no\ Vulkan\ device\ in\ the\ engine\ \(Mesa\ Turnip\ did\ not\ see\ the\ Adreno\).\ Run\ omarchy-local-ai\ gpu ]]
echo 'ok - no Vulkan device fails the GPU start'

cat >"$TMP/engine.log" <<'EOF'
llama_model_load_from_file_impl: using device Vulkan0 (llvmpipe (LLVM 18.1.0, 128 bits))
load_tensors: offloaded 24/24 layers to GPU
EOF
[[ $(adreno_offload demo) == fail\ Vulkan\ is\ not\ the\ Adreno\ GPU\ \(llama_model_load_from_file_impl:\ using\ device\ Vulkan0\ \(llvmpipe\ \(LLVM\ 18.1.0,\ 128\ bits\)\)\).\ Run\ omarchy-local-ai\ gpu ]]
echo 'ok - a software Vulkan device is not accepted'

cat >"$TMP/engine.log" <<'EOF'
0.12.345 I llama_prepare_model_devices: using device Vulkan0 (Adreno X1-45) (unknown id) - 10308 MiB free
0.12.456 I load_tensors: offloaded 31/31 layers to GPU
EOF
[[ $(adreno_offload demo) == 'ok 0.12.345 I llama_prepare_model_devices: using device Vulkan0 (Adreno X1-45) (unknown id) - 10308 MiB free' ]]
echo 'ok - b12211 -lv 4 log for Adreno X1-45 counts as the GPU path'

cat >"$TMP/engine.log" <<'EOF'
loading model
model loaded
main: server is listening
EOF
[[ $(adreno_offload demo) == wait ]]
echo 'ok - default verbosity does not count as the GPU'

jq -e 'any(.hardware[].recipes[]; .id == "lfm25-26b-qad-q4-adreno-16gb"
  and (.launch.arguments | index("-lv") != null)
  and .launch.arguments[(.launch.arguments | index("-lv")) + 1] == "4"
  and (.launch.arguments | index("off") != null)
  and .launch.environment.GGML_VK_DISABLE_INTEGER_DOT_PRODUCT == "1"
  and (.launch.arguments | index("f16") != null))' "$RECIPES" >/dev/null
echo 'ok - the recipe passes -lv 4, flash attention off, f16 KV, and integer-dot off'

owned() { :; }
remove() { :; }
: >"$TMP/docker.log"
docker() {
  printf '%s\n' "$*" >>"$TMP/docker.log"
  case $1 in
    version) echo 29.0.0 ;;
    network) [[ $2 == inspect ]] && echo 'true false isolated' ;;
    image) [[ $3 == omarchy-local-ai/adreno-vulkan:local ]] && return 1 ;;
    ps) return 0 ;;
  esac
  return 0
}
phase_start lfm25-26b-qad-q4-adreno-16gb 12434 adreno-vulkan:0 >/dev/null
engine_line=$(grep '^run ' "$TMP/docker.log" | head -1)
grep -F -- '--device /dev/dri/renderD128' <<<"$engine_line" >/dev/null
grep -F -- '--device /dev/dri/card0' <<<"$engine_line" >/dev/null
grep -F -- 'GGML_VK_DISABLE_INTEGER_DOT_PRODUCT=1' <<<"$engine_line" >/dev/null
grep -F -- 'freedreno_icd.json' <<<"$engine_line" >/dev/null
grep -F -- '--n-gpu-layers' <<<"$engine_line" >/dev/null
grep -F -- 'Vulkan0' <<<"$engine_line" >/dev/null
grep -F -- '-lv' <<<"$engine_line" >/dev/null
grep -F -- '--flash-attn' <<<"$engine_line" >/dev/null
if grep -F -- '--gpus' <<<"$engine_line" >/dev/null; then
  echo "not ok - Adreno start used --gpus" >&2
  exit 1
fi
echo 'ok - an Adreno engine is started with the render node, Turnip, and no NVIDIA --gpus'

: >"$TMP/docker.log"
docker() {
  printf '%s\n' "$*" >>"$TMP/docker.log"
  case $1 in
    version) echo 29.0.0 ;;
    network) [[ $2 == inspect ]] && echo 'true false isolated' ;;
    ps) return 0 ;;
  esac
  return 0
}
phase_start lfm25-26b-qad-q4-adreno-16gb 12434 adreno-vulkan:0 >/dev/null
grep -F -- 'omarchy-local-ai/adreno-vulkan:local' "$TMP/docker.log" >/dev/null
echo 'ok - a locally built Adreno image is used when it is already loaded'
