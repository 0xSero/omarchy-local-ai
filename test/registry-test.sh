#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CATALOG=$TMP/cache/recipes.json
export RECIPES=$ROOT/recipes.json
SOURCE=$ROOT/recipes.json
MODE=ok
now() { echo 2026-09-29T00:00:00Z; }
die() { echo "local-ai: $*" >&2; exit 1; }
eval "$(sed -n '/^policy() {/,/^# cdi_stale:/p' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" | sed '$d')"
curl() {
  if [[ $* == *commits/main* ]]; then printf '{"sha":"%040d"}\n' 1
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
