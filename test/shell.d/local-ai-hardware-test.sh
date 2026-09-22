#!/bin/bash
# Detection, matching, gating, agents, and the shape of the record the card reads.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq
source "$ROOT/test/shell.d/fixtures/local-ai/env.sh"

write_recipes rtx-4090-24gb "$(recipe test-a)"

SHIM_GPUS="0, NVIDIA GeForce RTX 3050, 8192, 100, 8000" "$CLI" snapshot >/dev/null
[[ $(snap .hardwareId) == "" && $(snap .statusText) == "Unsupported GPU" && $(snap .helpText) == *"no validated recipe for NVIDIA GeForce RTX 3050"* && $(snap '.recipes|length') == 0 ]] || fail "unsupported" "$(cat "$STATE/snapshot.json")"
pass "a GPU the registry has not validated is named as unsupported, with no recipe offered"

SHIM_GPUS="" "$CLI" snapshot >/dev/null 2>&1 || true
SHIM_GPUS=$'0, NVIDIA GeForce RTX 3050, 8192, 100, 8000\n1, NVIDIA GeForce RTX 4090, 24564, 300, 24264' "$CLI" snapshot >/dev/null
[[ $(snap .hardwareId) == rtx-4090-24gb && $(snap '.gpus[1].chosen') == true && $(snap '.cards|length') == 2 && $(snap '.cards[0].name') == "RTX 4090" ]] || fail "largest first" "$(snap .cards)"
pass "with two cards the largest one with a recipe is chosen, and every card type is listed"

"$CLI" gpu nvidia:0 >/dev/null; SHIM_GPUS=$'0, NVIDIA GeForce RTX 3050, 8192, 100, 8000\n1, NVIDIA GeForce RTX 4090, 24564, 300, 24264' "$CLI" snapshot >/dev/null
[[ $(snap '.gpus[0].chosen') == true && $(snap .hardwareId) == "" ]] || fail "pinned" "$(snap .gpus)"
"$CLI" gpu auto >/dev/null
pass "gpu <key> pins the card the snapshot looks at"

SHIM_DRIVER=550.0 "$CLI" snapshot >/dev/null
write_recipes rtx-4090-24gb "$(recipe test-a dir '.minDriver="575.0"')"
SHIM_DRIVER=550.0 "$CLI" snapshot >/dev/null
[[ $(snap '.recipes[0].gate') == *"needs NVIDIA driver 575.0"* ]] || fail "driver gate" "$(snap '.recipes[0]')"
SHIM_DRIVER=550.0 "$CLI" load test-a
[[ $(snap .state) == error && $(snap .error) == *"needs NVIDIA driver 575.0"* ]] || fail "driver refuse" "$(snap .error)"
pass "a driver older than the recipe's floor gates the row and refuses the load"

# Intel cards by PCI id, one per render node; the engine gets only the chosen node
mkdir -p "$TMP/dri"; touch "$TMP/dri/pci-0000:84:00.0-render" "$TMP/dri/pci-0000:c3:00.0-render"
write_recipes intel-arc-pro-b70-32gb "$(recipe b70)"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" snapshot >/dev/null
[[ $(snap '[.gpus[]|select(.backend=="intel-xpu")]|length') == 2 && $(snap '.cards[0].count') == 2 && $(snap '.cards[0].totalGb') == 64 ]] || fail "intel" "$(snap .gpus)"
pass "two Arc Pro B70 named only by PCI id are detected as one card type with two cards"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" load b70 intel-xpu:1
[[ $(snap .state) == ready ]] || fail "intel load" "$(snap .error) $(cat "$STATE/log")"
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine == *"--device $TMP/dri/pci-0000:c3:00.0-render:"* && $engine != *"pci-0000:84:00.0"* && $engine == *"--volume /dev/dri/by-path:/dev/dri/by-path:ro"* && $engine != *"--gpus"* ]] || fail "intel devices" "$engine"
pass "an Intel launch exposes only the selected render node, never the whole /dev/dri"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" unload >/dev/null

