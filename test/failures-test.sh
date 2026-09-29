#!/bin/bash
# Failure contracts, using only a temporary home and function shims.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE/deploy/test" "$MODELS"
export XDG_RUNTIME_DIR=$TMP/run
printf '{"id":"test","port":12434,"keys":[],"agent":"pi","folder":"%s"}\n' "$TMP" >"$STATE/deploy/test/config.json"
echo '{"state":"ready","pid":0}' >"$STATE/deploy/test/status.json"
failed=0
check() {
  local name=$1 expected=$2 rc
  shift 2
  set +e
  (set -e; "$@") >"$TMP/out" 2>&1
  rc=$?
  set -e
  if [[ $rc == "$expected" ]]; then echo "ok - $name"; else
    echo "not ok - $name (exit $rc, expected $expected)"; cat "$TMP/out"; failed=$((failed + 1))
  fi
}
# Docker removal fails while inspect succeeds. Losing the deployment would make the running engine invisible.
docker() { case $1 in inspect) echo "1|$(id -u)";; rm) return 1;; esac; }
check 'stop reports a failed container removal' 1 cmd_stop test
[[ -f $STATE/deploy/test/config.json ]] || { echo 'not ok - stop discarded a live deployment'; failed=$((failed + 1)); }
mkdir -p "$STATE/deploy/test"
echo '{"id":"test","port":12434}' >"$STATE/deploy/test/config.json"
echo '{"state":"starting"}' >"$STATE/deploy/test/status.json"
serve() { echo 'serve was called' >"$TMP/served"; }
check 'share refuses a model that is not ready' 1 cmd_share test
[[ ! -f $TMP/served ]] || { echo 'not ok - shared a model before readiness'; failed=$((failed + 1)); }
check 'share rejects unknown mode' 1 cmd_share test nonsense
# Tailscale failure cannot trap a model in the running state.
echo '{"id":"test","port":12434,"shared":true}' >"$STATE/deploy/test/config.json"
echo '{"state":"ready"}' >"$STATE/deploy/test/status.json"
serve() { return 1; }
tailscale() { echo '{"OperatorUser":"another-account"}'; }
# timeout normally execs a binary; this fixture invokes the shell function instead.
timeout() { shift; "$@"; }
check 'share reports that another account manages Tailscale' 1 cmd_share test
grep -q 'another account.*ask that account' "$TMP/out" || { echo 'not ok - wrong operator advice'; failed=$((failed + 1)); }
docker() { case $1 in inspect) echo "1|$(id -u)";; rm) :;; esac; }
check 'a shared model can stop when unsharing fails' 0 cmd_stop test
[[ ! -d $STATE/deploy/test ]] && grep -q 'could not unshare' "$LOG" || { echo 'not ok - unshare failure trapped the model'; failed=$((failed + 1)); }
unset -f timeout
mkdir -p "$STATE/deploy/test"
echo '{"id":"test","port":12434}' >"$STATE/deploy/test/config.json"
# A remembered worker PID can belong to another process after reboot.
echo '{"state":"starting","pid":0}' >"$STATE/deploy/test/status.json"
docker() { :; }
kill() { echo called >"$TMP/killed"; }
pgrep() { return 1; }
check 'a stale worker PID can be dismissed' 0 cmd_stop test
[[ ! -f $TMP/killed ]] || { echo 'not ok - stop signalled an unrelated process group'; failed=$((failed + 1)); }
mkdir -p "$STATE/deploy/test"
echo '{"id":"test","port":12434}' >"$STATE/deploy/test/config.json"
# An empty Hub listing used to be sealed as a verified download.
tree() { :; }
w='{"repository":"test/model","revision":"0000000000000000000000000000000000000000","layout":"dir","mountPath":"/models"}'
check 'empty Hub listing is not a verified model' 1 fetch test "$w"
[[ ! -e $MODELS/test--model@000000000000/.verified ]] || { echo 'not ok - empty download marked verified'; failed=$((failed + 1)); }
rm -f "$STATE/deploy/test/cancel"
# A failure without die() (disk/jq/launcher failures) still needs a useful visible reason.
recipe() { echo '{"name":"Test","weights":[{}]}'; }
fetch() { return 1; }
notify() { :; }
check 'worker failure exits nonzero' 1 worker_run test nvidia:0
if [[ -z $(jq -r '.error // ""' "$STATE/deploy/test/status.json") ]]; then
  echo 'not ok - unexpected worker failure has no reason'; failed=$((failed + 1))
else echo 'ok - unexpected worker failure has a visible reason'; fi
# Launch failures must get back to the panel rather than vanish in a detached process.
echo '{"state":"ready"}' >"$STATE/deploy/test/status.json"
printf '{"id":"test","port":12434,"agent":"pi","folder":"%s"}\n' "$TMP" >"$STATE/deploy/test/config.json"
bin() { echo pi; }
argv() { printf 'pi\0'; }
omarchy-launch-tui() { return 1; }
check 'open reports a terminal launch failure' 1 cmd_open test
check 'set rejects a missing folder without exposing its path' 1 cmd_set folder "$TMP/private/missing"
grep -qx 'local-ai: that folder does not exist' "$TMP/out" || { echo 'not ok - missing-folder prompt contains a path'; failed=$((failed + 1)); }
# Purging must not claim success when it could not enumerate the daemon's containers.
docker() { return 1; }
check 'purge refuses an unavailable daemon' 1 phase_purge
# Bounds are tested through the actual Docker wrapper, with timeout recording its argv.
eval "$(sed -n '/^docker() {/p' "${BACKEND:-$ROOT/bin/omarchy-local-ai}")"
timeout() { printf '%s\n' "$*"; }
[[ $(docker inspect test) == '--kill-after=5 30 docker inspect test' && $(docker pull test) == '--kill-after=5 1800 docker pull test' ]] || {
  echo 'not ok - Docker operations lack their time bounds'; failed=$((failed + 1));
}
# Locks fail visibly instead of waiting without a bound.
flock() { [[ $1 == -w && $2 == 10 ]] || return 99; return 1; }
export CATALOG=$TMP/catalog/recipes.json
check 'registry lock contention fails visibly' 1 cmd_registry
[[ $(cat "$TMP/out") == 'local-ai: a model refresh is already running' ]] || { echo 'not ok - refresh lock has no clear error'; failed=$((failed + 1)); }
((failed == 0))
