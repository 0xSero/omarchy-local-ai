#!/bin/bash
# Setup, with sudo and the Omarchy helpers shimmed: the NVIDIA runtime when an NVIDIA card needs it, Omarchy's
# Sudoless Docker, the tailnet operator, and the earlier versions' polkit files removed. Run again, it changes nothing.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/bin" "$TMP/bin" "$TMP/home" "$TMP/etc"
cp "$ROOT/bin/omarchy-install-ai-local" "$TMP/plugin/bin/"
export HOME=$TMP/home SETUP_TEST=$TMP
# the earlier polkit files live in a test folder
sed -i -e "s|/etc/polkit-1/actions/|$TMP/etc/|" -e "s|/etc/polkit-1/rules.d/|$TMP/etc/|" "$TMP/plugin/bin/omarchy-install-ai-local"
cat >"$TMP/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SETUP_TEST/calls"
case $1 in
-v | systemctl | tailscale) exit 0 ;;
docker)
  if [[ $2 == ps ]]; then [[ ${BUSY:-0} == 0 ]] || echo busy
  elif [[ ${READY:-0} == 1 || -f $SETUP_TEST/configured ]]; then echo '{"nvidia":{}}'
  else echo '{}'; fi ;;
nvidia-ctk) touch "$SETUP_TEST/configured" ;;
test | rm) "$@" ;;
*) exit 1 ;;
esac
SH
cat >"$TMP/bin/omarchy-hw-nvidia" <<'SH'
#!/bin/bash
[[ ${NVIDIA:-1} == 1 ]]
SH
cat >"$TMP/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
[[ ${FAIL_INSTALL:-0} == 0 ]]
SH
# Omarchy's Sudoless Docker: yes adds the account to the group, DECLINE answers no
cat >"$TMP/bin/omarchy-setup-security-sudoless-docker" <<'SH'
#!/bin/bash
echo "sudoless ${OMARCHY_DEFER_REBOOT:-now}" >>"$SETUP_TEST/calls"
[[ -n ${DECLINE:-} ]] || touch "$SETUP_TEST/group"
SH
cat >"$TMP/bin/omarchy-sudo-docker" <<'SH'
#!/bin/bash
[[ ! -f $SETUP_TEST/group ]]
SH
printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/tailscale"
chmod +x "$TMP/bin/"*
export PATH=$TMP/bin:$PATH
setup() { bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1; }

if BUSY=1 setup; then exit 1; fi
[[ ! -e $TMP/configured && ! -e $TMP/group ]]
echo 'ok - setup refuses to modify Docker while containers are running'
if FAIL_INSTALL=1 setup; then exit 1; fi
[[ ! -e $TMP/group ]]
echo 'ok - failed dependency setup is not marked ready'
if DECLINE=1 setup; then exit 1; fi
grep -q 'needs Sudoless Docker' "$TMP/out"
echo 'ok - declining Sudoless Docker leaves Local AI not set up, and says so'

touch "$TMP/etc/sero.local-ai.u$(id -u).policy" "$TMP/etc/49-sero.local-ai.u$(id -u).rules"
: >"$TMP/calls"
setup
grep -qx 'sudoless 1' "$TMP/calls"
[[ -f $TMP/group ]]
grep -qx "tailscale set --operator=$USER" "$TMP/calls"
[[ -z $(ls "$TMP/etc") ]]
grep -qx 'systemctl reload polkit' "$TMP/calls"
echo 'ok - setup turns on Sudoless Docker without its reboot, makes you the tailnet operator, and removes the old polkit files'

: >"$TMP/calls"
READY=1 BUSY=1 setup
! grep -q 'restart docker' "$TMP/calls"
! grep -q 'reload polkit' "$TMP/calls"
echo 'ok - run again, setup restarts nothing'
node - "$ROOT/Model.js" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const c = {module:{exports:{}}}; vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const v=c.module.exports.build({gpus:[],kinds:[],setupNeeded:true}, {view:'home'});
assert(v.rows.some(r => (r.items||[]).some(b => b.action === 'setup')));
console.log('ok - fresh installs offer setup directly in the panel');
JS
