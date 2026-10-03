#!/bin/bash
# Legacy container names survive upgrades; new deployments cannot collide across users.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE/deploy/test"
echo '{}' >"$STATE/deploy/test/config.json"
[[ $(engine test) == omarchy-local-ai-test-engine ]] || exit 1
for owner in 1000 1001; do
  printf '{"containerUid":%s}\n' "$owner" >"$STATE/deploy/test/config.json"
  [[ $(engine test) == "omarchy-local-ai-$owner-test-engine" && $(gateway test) == "omarchy-local-ai-$owner-test-gateway" && $(network test) == "omarchy-local-ai-$owner-test" ]] || exit 1
done
echo 'ok - legacy names persist and two users have different container and network names'
# A card can become allocated after the UI's check or while images download.
RECIPES=$TMP/recipes.json
echo '{"hardware":{"test":{"match":{"backend":"nvidia"}}},"gateway":{"image":"gateway"}}' >"$RECIPES"
recipe() { echo '{"hw":"test","cards":1,"image":"engine"}'; }
policy() { echo ok; }
nvidia_ready() { return 0; }
cdi_stale() { :; }
owned() { :; }
gpus() {
  if [[ -f $TMP/removed ]]; then
    echo '[{"key":"nvidia:0","hw":"test","held":true,"usedMiB":1}]'
  else
    echo '[{"key":"nvidia:0","hw":"test","held":false,"usedMiB":1}]'
  fi
}
remove() { touch "$TMP/removed"; }
docker() { [[ $1 == image ]] || { touch "$TMP/launched"; return 99; }; }
if (phase_start test 12434 nvidia:0) >"$TMP/output" 2>&1; then exit 1; fi
grep -q 'nvidia:0 is in use by another program' "$TMP/output"
[[ ! -f $TMP/launched ]]
echo 'ok - launch rechecks allocations after downloads and before creating containers'
