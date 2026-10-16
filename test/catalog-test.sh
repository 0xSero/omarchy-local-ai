#!/bin/bash
# Which recipes the backend reads: the refreshed catalog when it is newer than the bundled recipes.json, the bundled
# one when there is no catalog or the plugin was updated after the last refresh.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PANEL=$TMP/plugin
mkdir -p "$PANEL" "$TMP/cache/v3" "$TMP/cache/v4"
echo bundled >"$PANEL/recipes.json"
pick() {
  eval "$(grep -E '^(CATALOG|RECIPES)=|^\[\[ .*CATALOG' "$ROOT/bin/omarchy-local-ai" | sed "s|\$HOME/.cache/omarchy/local-ai|$TMP/cache|")"
  cat "$RECIPES"
}
[[ $(pick) == bundled ]] || { echo "not ok - no catalog"; exit 1; }
echo unsupported-legacy-cache >"$TMP/cache/recipes.json"
[[ $(pick) == bundled ]] || { echo "not ok - schema-2 cache reached schema-3 plugin"; exit 1; }
# a catalog an earlier version refreshed passed weaker checks: never read, however new
echo older-refresh >"$TMP/cache/v3/recipes.json"
touch -d '1 minute ago' "$PANEL/recipes.json"
[[ $(pick) == bundled ]] || { echo "not ok - a catalog an earlier version refreshed was read"; exit 1; }
echo refreshed >"$TMP/cache/v4/recipes.json"
[[ $(pick) == refreshed ]] || { echo "not ok - a refresh after the install"; exit 1; }
touch "$PANEL/recipes.json"
touch -d '1 minute ago' "$TMP/cache/v4/recipes.json"
[[ $(pick) == bundled ]] || { echo "not ok - an update after the last refresh"; exit 1; }
echo 'ok - a refreshed catalog is read until a plugin update brings newer recipes; one an earlier version refreshed never is'
