#!/bin/bash
# Agent settings and updater routing, without touching installed agents.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE/deploy/test"
printf '{"agent":"pi"}\n' >"$STATE/settings.json"
printf '{"agent":"pi"}\n' >"$STATE/deploy/test/config.json"
cmd_set agent claude test
[[ $(jq -r .agent "$STATE/settings.json") == pi ]] || { echo 'not ok - model selection changed the default'; exit 1; }
[[ $(jq -r .agent "$STATE/deploy/test/config.json") == claude ]] || exit 1
cmd_set agent codex
[[ $(jq -r .agent "$STATE/settings.json") == codex && $(jq -r .agent "$STATE/deploy/test/config.json") == claude ]] || exit 1
echo 'ok - model agent and default are explicit independent choices'
# The external commands are functions so their argv is captured without network or installation.
export UPDATE_ARGS=$TMP/args
bin() { echo "$1"; }
omarchy-cmd-present() { [[ $1 == mise ]]; }
mise() {
  if [[ $1 == ls ]]; then
    [[ $* == *oh-my-pi* ]] && echo '[]' || echo '[{"installed":true}]'
  else printf '%s\n' "$*" >>"$UPDATE_ARGS"; fi
}
timeout() { shift; "$@"; }
omp() { printf 'omp %s\n' "$*" >>"$UPDATE_ARGS"; }
for a in pi claude codex opencode omp crush grok copilot hermes; do cmd_update "$a"; done
grep -qx -- '--yes upgrade --bump pi' "$UPDATE_ARGS"
grep -qx -- '--yes upgrade --bump npm:@xai-official/grok' "$UPDATE_ARGS"
grep -qx -- '--yes upgrade --bump pipx:hermes-agent\[extras=all\]' "$UPDATE_ARGS"
grep -qx -- 'omp update' "$UPDATE_ARGS"
[[ $(wc -l <"$UPDATE_ARGS") == 9 ]]
if (cmd_update 'pi;touch bad') >/dev/null 2>&1; then echo 'not ok - unknown updater accepted'; exit 1; fi
mise() { [[ $1 == ls ]] && echo '[{"installed":true}]' || return 1; }
if (cmd_update pi) >/dev/null 2>&1; then echo 'not ok - updater failure reported success'; exit 1; fi
echo 'ok - all nine update routes are scoped and updater failures stay failures'
# The plugin's own update: offered only for a release this checkout lacks, and run by Omarchy's update.
PANEL=$TMP/plugin
mkdir -p "$PANEL/.git"
printf '{"id":"sero.local-ai","version":"1.0.0"}\n' >"$PANEL/manifest.json"
omarchy-cmd-present() { [[ $1 == omarchy-plugin-update ]]; }
REMOTE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb CONTAINS=1
git() {
  case $3 in
    rev-parse) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    ls-remote) printf '%s\tHEAD\n' "$REMOTE" ;;
    merge-base) return "$CONTAINS" ;;
  esac
}
[[ $(plugin_latest | jq -r .latest) == "$REMOTE" ]] || { echo 'not ok - a newer release was not found'; exit 1; }
CONTAINS=0
[[ -z $(plugin_latest) ]] || { echo 'not ok - a checkout ahead of the release was offered it'; exit 1; }
REMOTE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
[[ -z $(plugin_latest) ]] || { echo 'not ok - the current release was offered'; exit 1; }
rm -rf "$PANEL/.git"; CONTAINS=1 REMOTE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
[[ -z $(plugin_latest) ]] || { echo 'not ok - a copy Omarchy cannot update was offered an update'; exit 1; }
# the update opens in a terminal, where Omarchy's own update shows the change and asks: never --yes
omarchy-launch-tui() { printf 'tui %s\n' "$*" >>"$UPDATE_ARGS"; }
[[ $(cmd_update plugin) == *'open in a terminal'* ]]
grep -q -- '^tui --app-id=org.omarchy.local-ai-update bash -c .*omarchy-plugin-update "$1".* local-ai sero.local-ai$' "$UPDATE_ARGS"
! grep -q -- '--yes' "$UPDATE_ARGS"
omarchy-launch-tui() { return 1; }
if (cmd_update plugin) >/dev/null 2>&1; then echo 'not ok - a terminal that did not open reported success'; exit 1; fi
echo 'ok - the plugin update is offered for a newer release only and opens Omarchy''s update in a terminal, which asks first'

# Values that land in an agent's config are checked again where they are written: a context that is not a number is
# the default, a vision flag is true or false, and a model name is quoted by jq, however a recipe carried them
mkdir -p "$TMP/ag"; echo key >"$KEY"
EVIL=$'131072\n[mcp_servers.pwn]\ncommand = "sh"\n[model.x]'
argv grok /bin/grok http://172.30.0.5:12434 $'m"\n[x]' "$EVIL" 'true; rm -rf' "$TMP/ag" >/dev/null
! grep -q 'mcp_servers\|^\[x\]' "$TMP/ag/config.toml" && grep -qx 'context_window = 32768' "$TMP/ag/config.toml" ||
  { echo 'not ok - an agent config took a value it should not'; cat "$TMP/ag/config.toml"; exit 1; }
[[ $(argv codex /bin/codex http://172.30.0.5:12434 'a"b' 4096 false "$TMP/ag" | tr '\0' '\n' | grep '^model=') == 'model="a\"b"' ]] ||
  { echo 'not ok - codex model name is not quoted'; exit 1; }
echo 'ok - agent configs take only a number for the context, a boolean for vision and a quoted model name'
