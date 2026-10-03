#!/bin/bash
# Legacy container names survive upgrades; new deployments cannot collide across users.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
ALLOCATION_LOCK=$TMP/runtime
mkdir "$ALLOCATION_LOCK"
chmod 555 "$ALLOCATION_LOCK"
paths "$TMP/home"
# Separate users have separate state locks, but must serialize the shared GPU check and creation.
source "$TMP/functions"
ALLOCATION_LOCK=$TMP/runtime
paths "$TMP/home"
RECIPES=$TMP/recipes.json
echo '{"hardware":{"test":{"match":{"backend":"nvidia"}}},"gateway":{"image":"gateway"}}' >"$RECIPES"
recipe() { echo '{"hw":"test","cards":1,"image":"engine","weights":[],"launch":{"port":8080,"environment":{},"arguments":[]}}'; }
policy() { echo ok; }
cdi_stale() { :; }
nvidia_ready() { return 0; }
owned() { :; }
remove() { :; }
gpus() { printf '[{"key":"nvidia:0","hw":"test","held":%s,"usedMiB":1}]\n' "$([[ -f $TMP/allocated ]] && echo true || echo false)"; }
docker() {
  case $1 in
    info) echo NVIDIA ;;
    run) if [[ $* == *-engine* ]]; then sleep 1; echo "$PKEXEC_UID" >>"$TMP/starts"; touch "$TMP/allocated"; fi ;;
  esac
}
rundir() { echo "$TMP/run/$1"; }
(export PKEXEC_UID=1000; phase_start first 12434 nvidia:0) >"$TMP/first" 2>&1 & first=$!
(export PKEXEC_UID=1001; phase_start second 12435 nvidia:0) >"$TMP/second" 2>&1 & second=$!
rc1=0; wait "$first" || rc1=$?
rc2=0; wait "$second" || rc2=$?
[[ $((rc1 + rc2)) == 1 && $(wc -l <"$TMP/starts") == 1 ]]
grep -q 'nvidia:0 is in use' "$TMP/first" "$TMP/second"
echo 'ok - simultaneous users start only one engine on the same GPU'

[[ -d $ALLOCATION_LOCK && $(stat -c %a "$ALLOCATION_LOCK") == 555 ]]
echo "ok - allocation locks the runtime directory read-only without creating a daemon-specific lock file"
