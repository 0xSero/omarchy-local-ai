#!/bin/bash
# One start at a time per account, on a lock in the account's own runtime directory that no other account can hold;
# two accounts that take the same card at the same moment are settled by Docker: the container created first keeps it.
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
RECIPES=$TMP/recipes.json
echo '{"hardware":{"test":{"match":{"backend":"nvidia"}}},"gateway":{"image":"gateway"}}' >"$RECIPES"
recipe() { echo '{"hw":"test","cards":1,"image":"engine","weights":[],"launch":{"port":8080,"environment":{},"arguments":[]}}'; }
policy() { echo ok; }
cdi_stale() { :; }
nvidia_ready() { return 0; }
owned() { :; }
remove() { :; }
gpus() { printf '[{"key":"nvidia:0","hw":"test","held":%s,"usedMiB":1}]\n' "$([[ -f $TMP/allocated ]] && echo true || echo false)"; }
# EARLIER: the allocation of a running container another account created before this start's engine
MINE='{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=GPU-a"]}],"privileged":false}'
docker() {
  case $1 in
    info) echo NVIDIA ;;
    version) echo 29.0.0 ;;
    network) if [[ $2 == inspect ]]; then echo 'true false isolated'; fi ;;
    run) if [[ $* == *-engine* ]]; then sleep 1; echo "$1" >>"$TMP/starts"; touch "$TMP/allocated"; fi ;;
    ps) echo "$*" >>"$TMP/ps"; [[ -z ${EARLIER:-} ]] || echo earlier ;;
    inspect) if [[ ${@: -1} == earlier ]]; then echo "$EARLIER"; else echo "$MINE"; fi ;;
    rm) echo "${@: -1}" >>"$TMP/removed" ;;
  esac
}
rundir() { echo "$TMP/run/$1"; }
# card 0 is GPU-a
nvidia-smi() { [[ ${*: -1} == 0 ]] && echo GPU-a; }
(phase_start first 12434 nvidia:0) >"$TMP/first" 2>&1 & first=$!
(phase_start second 12435 nvidia:0) >"$TMP/second" 2>&1 & second=$!
rc1=0; wait "$first" || rc1=$?
rc2=0; wait "$second" || rc2=$?
[[ $((rc1 + rc2)) == 1 && $(wc -l <"$TMP/starts") == 1 ]]
grep -q 'nvidia:0 is in use' "$TMP/first" "$TMP/second"
echo 'ok - two starts of one account on the same GPU start only one engine'

[[ -f $XDG_RUNTIME_DIR/omarchy-local-ai.allocation.lock && $(stat -c %u "$XDG_RUNTIME_DIR/omarchy-local-ai.allocation.lock") == "$(id -u)" ]]
# a lock anyone holds on the shared /run, as any account could, no longer stalls a start
rm -f "$TMP/allocated" "$TMP/starts"
(exec 9</run; flock 9; exec sleep 60) & holder=$!
sleep 0.3
(phase_start third 12436 nvidia:0) >"$TMP/third" 2>&1 || { cat "$TMP/third"; exit 1; }
kill "$holder" 2>/dev/null || true
(unset XDG_RUNTIME_DIR; allocation_lock)
[[ -f $STATE/omarchy-local-ai.allocation.lock ]]
echo "ok - the allocation lock is the account's own, in its runtime directory (else its state folder); a lock on /run blocks nothing"

# another account's engine created first on the same card: this start removes its engine and stops
rm -f "$TMP/allocated" "$TMP/starts" "$TMP/removed"
EARLIER='{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=GPU-a"]}],"privileged":false}'
if (phase_start fourth 12437 nvidia:0) >"$TMP/fourth" 2>&1; then echo "not ok - a card another account took first was kept"; exit 1; fi
grep -q 'nvidia:0 is in use by another program' "$TMP/fourth" && grep -q -- '-fourth-engine$' "$TMP/removed"
# one on another card, or with no GPU, leaves this start alone
for EARLIER in '{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=GPU-b"]}],"privileged":false}' \
  '{"devices":[{"PathOnHost":"/dev/kfd"}],"requests":null,"privileged":false}'; do
  rm -f "$TMP/removed" "$TMP/allocated"
  (phase_start fifth 12438 nvidia:0) >"$TMP/fifth" 2>&1 || { cat "$TMP/fifth"; exit 1; }
  [[ ! -f $TMP/removed ]]
done
# the same card named another way: by index through --gpus, by index as a CDI name; and an id it cannot place
for EARLIER in '{"devices":[],"requests":[{"Driver":"","Count":0,"DeviceIDs":["0"],"Capabilities":[["gpu"]]}],"privileged":false}' \
  '{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=0"]}],"privileged":false}' \
  '{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=all"]}],"privileged":false}' \
  '{"devices":[],"requests":[{"Driver":"nvidia","Count":0,"DeviceIDs":["MIG-1"],"Capabilities":[["gpu"]]}],"privileged":false}' \
  '{"devices":[{"PathOnHost":"/dev/nvidia0"}],"requests":null,"privileged":false}'; do
  if (settle me nvidia:0) >/dev/null 2>&1; then echo "not ok - the same card taken first another way was ignored: $EARLIER"; exit 1; fi
done
# another card named any of those ways is not this one
for EARLIER in '{"devices":[],"requests":[{"Driver":"","Count":0,"DeviceIDs":["1"],"Capabilities":[["gpu"]]}],"privileged":false}' \
  '{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["nvidia.com/gpu=1"]}],"privileged":false}' \
  '{"devices":[],"requests":[{"Driver":"cdi","DeviceIDs":["amd.com/gpu=0"]}],"privileged":false}'; do
  (settle me nvidia:0) || { echo "not ok - another card counted as this one: $EARLIER"; exit 1; }
done
# a container created but not started yet, restarting or paused holds its card too
grep -q -- '--filter status=running --filter status=created --filter status=restarting --filter status=paused --filter before=me' "$TMP/ps"
# a whole-GPU request, or the same render node, made first also wins
rm -f "$TMP/removed" "$TMP/allocated"
EARLIER='{"devices":[],"requests":[{"Driver":"nvidia","Count":-1,"DeviceIDs":null}],"privileged":false}'
if (phase_start sixth 12439 nvidia:0) >/dev/null 2>&1; then echo "not ok - an all-GPU container made first was ignored"; exit 1; fi
grep -q -- '-sixth-engine$' "$TMP/removed"
MINE='{"devices":[{"PathOnHost":"/dev/dri/renderD128"}],"requests":null,"privileged":false}'
EARLIER='{"devices":[{"PathOnHost":"/dev/dri/renderD128"}],"requests":null,"privileged":false}'
if (settle me intel-xpu:0) >/dev/null 2>&1; then echo "not ok - a render node taken first was ignored"; exit 1; fi
EARLIER='{"devices":[{"PathOnHost":"/dev/dri/renderD129"}],"requests":null,"privileged":false}'
(settle me intel-xpu:0)
echo 'ok - two accounts on one card at the same moment: the container Docker created first keeps it, the later one is removed'
