#!/bin/bash
# Every state the machine can be in, judged by lib/access.sh alone: a login older than setup, Docker down, no NVIDIA
# runtime, a failed setup. Each state has a panel page that either offers Set up Local AI or clears by itself, and a
# start refuses in the words of its state. Docker, the group database and newgrp are shims; no daemon runs.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf '%s\n' "${2:-}" >&2; printf 'not ok - %s\n' "$1" >&2; exit 1; }
# the socket cases need a permission root does not have
[[ $EUID != 0 ]] || { echo 'skip - readiness cases need a non-root user'; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REAL_HOME=$HOME # a version manager's node shim needs the real one
export HOME=$TMP/home XDG_RUNTIME_DIR=$TMP/run SHIM=$TMP/shim OMARCHY_DOCKER_SOCKET=$TMP/docker.sock
STATE=$HOME/.local/state/omarchy/local-ai
mkdir -p "$HOME" "$SHIM" "$TMP/bin" "$TMP/plugin/bin" "$TMP/plugin/lib"
cp "$ROOT/bin/omarchy-local-ai" "$TMP/plugin/bin/"
cp "$ROOT/lib/access.sh" "$TMP/plugin/lib/"
cp "$ROOT/manifest.json" "$ROOT/recipes.json" "$TMP/plugin/"
CLI=$TMP/plugin/bin/omarchy-local-ai
NODE=$(command -v node || true) # before PATH narrows to the shims
shim() { printf '#!/bin/bash\n%s\n' "$2" >"$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

# SUDO_NEEDED: Sudoless Docker is off (exit 0 is Omarchy's answer to --configured)
shim omarchy-sudo-docker '[[ ${SUDO_NEEDED:-0} == 1 ]]'
shim omarchy-hw-nvidia '[[ ${NVIDIA:-0} == 1 ]]'
# DOCKER_DOWN: the daemon does not answer; RUNTIMES: what `docker info` lists
shim docker '[[ $1 == info && ${DOCKER_DOWN:-0} == 0 ]] || exit 1
[[ -n ${RUNTIMES:-} ]] && echo "$RUNTIMES" || echo "{\"runc\":{}}"'
# NOT_IN_GROUP: /etc/group does not list the account; PRIMARY_GID: the account's own group
shim getent 'if [[ $1 == group ]]; then echo "docker:x:998:$([[ -n ${NOT_IN_GROUP:-} ]] && echo nobody || id -un)"
else echo "$2:x:1000:${PRIMARY_GID:-1000}::/home/$2:/bin/bash"; fi'
# newgrp runs the command it is handed; GRANT: the group makes the socket writable, as a fresh login would
shim newgrp 'echo called >>"$SHIM/newgrp.log"; [[ -z ${GRANT:-} ]] || chmod 600 "$OMARCHY_DOCKER_SOCKET"; exec "$SHELL"'
export PATH=$TMP/bin:/usr/bin:/bin

sock_open() { rm -f "$OMARCHY_DOCKER_SOCKET"; : >"$OMARCHY_DOCKER_SOCKET"; }
sock_shut() { sock_open; chmod 000 "$OMARCHY_DOCKER_SOCKET"; }
newgrp_calls() { wc -l <"$SHIM/newgrp.log" 2>/dev/null || echo 0; }
# verdict [VAR=value...]: what `readiness` prints, "<state> <message>", in a fresh login-shaped run
verdict() { : >"$SHIM/newgrp.log"; env "$@" "$CLI" readiness | tr '\t' ' ' | sed 's/ *$//'; }
# check <name> <state> [message] -- [VAR=value...]
check() {
  local name=$1 want=$2 msg="" got
  shift 2
  [[ $1 == -- ]] || { msg=$1; shift; }
  shift
  got=$(verdict "$@")
  [[ $got == "$want${msg:+ $msg}" ]] || fail "$name" "want '$want${msg:+ $msg}', got '$got'"
  pass "$name"
}

sock_open
check 'a set up machine is ready' ready --
[[ $(newgrp_calls) == 0 ]] || fail 'ready needs no group' "$(cat "$SHIM/newgrp.log")"

check 'Sudoless Docker off needs setup' needs-setup -- SUDO_NEEDED=1
# a PATH with no Omarchy in it: on a real Omarchy the helper is installed system-wide, so removing the shim is not enough
mkdir "$TMP/bare"
ln -s "$(command -v readlink)" "$(command -v mkdir)" "$TMP/bare/"
check 'no Sudoless Docker helper is unsupported' unsupported 'This Omarchy has no Sudoless Docker helper; update Omarchy' -- "PATH=$TMP/bare"

check 'a daemon that does not answer is docker-down' docker-down 'Docker is not answering' -- DOCKER_DOWN=1
rm -f "$OMARCHY_DOCKER_SOCKET"
check 'no socket is docker-down: Docker is not running' docker-down 'Docker is not running' --
[[ $(newgrp_calls) == 0 ]] || fail 'a group cannot fix a missing socket' "$(cat "$SHIM/newgrp.log")"

# a login that began before setup: the group is in /etc/group and not in this process
sock_shut
check 'a login older than setup is ready once newgrp applies the group' ready -- GRANT=1
[[ $(newgrp_calls) == 1 ]] || fail 'the group is applied once' "$(newgrp_calls)"
sock_shut
check 'newgrp that grants nothing ends in docker-down, and is tried once' docker-down \
  "This login cannot use Docker's socket, though the account is in the docker group" --
[[ $(newgrp_calls) == 1 ]] || fail 'no loop when the group does not help' "$(newgrp_calls)"
sock_shut
check 'a re-executed process does not try again' docker-down \
  "This login cannot use Docker's socket, though the account is in the docker group" -- LOCAL_AI_REEXEC=1 GRANT=1
[[ $(newgrp_calls) == 0 ]] || fail 'the loop guard' "$(newgrp_calls)"
sock_shut
check 'an account whose primary group is docker is in the group' ready -- NOT_IN_GROUP=1 PRIMARY_GID=998 GRANT=1
sock_shut
check 'an account outside the docker group needs setup, and no group is tried' needs-setup -- NOT_IN_GROUP=1 GRANT=1
[[ $(newgrp_calls) == 0 ]] || fail 'newgrp for an account outside the group' "$(newgrp_calls)"
mv "$TMP/bin/newgrp" "$TMP/newgrp.off"
sock_shut
check 'without newgrp a stale login is docker-down, not a failure' docker-down \
  "This login cannot use Docker's socket, though the account is in the docker group" --
mv "$TMP/newgrp.off" "$TMP/bin/newgrp"

sock_open
NVIDIA_RUNTIME='{"nvidia":{"path":"nvidia-container-runtime"},"runc":{}}'
check 'an NVIDIA card without the runtime needs setup' needs-setup -- NVIDIA=1
check 'an NVIDIA card with the runtime is ready' ready -- NVIDIA=1 "RUNTIMES=$NVIDIA_RUNTIME"
check 'the toolkit registering only nvidia-cdi counts' ready -- NVIDIA=1 'RUNTIMES={"nvidia-cdi":{},"runc":{}}'
check 'a machine without an NVIDIA card needs no runtime' ready -- NVIDIA=0

mkdir -p "$STATE"
echo 'Setup did not finish; choose Set up Local AI to try again.' >"$STATE/setup-error"
check 'a setup that did not finish needs setup' needs-setup --
check 'and that wins over a Docker that is down, so the button is there' needs-setup -- DOCKER_DOWN=1
rm "$STATE/setup-error"

# a start refuses in the words of the state, and asks for nothing
refusal() { env "$@" "$CLI" run no-such-recipe nvidia:0 2>&1 >/dev/null || true; }
[[ $(refusal SUDO_NEEDED=1) == *'Local AI is not set up yet: choose Set up Local AI'* ]] || fail 'run refusal: needs-setup' "$(refusal SUDO_NEEDED=1)"
[[ $(refusal DOCKER_DOWN=1) == *'Docker is not answering'* ]] || fail 'run refusal: docker-down' "$(refusal DOCKER_DOWN=1)"
sock_shut
[[ $(refusal) == *"This login cannot use Docker's socket"* ]] || fail 'run refusal: socket' "$(refusal)"
! refusal | grep -qi 'log out' || fail 'a start asked for a new login'
sock_open
[[ $(refusal) == *'no recipe no-such-recipe'* ]] || fail 'run past readiness' "$(refusal)"
pass 'a start refuses in the words of its state, and only a ready machine gets past it'

# every state the backend can report has a panel page with a button, or one that says it clears by itself
states=$(bash -c '. "$1"; printf "%s\n" "${READINESS_STATES[@]}"' _ "$ROOT/lib/access.sh")
[[ -n $states ]] || fail 'no readiness states'
[[ -n $NODE ]] || { echo 'skip - the panel pages need node'; exit 0; }
HOME=$REAL_HOME "$NODE" - "$ROOT/Model.js" "$states" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const c = {module: {exports: {}}}; vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), c);
const states = process.argv[3].split('\n').filter(Boolean).concat('a-state-added-later');
for (const state of states) {
  const v = c.module.exports.build({gpus: [], kinds: [], readiness: {state}}, {view: 'home'});
  if (state === 'ready') continue;
  const buttons = v.rows.flatMap(r => (r.items || []).map(b => b.action));
  const notes = v.rows.map(r => r.note || '').join(' ');
  assert(buttons.includes('setup') || /again by itself/.test(notes), `${state} is a dead end`);
  assert(!/log out/i.test(notes), `${state} asks for a new login`);
}
console.log('ok - every readiness state offers Set up Local AI or says it clears by itself');
JS
