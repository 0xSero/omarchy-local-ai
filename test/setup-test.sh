#!/bin/bash
# Setup, with the Omarchy helpers shimmed: Omarchy's Sudoless Docker, then on NVIDIA the container toolkit, each run
# with a password prompt that names it. Local AI itself runs nothing as root: a sudo shim fails the test if called.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/bin" "$TMP/plugin/lib" "$TMP/bin" "$TMP/home" "$TMP/etc"
cp "${INSTALLER:-$ROOT/bin/omarchy-install-ai-local}" "$TMP/plugin/bin/omarchy-install-ai-local"
cp "$ROOT/lib/access.sh" "$TMP/plugin/lib/"
export HOME=$TMP/home SETUP_TEST=$TMP
# the earlier polkit files live in a test folder
sed -i -e "s|/etc/polkit-1/actions/|$TMP/etc/|g" -e "s|/etc/polkit-1/rules.d/|$TMP/etc/|g" "$TMP/plugin/bin/omarchy-install-ai-local"
shim() { printf '#!/bin/bash\n%s\n' "$2" >"$1"; chmod +x "$1"; }
shim "$TMP/bin/sudo" 'echo "sudo $*" >>"$SETUP_TEST/calls"; exit 1'
shim "$TMP/bin/omarchy-hw-nvidia" '[[ ${NVIDIA:-1} == 1 ]]'
shim "$TMP/bin/omarchy-pkg-add" 'echo "pkg $* | $SUDO_PROMPT" >>"$SETUP_TEST/calls"; [[ ${FAIL_INSTALL:-0} == 0 ]]'
# Omarchy's Sudoless Docker: yes adds the account to the group, DECLINE answers no
shim "$TMP/bin/omarchy-setup-security-sudoless-docker" 'echo "sudoless ${OMARCHY_DEFER_REBOOT:-now} | $SUDO_PROMPT" >>"$SETUP_TEST/calls"
[[ -n ${DECLINE:-} ]] || touch "$SETUP_TEST/group"'
shim "$TMP/bin/getent" 'if [[ $1 == group ]]; then echo "docker:x:998:$([[ -f $SETUP_TEST/group ]] && id -un)"
else echo "$2:x:1000:1000::/home/$2:/bin/bash"; fi'
# the backend's verdict after setup: READINESS, ready by default
shim "$TMP/plugin/bin/omarchy-local-ai" '[[ $1 == readiness ]] && printf "%s\t%s\n" "${READINESS:-ready}" "${READINESS_MSG:-}"'
shim "$TMP/bin/tailscale" '[[ ${FAIL_PREFS:-0} == 0 ]] || exit 1
jq -nc --arg user "${TEST_OPERATOR-$(id -un)}" "{OperatorUser:\$user}"'
export PATH=$TMP/bin:$PATH
setup() { : >"$TMP/calls"; bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1; }
error=$HOME/.local/state/omarchy/local-ai/setup-error

if DECLINE=1 setup; then exit 1; fi
grep -q 'needs Sudoless Docker' "$TMP/out"
if grep -q '^pkg' "$TMP/calls"; then exit 1; fi
[[ -s $error ]]
echo 'ok - declining Sudoless Docker installs nothing, says so, and leaves a panel error'

setup
grep -qx "sudoless 1 | Password for %u to turn on Sudoless Docker for Local AI: " "$TMP/calls"
grep -qx "pkg nvidia-container-toolkit | Password for %u to install NVIDIA container support for Local AI: " "$TMP/calls"
grep -q 'Local AI is ready' "$TMP/out"
[[ ! -e $error ]]
echo 'ok - setup turns on Sudoless Docker, then installs the NVIDIA toolkit, each prompt naming what it is for'

setup
if grep -q '^sudoless' "$TMP/calls"; then exit 1; fi
echo 'ok - run again, Sudoless Docker is not asked twice'

NVIDIA=0 setup
if grep -q '^pkg' "$TMP/calls"; then exit 1; fi
echo 'ok - a non-NVIDIA machine installs no NVIDIA package'

if FAIL_INSTALL=1 setup; then exit 1; fi
[[ -s $error ]] && ! grep -q 'Local AI is ready' "$TMP/out"
echo 'ok - a failed package install never reports success and leaves a panel error'

if READINESS=needs-setup READINESS_MSG='Docker lists no NVIDIA GPU' setup; then exit 1; fi
grep -q 'Docker lists no NVIDIA GPU' "$TMP/out"
echo 'ok - setup ends with the verdict the panel will show, and fails when it is not ready'

READINESS=docker-down setup
grep -q 'clears this by itself' "$TMP/out"
echo 'ok - Docker not answering after setup is reported, not a failure'

TEST_OPERATOR=another-account setup
grep -q "operator must be $(id -un)" "$TMP/out"
TEST_OPERATOR='' setup
grep -q "it is 'nobody'" "$TMP/out"
FAIL_PREFS=1 setup
if grep -q 'operator' "$TMP/out"; then exit 1; fi
echo 'ok - setup names the Tailscale operator step and never changes the operator'

touch "$TMP/etc/49-sero.local-ai.u$(id -u).rules"
setup
grep -q 'Delete them as root' "$TMP/out"
echo 'ok - leftover polkit files from earlier versions are named'

if grep -q '^sudo' "$TMP/calls"; then exit 1; fi
if grep -qE '(^|[^-])\bsudo\b|systemctl|pkexec' "$ROOT/bin/omarchy-install-ai-local"; then exit 1; fi
echo 'ok - setup itself runs nothing as root'

node - "$ROOT/Model.js" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const c = {module:{exports:{}}}; vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const v=c.module.exports.build({gpus:[],kinds:[],readiness:{state:'needs-setup'}}, {view:'home'});
assert.deepEqual(Array.from(v.rows.flatMap(r => (r.items||[]).map(b => b.action))), ['setup']);
console.log('ok - fresh installs offer setup directly in the panel');
JS
