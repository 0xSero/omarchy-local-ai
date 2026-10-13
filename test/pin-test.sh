#!/bin/bash
# Pins: the latest first, a second copy of a model pins the model, off unpins, other settings are kept, a bad id is
# refused
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
B=${BACKEND:-$ROOT/bin/omarchy-local-ai}
FNS=$(mktemp); sed '/^paths "\$HOME"$/,$d' "$B" >"$FNS"
T=$(mktemp -d); echo '{"agent":"pi"}' >"$T/settings.json"
pin() { bash -c "set -euo pipefail; source $FNS >/dev/null 2>&1; STATE=$T; cmd_pin $*" 2>/dev/null; }
check() { local got; got=$(jq -c "$1" "$T/settings.json"); [[ $got == "$2" ]] && echo "ok - $3" || { echo "not ok - $3: want $2, got $got"; exit 1; }; }
pin a.3090; pin b.cpu
check .pins '["b.cpu","a.3090"]' "the latest pin first"
pin a.3090--2
check .pins '["a.3090","b.cpu"]' "a second copy pins its model, once, to the front"
pin b.cpu off
check .pins '["a.3090"]' "off unpins"
check .agent '"pi"' "other settings are kept"
pin '../x' && { echo "not ok - a bad id is refused"; exit 1; } || echo "ok - a bad id is refused"
rm -rf "$T" "$FNS"
