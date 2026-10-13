#!/bin/bash
# needs.cpus: a recipe whose engine pins work to more CPU threads than the machine has does not fit, and says so
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
B=${BACKEND:-$ROOT/bin/omarchy-local-ai}
FNS=$(mktemp); sed '/^paths "\$HOME"$/,$d' "$B" >"$FNS"
fit() { bash -c "source $FNS >/dev/null 2>&1; jq -r --argjson h '{\"cpus\": $1, \"freeRamGb\": 500, \"diskFreeGb\": 900, \"disk\": \"nvme\", \"have\": [], \"got\": {}}' \"\$NEEDS\"'unfit(\$h)' <<<'{\"needs\": {\"host_ram_gb\": 1, \"disk_gb\": 1, \"cpus\": 40}, \"weights\": []}'"; }
[[ $(fit 24) == "needs 40 CPU threads, you have 24" ]] && echo "ok - too few CPU threads: why" || { echo "not ok - too few CPU threads: $(fit 24)"; exit 1; }
[[ -z $(fit 48) ]] && echo "ok - enough CPU threads fits" || { echo "not ok - enough CPU threads: $(fit 48)"; exit 1; }
rm -f "$FNS"
