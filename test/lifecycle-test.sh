#!/bin/bash
# Legacy container names survive upgrades; new deployments cannot collide across users.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
paths "$TMP/home"
mkdir -p "$STATE/deploy/test"
echo '{}' >"$STATE/deploy/test/config.json"
[[ $(engine test) == omarchy-local-ai-test-engine ]] || exit 1
for owner in 1000 1001; do
  printf '{"containerUid":%s}\n' "$owner" >"$STATE/deploy/test/config.json"
  [[ $(engine test) == "omarchy-local-ai-$owner-test-engine" && $(gateway test) == "omarchy-local-ai-$owner-test-gateway" && $(network test) == "omarchy-local-ai-$owner-test" ]] || exit 1
done
echo 'ok - legacy names persist and two users have different container and network names'
# A card can become allocated after the UI's check or while images download.
RECIPES=$TMP/recipes.json
echo '{"hardware":{"test":{"match":{"backend":"nvidia"}}},"gateway":{"image":"gateway"}}' >"$RECIPES"
recipe() { echo '{"hw":"test","cards":1,"image":"engine"}'; }
policy() { echo ok; }
nvidia_ready() { return 0; }
cdi_stale() { :; }
owned() { :; }
gpus() {
  if [[ -f $TMP/removed ]]; then
    echo '[{"key":"nvidia:0","hw":"test","held":true,"usedMiB":1}]'
  else
    echo '[{"key":"nvidia:0","hw":"test","held":false,"usedMiB":1}]'
  fi
}
remove() { touch "$TMP/removed"; }
docker() {
  case $1 in image) ;; version) echo 29.0.0 ;; *) touch "$TMP/launched"; return 99 ;; esac
}
if (phase_start test 12434 nvidia:0) >"$TMP/output" 2>&1; then exit 1; fi
grep -q 'nvidia:0 is in use by another program' "$TMP/output"
[[ ! -f $TMP/launched ]]
echo 'ok - launch rechecks allocations after downloads and before creating containers'

# Preparation may release allocation while its labelled container reserves a GPU.
rm "$TMP/removed"
gpus() {
  if [[ -f $TMP/prepared ]]; then
    echo '[{"key":"nvidia:0","hw":"test","held":true,"usedMiB":1}]'
  else echo '[{"key":"nvidia:0","hw":"test","held":false,"usedMiB":1}]'; fi
}
remove() { rm -rf "$(rundir "$1")"; }
prepare_model() { touch "$TMP/prepared"; flock -u 8; }
launch_options() { :; }
docker() {
  case $1 in
    image) return 0 ;;
    version) echo 29.0.0 ;;
    info) echo '{}' ;;
    run) touch "$TMP/launched"; return 99 ;;
    *) return 0 ;;
  esac
}
if (phase_start test 12434 nvidia:0) >"$TMP/output" 2>&1; then exit 1; fi
grep -q 'nvidia:0 is in use by another program' "$TMP/output"
[[ ! -f $TMP/launched && ! -d $(rundir test) ]]
echo 'ok - launch reacquires allocation after preparation, refuses a claimed card and cleans transient assets'

# A model an older version started keeps running; its engine moves off the host-reachable bridge, once.
ours() { return 0; }
docker() {
  printf '%s\n' "$*" >>"$TMP/privatize.log"
  case $1 in
    version) echo "${DOCKER_VERSION:-29.0.0}" ;;
    inspect) if [[ ${@: -1} == *-engine && ! -f $TMP/moved ]]; then echo "$(network test) "; else echo "bridge "; fi ;;
    network) if [[ $2 == inspect ]]; then echo 'true false isolated'; elif [[ $2 == disconnect ]]; then touch "$TMP/moved"; fi ;;
  esac
}
rm -f "$STATE/deploy/test/private"
DOCKER_VERSION=27.5.1 privatize
[[ ! -f $STATE/deploy/test/private ]] && ! grep -q '^network connect' "$TMP/privatize.log" &&
  grep -q 'could not move its engine to a private network (Docker 28 or newer is needed' "$LOG"
[[ -f $STATE/deploy/test/private-failed ]]
: >"$TMP/privatize.log"
DOCKER_VERSION=27.5.1 privatize
! grep -q '^version' "$TMP/privatize.log"
rm "$STATE/deploy/test/private-failed"
privatize
n=$(network test)
diff <(grep -E '^network (create|connect|disconnect)' "$TMP/privatize.log") - <<LOG
network create --internal --ipv6=false -o com.docker.network.bridge.gateway_mode_ipv4=isolated --label io.omarchy.local-ai=1 --label io.omarchy.local-ai.uid=$(id -u) $n-private
network connect --alias engine $n-private $n-engine
network connect $n-private $n-gateway
network disconnect $n $n-engine
LOG
[[ -f $STATE/deploy/test/private ]]
: >"$TMP/privatize.log"
privatize
! grep -q '^network' "$TMP/privatize.log"
rm "$STATE/deploy/test/private"
privatize
[[ -f $STATE/deploy/test/private ]] && ! grep -q '^network' "$TMP/privatize.log"
echo 'ok - a running engine an older version started moves to its private network once; on an old Docker the log says so once'