# a two-card recipe claims two cards of its type
write_recipes intel-arc-pro-b70-32gb "$(recipe b70 dir '.cards=2')" "$(recipe b70-one)"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" load b70
[[ $(snap .state) == ready && $(snap '.models[0].keys|length') == 2 ]] || fail "tp2" "$(snap .models) $(snap .error)"
pass "a two-card recipe claims two cards"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" load b70-one
[[ $(snap .state) == ready && $(snap '.models|length') == 1 && $(snap '.models[0].recipeId') == b70-one ]] || fail "replace tp2" "$(snap .models)"
pass "a one-card recipe on a busy card replaces the two-card model that held it"
SHIM_GPUS="" SHIM_LSPCI=1 "$CLI" unload >/dev/null
rm -rf "$TMP/dri"

# agents: the launch line carries the endpoint and the key by environment, never by argv
write_recipes rtx-4090-24gb "$(recipe test-a)"
"$CLI" snapshot >/dev/null
"$CLI" agent claude 2>/dev/null && fail "agent without model"
[[ $(snap .error) == *"load a model first"* ]] || fail "agent refusal" "$(snap .error)"
pass "an agent cannot be opened without a ready model"
"$CLI" load test-a >/dev/null
key=$(cat "$STATE/gateway.key")
for a in claude codex opencode pi omp crush copilot grok hermes ori agy muse cursor-agent; do
  line=$("$CLI" agent "$a") || fail "agent $a" "$(snap .error)"
  [[ $line != *"$key"* ]] || fail "key in argv" "$a: $line"
  [[ $line == *"omarchy-local-ai-workdir $HOME "* ]] || fail "workdir" "$a: $line"
done
pass "all thirteen agents launch on the model with the key kept out of their command line"
line=$("$CLI" agent claude); [[ $line == *"ANTHROPIC_BASE_URL=http://127.0.0.1:12434"* && $line == *"ANTHROPIC_AUTH_TOKEN"* && $line == *"--model Test-Model"* ]] || fail "claude line" "$line"
line=$("$CLI" agent codex); [[ $line == *"model_providers.local.base_url=http://127.0.0.1:12434/v1"* && $line == *"wire_api=responses"* ]] || fail "codex line" "$line"
line=$("$CLI" agent pi); [[ $line == *"PI_CODING_AGENT_DIR=$STATE/agents/pi"* && $(mode "$STATE/agents/pi/models.json") == 600 ]] || fail "pi line" "$line $(ls -l "$STATE/agents/pi")"
pass "each agent gets its own variables, and plugin-owned config files are private"
SHIM_APIS=chat "$CLI" load test-a >/dev/null
"$CLI" agent claude 2>/dev/null && fail "claude on chat-only"
[[ $(snap .error) == *"dialect"* ]] || fail "dialect refusal" "$(snap .error)"
pass "an agent whose dialect did not pass acceptance is refused"
[[ -z $(find "$HOME" -maxdepth 2 -newer "$STATE/gateway.key" -name '.*' -not -path "$HOME/.local*" -not -path "$HOME/.cache*" 2>/dev/null) ]] || fail "user files touched" "$(find "$HOME" -maxdepth 2 -newer "$STATE/gateway.key" -name '.*')"
pass "no file the user owns outside the plugin's own state was written"

mkdir -p "$HOME/project"; "$CLI" agent-dir "$HOME/project" >/dev/null
[[ $("$CLI" agent pi) == *"omarchy-local-ai-workdir $HOME/project "* ]] || fail "agent-dir" "$("$CLI" agent pi)"
pass "agents open in the chosen folder"

# the record the card reads
"$CLI" snapshot >/dev/null
for k in schemaVersion state error statusText helpText operation hardwareId gpus cards recipes models running agents port registry updatedAt; do jq -e --arg k "$k" 'has($k)' "$STATE/snapshot.json" >/dev/null || fail "snapshot field $k"; done
[[ $(snap .schemaVersion) == "omarchy-local-ai/snapshot/11" && $(mode "$STATE/snapshot.json") == 600 ]] || fail "snapshot shape"
pass "the snapshot carries every field the card renders, privately"
SHIM_PORT_BUSY=1 "$CLI" unload >/dev/null; SHIM_PORT_BUSY=1 "$CLI" snapshot >/dev/null
[[ $(snap .statusText) == "Port in use" && $(snap '.port.busy') == true ]] || fail "port busy" "$(snap .port)"
pass "a foreign listener on the gateway port is a status line on the card"
mv "$STATE/state.json" "$STATE/ledger.json"; "$CLI" snapshot >/dev/null
[[ -f $STATE/state.json && ! -f $STATE/ledger.json ]] || fail "5.x ledger"
pass "a 5.x ledger is adopted by rename"
