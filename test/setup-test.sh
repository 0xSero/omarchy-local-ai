#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/plugin/bin" "$TMP/bin" "$TMP/home"
cp "$ROOT/bin/omarchy-install-ai-local" "$TMP/plugin/bin/"
cp "$ROOT/local-ai.policy" "$TMP/plugin/"
export HOME=$TMP/home SETUP_TEST=$TMP
# Only this disposable installer writes to the test policy location.
sed -i "s|POLICY=/etc/polkit-1/actions/sero.local-ai.u\$(id -u).policy|POLICY=$TMP/plugin.policy|" "$TMP/plugin/bin/omarchy-install-ai-local"
cat >"$TMP/bin/sudo" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SETUP_TEST/calls"
case $1 in
-v) exit 0 ;;
docker)
  if [[ $2 == ps ]]; then [[ ${BUSY:-0} == 0 ]] || echo busy
  elif [[ ${READY:-0} == 1 || -f $SETUP_TEST/configured ]]; then echo '{"nvidia":{}}'
  else echo '{}'; fi ;;
nvidia-ctk) touch "$SETUP_TEST/configured" ;;
systemctl) exit 0 ;;
install) shift; /usr/bin/install "$@" ;;
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
chmod +x "$TMP/bin/"*
export PATH=$TMP/bin:$PATH
if BUSY=1 bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1; then exit 1; fi
[[ ! -e $TMP/plugin.policy && ! -e $TMP/configured ]]
echo 'ok - setup refuses to modify Docker while containers are running'
if FAIL_INSTALL=1 bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1; then exit 1; fi
[[ ! -e $TMP/plugin.policy ]]
echo 'ok - failed dependency setup is not marked ready'
bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1
grep -q 'Local AI needs your password to update the model catalog' "$TMP/plugin.policy"
grep -q '__registry' "$TMP/plugin.policy"
echo 'ok - setup installs the custom catalog authorization message'
: >"$TMP/calls"
READY=1 BUSY=1 bash "$TMP/plugin/bin/omarchy-install-ai-local" >"$TMP/out" 2>&1
! grep -q 'restart docker' "$TMP/calls"
echo 'ok - an already configured runtime needs no Docker restart'
node - "$ROOT/Model.js" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const c = {module:{exports:{}}}; vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const v=c.module.exports.build({gpus:[],kinds:[],setupNeeded:true}, {view:'home'});
assert(v.rows.some(r => (r.items||[]).some(b => b.action === 'setup')));
console.log('ok - fresh installs offer setup directly in the panel');
JS
