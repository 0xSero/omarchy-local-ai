#!/bin/bash
# A card that drives the desktop is not "taken": its framebuffer and the compositor count in memory.used, but only the
# programs with a context on the card (nvidia-smi's compute apps) and Docker claims decide it (#175).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
bad() { echo "not ok - $*" >&2; exit 1; }
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
RECIPES=$TMP/recipes.json
echo '{"hardware":{"rtx-3070-8gb":{"match":{"backend":"nvidia","names":["rtx3070"],"vramGb":8},"recipes":[]}}}' >"$RECIPES"
MEMINFO=$TMP/meminfo
echo 'MemTotal:       65536000 kB' >"$MEMINFO"
intel() { :; }
amd() { echo '[]'; }
cpu() { echo '[]'; }
# one RTX 3070 with a monitor: 2.9 GB used, 4.9 GB free; APPS are the programs with a context on it. The backend calls it
# through timeout, so it is a program on PATH, not a function.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/nvidia-smi" <<'SH'
#!/bin/bash
case "$*" in
  *--query-compute-apps*) printf '%b' "${APPS:-}" ;;
  *) if [[ -n ${NOUUID:-} ]]; then echo "0, NVIDIA GeForce RTX 3070, 8192, ${USED:-2910}, 45"
     else echo "0, NVIDIA GeForce RTX 3070, 8192, ${USED:-2910}, 45, GPU-aaaa-3070, ${FREE:-4977}"; fi ;;
esac
SH
chmod +x "$TMP/bin/nvidia-smi"
export PATH=$TMP/bin:$PATH APPS USED FREE NOUUID
DESKTOP='GPU-aaaa-3070, 1201, /usr/bin/Hyprland, 136\nGPU-aaaa-3070, 1300, /usr/bin/Xwayland, 3\nGPU-aaaa-3070, 2210, /opt/zen-browser-bin/zen-bin, 206\nGPU-aaaa-3070, 2400, /usr/bin/quickshell, 16\n'

APPS=$DESKTOP USED='' FREE='' NOUUID=''
g=$(gpus none)
[[ $(jq -r '.[0] | "\(.key) \(.hw) \(.usedMiB) \(.freeMiB) \(.othersMiB) \(.others[0].name)"' <<<"$g") == "nvidia:0 rtx-3070-8gb 2910 4977 361 zen-bin" ]] ||
  bad "desktop card read as $(jq -c '.[0]' <<<"$g")"
[[ -z $(card_taken "$g" nvidia:0) ]] || bad "a desktop card is taken: $(card_taken "$g" nvidia:0)"
echo 'ok - the desktop on a card (framebuffer, compositor, browser) does not make it taken'

r='{"name":"Gemma 4 E4B","sizeGb":3.6,"cards":1}'
[[ -z $(card_room "$g" nvidia:0 "$r") ]] || bad "a model that fits in 4.9 GB free was refused: $(card_room "$g" nvidia:0 "$r")"
r='{"name":"Qwen3.5-9B","sizeGb":6.47,"cards":1}'
[[ $(card_room "$g" nvidia:0 "$r") == "Qwen3.5-9B needs 6.5 GB on nvidia:0; 4.9 GB is free" ]] ||
  bad "weights larger than the free memory: $(card_room "$g" nvidia:0 "$r")"
echo 'ok - a start is refused only when the weights do not fit in the free memory, and says how much is free'

# a program whose name carries its command line: the panel shows the program, not the flags
APPS="${DESKTOP}GPU-aaaa-3070, 2150, /opt/brave-browser/brave --type=gpu-process --gpu-preferences=AAAA, 412\n"
g=$(gpus none)
[[ $(jq -r '.[0].others[0].name' <<<"$g") == "brave" ]] ||
  bad "a program with flags in its name: '$(jq -r '.[0].others[0].name' <<<"$g")'"
echo 'ok - a program is named by its binary, not by the whole command line'

# a flag can hold a "/": a path, or base64. The binary is the first word, so the name is cut at the first space
# first; cutting at the last "/" first would name the tail of the flag
APPS="${DESKTOP}GPU-aaaa-3070, 2150, /opt/brave-browser/brave --type=gpu-process --user-data-dir=/home/u/.config/brave, 412\n"
g=$(gpus none)
[[ $(jq -r '.[0].others[0].name' <<<"$g") == "brave" ]] ||
  bad "a program with a path in its flags: '$(jq -r '.[0].others[0].name' <<<"$g")'"
APPS="${DESKTOP}GPU-aaaa-3070, 2150, /opt/brave-browser/brave --type=gpu-process --gpu-preferences=AAA/BB+CC==, 412\n"
g=$(gpus none)
[[ $(jq -r '.[0].others[0].name' <<<"$g") == "brave" ]] ||
  bad "a program with base64 in its flags: '$(jq -r '.[0].others[0].name' <<<"$g")'"
echo 'ok - a flag with a "/" in it does not take the name of the program'

APPS="${DESKTOP}GPU-aaaa-3070, 3100, /usr/bin/ollama, 5300\nGPU-bbbb-other, 3200, /usr/bin/python3, 9000\n"
USED=7900 FREE=0
g=$(gpus none)
[[ $(card_taken "$g" nvidia:0) == "ollama, zen-bin (5.5 GB)" ]] || bad "a card held by ollama: '$(card_taken "$g" nvidia:0)'"
echo 'ok - a program that holds the card is named with the memory it holds; programs on another card do not count'

g='[{"key":"nvidia:0","hw":"rtx-3070-8gb","held":true,"heldBy":["ollama"],"othersMiB":0}]'
[[ $(card_taken "$g" nvidia:0) == "another program" ]] || bad "a Docker-held card: '$(card_taken "$g" nvidia:0)'"
g='[{"key":"amd-rocm:0","hw":"x","held":false,"usedMiB":9000,"othersMiB":9000,"others":[]}]'
[[ $(card_taken "$g" amd-rocm:0) == "another program (8.8 GB)" ]] || bad "an AMD card: '$(card_taken "$g" amd-rocm:0)'"
echo 'ok - a card a container claims is taken as before, and AMD still counts its total'

# no UUID from the driver: the card total stands in, as before
APPS='' USED=7000 NOUUID=1
g=$(gpus none)
[[ $(jq -r '.[0].othersMiB' <<<"$g") == 7000 && -n $(card_taken "$g" nvidia:0) ]] || bad "no UUID: $(jq -c '.[0]' <<<"$g")"
echo 'ok - without a UUID to match programs to the card, its total memory still decides'
