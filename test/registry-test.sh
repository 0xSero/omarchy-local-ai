#!/bin/bash
set -euo pipefail
shopt -s nullglob # as the backend runs
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CATALOG=$TMP/cache/recipes.json
export RECIPES=$ROOT/recipes.json
SOURCE=$ROOT/recipes.json
STATE=$TMP/state PANEL=$ROOT
mkdir -p "$STATE"
gpus() { echo '[{"hw": "rtx-3090"}, {"hw": ""}]'; }
MODE=ok
now() { echo 2026-09-29T00:00:00Z; }
die() { echo "local-ai: $*" >&2; exit 1; }
eval "$(sed -n '/^policy() {/,/^# cdi_stale:/p' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" | sed '$d')"
curl() {
  if [[ $* == *usage.sybilsolutions.ai* ]]; then [[ -z ${PINGDOWN:-} ]] || return 7; cat >>"$TMP/pings"
  elif [[ $* == *commits/main* ]]; then printf '{"sha":"%040d"}\n' 1
  elif [[ $MODE == offline ]]; then return 22
  elif [[ $MODE == malformed ]]; then echo broken
  elif [[ $MODE == unpinned ]]; then jq '.gateway.image = "gateway:latest"' "$SOURCE"
  elif [[ $MODE == newgateway ]]; then jq '.gateway.image = "ghcr.io/x/gateway@sha256:\("c" * 64)"' "$SOURCE"
  elif [[ $MODE == foreign ]]; then jq '.hardware[(.hardware | keys_unsorted[0])].recipes[0].image = "ghcr.io/stranger/engine@sha256:\("d" * 64)"' "$SOURCE"
  else cat "$SOURCE"; fi
}
[[ $(cmd_registry) == "models up to date · 00000000" ]]
echo "ok - registry refresh reports the published revision"
jq -e '.registryCommit == "0000000000000000000000000000000000000001" and (.hardware|length > 0)' "$CATALOG" >/dev/null

# The install count: one ping per refresh, a random id, the version, the card kinds with recipes, the running models
jq -e --arg v "$(jq -r .version "$ROOT/manifest.json")" 'keys == ["hw", "id", "running", "version"]
  and (.id | test("^[0-9a-f]{32}$")) and .version == $v and .hw == ["rtx-3090"] and .running == 0' "$TMP/pings" >/dev/null ||
  { echo "not ok - the ping: $(cat "$TMP/pings")"; exit 1; }
[[ $(stat -c %a "$STATE/install-id") == 600 ]] || { echo "not ok - install-id is readable by others"; exit 1; }
echo "ok - a refresh sends the install count: a random id, the version, the card kinds, the running models"
before=$(sha256sum "$CATALOG")
for MODE in offline malformed unpinned newgateway; do
  set +e
  (set -e; cmd_registry) >"$TMP/out" 2>&1
  rc=$?
  set -e
  [[ $rc != 0 && $(sha256sum "$CATALOG") == "$before" ]] || { echo "not ok - $MODE replaced the catalog"; exit 1; }
done
echo 'ok - registry updates atomically and retains the previous catalog on network, schema, pin and gateway changes'

# A refresh never brings new code: a recipe whose engine image comes from a repository this version's own recipes never
# use is left out, and the rest still arrive
MODE=foreign
cmd_registry >/dev/null
gone=$(jq -r '.hardware[(.hardware | keys_unsorted[0])].recipes[0].id' "$SOURCE")
! jq -e --arg id "$gone" '[.hardware[].recipes[].id] | index($id)' "$CATALOG" >/dev/null || { echo "not ok - a recipe with an unknown engine image arrived"; exit 1; }
! jq -e '[.hardware[].recipes[].image] | any(startswith("ghcr.io/stranger/"))' "$CATALOG" >/dev/null || { echo "not ok - an unknown engine image arrived"; exit 1; }
(( $(jq '[.hardware[].recipes[]] | length' "$CATALOG") == $(jq '[.hardware[].recipes[]] | length' "$SOURCE") - 1 )) || { echo "not ok - the other recipes did not arrive"; exit 1; }
echo 'ok - a refresh leaves out recipes whose engine image this plugin version does not know, and keeps the rest'

# The same id on every refresh; nothing sent when turned off or with DO_NOT_TRACK; an unreachable counter fails nothing
(( $(jq -s 'map(.id) | unique | length' "$TMP/pings") == 1 && $(wc -l <"$TMP/pings") > 1 )) ||
  { echo "not ok - refreshes sent different ids"; exit 1; }
MODE=ok
n=$(wc -l <"$TMP/pings")
echo '{"ping": "off"}' >"$STATE/settings.json"
cmd_registry >/dev/null
rm "$STATE/settings.json"
DO_NOT_TRACK=1 cmd_registry >/dev/null
(( $(wc -l <"$TMP/pings") == n )) || { echo "not ok - a ping was sent while turned off"; exit 1; }
[[ $(PINGDOWN=1 cmd_registry) == "models up to date · 00000000" ]] || { echo "not ok - an unreachable counter failed the refresh"; exit 1; }
echo "ok - the same id every time; set ping off and DO_NOT_TRACK send nothing; an unreachable counter fails nothing"
