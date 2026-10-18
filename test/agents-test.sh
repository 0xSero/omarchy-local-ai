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
# the update opens in a terminal that runs this script's own update step
omarchy-launch-tui() { printf 'tui %s\n' "$*" >>"$UPDATE_ARGS"; }
[[ $(cmd_update plugin) == *'open in a terminal'* ]]
grep -qx -- "tui --app-id=org.omarchy.local-ai-update $TARGET __update sero.local-ai" "$UPDATE_ARGS"
omarchy-launch-tui() { return 1; }
if (cmd_update plugin) >/dev/null 2>&1; then echo 'not ok - a terminal that did not open reported success'; exit 1; fi
# that step shows the version and the release notes, not Omarchy's diff, asks, and only then runs Omarchy's update
# with --yes (its validation and rollback stay); a no leaves the plugin alone
printf '{"id":"sero.local-ai","version":"1.0.0"}\n' >"$PANEL/manifest.json"
NOTES=$'# Changelog\n\n## [Unreleased]\n\n## [1.1.0] - 2026-10-18\n\n### Added\n- A new card (registry #1). Long detail that stays out.\n\n## [1.0.0] - 2026-10-01\n\n### Added\n- The old entry.\n'
git() {
  case $3 in
    fetch) return 0 ;;
    rev-parse) [[ $4 == HEAD ]] && echo aaaa || echo bbbb ;;
    show) [[ $4 == FETCH_HEAD:manifest.json ]] && echo '{"version":"1.1.0"}' || printf '%s' "$NOTES" ;;
  esac
}
omarchy-cmd-present() { [[ $1 == gum ]]; }
sleep() { :; }; clear() { :; }
: >"$UPDATE_ARGS"
omarchy-plugin-update() { printf 'opu %s\n' "$*" >>"$UPDATE_ARGS"; }
gum() { return 0; }
OUT=$(update_run sero.local-ai)
[[ $OUT == *'Local AI 1.0.0 → 1.1.0'* && $OUT == *'A new card (registry #1)'* && $OUT == *'now 1.1.0'* ]] || { echo "not ok - update summary: $OUT"; exit 1; }
[[ $OUT != *'stays out'* && $OUT != *'old entry'* ]] || { echo "not ok - update summary showed too much: $OUT"; exit 1; }
grep -qx 'opu sero.local-ai --yes' "$UPDATE_ARGS" || { echo 'not ok - the confirmed update did not run'; exit 1; }
: >"$UPDATE_ARGS"; gum() { return 1; }
[[ $(update_run sero.local-ai) == *'Not updated.'* && ! -s $UPDATE_ARGS ]] || { echo 'not ok - a declined update ran'; exit 1; }
unset -f sleep clear gum omarchy-plugin-update
echo 'ok - the plugin update is offered for a newer release only, shows the version and notes, and asks before Omarchy updates it'

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
