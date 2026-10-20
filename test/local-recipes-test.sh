#!/bin/bash
# This machine's own recipes (recipes.local.json) laid over the recipes in use: merged, added, cached, skipped when
# they do not load, and never trusted more than a shipped recipe. Files only: no daemon, GPU or network.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
STATE=$TMP/state LOG=$TMP/log CATALOG=$TMP/cache/v4/recipes.json LOCAL_RECIPES=$TMP/recipes.local.json
mkdir -p "$STATE"
: >"$LOG"
PIN="ghcr.io/x/engine@sha256:$(printf 'a%.0s' {1..64})"
jq -n --arg pin "$PIN" '{gateway: {image: ("ghcr.io/x/gateway@sha256:" + ("b" * 64))},
  hardware: {"rtx-3060-12gb": {match: {backend: "nvidia"}, recipes: [{id: "shipped", name: "Shipped", image: $pin,
    launch: {arguments: ["-c", "4096"], environment: {A: "1"}, port: 8000}}]}}}' >"$TMP/recipes.json"
SHIPPED=$TMP/recipes.json
before=$(sha256sum <"$SHIPPED")

RECIPES=$SHIPPED
local_recipes
[[ $RECIPES == "$SHIPPED" && $BASE == "$SHIPPED" ]] || { echo "not ok - no recipes.local.json changed the recipes"; exit 1; }
echo 'ok - without recipes.local.json the recipes in use are read as they are'

jq -n --arg pin "$PIN" '{hardware: {
  "rtx-3060-12gb": {recipes: [{id: "shipped", launch: {arguments: ["-c", "8192"], resources: {sysNice: true}}},
    {id: "own", name: "Own", image: $pin, launch: {arguments: [], environment: {}, port: 8080}}]},
  "rtx-9999-1gb": {match: {backend: "nvidia"}, recipes: [{id: "other", name: "Other"}]}}}' >"$LOCAL_RECIPES"
local_recipes
[[ $RECIPES != "$SHIPPED" && $BASE == "$SHIPPED" ]] || { echo "not ok - recipes.local.json was not laid over"; exit 1; }
[[ $(jq -c '.hardware["rtx-3060-12gb"].recipes | map({id, name, a: .launch.arguments, e: .launch.environment, r: .launch.resources})' "$RECIPES") \
  == '[{"id":"shipped","name":"Shipped","a":["-c","8192"],"e":{"A":"1"},"r":{"sysNice":true}},{"id":"own","name":"Own","a":[],"e":{},"r":null}]' ]] ||
  { echo "not ok - merge"; jq -c '.hardware' "$RECIPES"; exit 1; }
[[ $(jq -r '.hardware["rtx-9999-1gb"].recipes[0].id, .gateway.image' "$RECIPES" | paste -sd' ') == "other ghcr.io/x/gateway@sha256:$(printf 'b%.0s' {1..64})" ]] ||
  { echo "not ok - a new card kind or the gateway"; exit 1; }
[[ $(sha256sum <"$SHIPPED") == "$before" ]] || { echo "not ok - the recipes in use were changed"; exit 1; }
echo 'ok - a recipe with a shipped id is merged over it, another is added after, a new card kind is taken with its match'

merged=$RECIPES
touch -d '1 hour ago' "$merged"
RECIPES=$SHIPPED
local_recipes
[[ $RECIPES == "$merged" && $(stat -c %Y "$merged") -lt $(($(date +%s) - 600)) ]] || { echo "not ok - the merge was not reused"; exit 1; }
jq '.hardware["rtx-3060-12gb"].recipes[1].name = "Renamed"' "$LOCAL_RECIPES" >"$TMP/edit" && mv "$TMP/edit" "$LOCAL_RECIPES"
RECIPES=$SHIPPED
local_recipes
[[ $RECIPES != "$merged" && ! -e $merged && $(jq -r '.hardware["rtx-3060-12gb"].recipes[1].name' "$RECIPES") == Renamed ]] ||
  { echo "not ok - an edit was not picked up, or the old merge kept"; exit 1; }
echo 'ok - the merge is cached until either file changes, and an outdated one is removed'

# found by id and run through the same policy as a shipped recipe: sysNice is a boolean, an unpinned image is refused
r=$(recipe own)
[[ $(policy "$r") == ok ]] || { echo "not ok - own recipe policy: $(policy "$r")"; exit 1; }
[[ $(policy "$(jq -c '.image = "ghcr.io/x/engine:latest"' <<<"$r")") == "image is not pinned by digest" ]]
[[ $(policy "$(jq -c '.launch.resources.sysNice = "yes"' <<<"$r")") == "invalid resources" ]]
[[ $(policy "$(jq -c '.launch.flags = ["--privileged"]' <<<"$r")") != ok ]]
[[ $(launch_options "$(recipe shipped)" | tr '\0' ' ') == *"--cap-add SYS_NICE "* ]] || { echo "not ok - sysNice"; exit 1; }
[[ $(launch_options "$r" | tr '\0' ' ') != *SYS_NICE* ]]
echo 'ok - an own recipe is checked like a shipped one, and sysNice adds only CAP_SYS_NICE'

for bad in '{"hardware": ' '[]' '{"hardware": {"rtx-3060-12gb": {"recipes": [{"id": "../x"}]}}}' \
  '{"hardware": {"rtx-3060-12gb": {"recipes": {}}}}' '{"hardware": {"new-kind": {"recipes": []}}}'; do
  printf '%s\n' "$bad" >"$LOCAL_RECIPES"
  RECIPES=$SHIPPED
  local_recipes
  [[ $RECIPES == "$SHIPPED" ]] || { echo "not ok - $bad was read"; exit 1; }
done
[[ $(grep -c 'are not used (it does not load)' "$LOG") == 1 ]] || { echo "not ok - the skip was not logged once"; cat "$LOG"; exit 1; }
! compgen -G "$TMP/cache/local/.recipes.*" >/dev/null || { echo "not ok - a temporary file was left"; exit 1; }
jq -n '{hardware: {}}' >"$LOCAL_RECIPES"
RECIPES=$SHIPPED
local_recipes
[[ ! -e $STATE/local-recipes-skipped ]] || { echo "not ok - a file that loads again is still skipped"; exit 1; }
echo 'ok - a file that does not load, a bad id or a new card kind without its match is skipped, logged once'
