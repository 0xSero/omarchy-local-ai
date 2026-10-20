#!/bin/bash
# Render every Local AI 8 page offscreen, in the panel (340 × 560) and full screen (1280 × 800), from a real snapshot
# (two Arc Pro B70s and a CPU) changed into each state: connect, setup needed, the tree, a model (free, downloading,
# loading, running), main (first time, nothing running, one running, several running, one failed) and settings.
# PANEL_ARTIFACTS=<dir> keeps the pictures and the log.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v quickshell >/dev/null; then
  echo 'ok - Local AI 8 pages render # SKIP quickshell is not installed'
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$ROOT/Page8.qml" "$ROOT/View8.js" "$TMP/"
python3 - "$ROOT/test/fixtures/snapshot-2xb70.json" "$TMP/cases.js" <<'PY'
import json, sys, copy
base = json.load(open(sys.argv[1]))
b70 = base['kinds'][0]
qwen = b70['models'][0]
small = next(m for m in b70['models'] if m['name'] == 'Qwen3.5-9B')
welp = next(m for m in b70['models'] if m['name'].startswith('Welp'))
line = [0, 900, 2100, 2600, 5200, 7400, 7900, 11800, 15200, 16900, 21000, 24800, 25100, 29900, 33800, 38100, 39000, 44500, 48100, 52000]
def dep(r, keys, state='ready', **kw):
    d = dict(r, keys=keys, state=state, agent='claude', folder='/home/user/Work', port=12434, startedAt='2026-10-20T08:00:00Z',
             session={'all': {'decode': 41, 'prefill': 1830, 'ttft': 640, 'tokens': line[-1], 'line': line}}, address='172.19.0.3:12434')
    d.update(kw)
    return d
def snap(**kw):
    s = copy.deepcopy(base)
    s.update(kw)
    return s
def owned(*ids):
    s = copy.deepcopy(base)
    for kd in s['kinds']:
        for m in kd['models']:
            if m['id'] in ids: m['downloaded'] = True
    return s
both_free = lambda s: [kd.update(free=list(kd['keys']), taken=[]) for kd in s['kinds']] and s
first = snap(life={'days': [], 'today': 0, 'requests': 0}, total=0)
idle = owned(small['id'], welp['id'], qwen['id'])
one = snap(deployments=[dep(small, ['intel-xpu:0'])])
one['kinds'][0]['free'] = []
multi = snap(deployments=[dep(small, ['intel-xpu:0']), dep(welp, ['intel-xpu:1'], 'load', detail='loading weights', percent=41, session={})])
multi['kinds'][0]['free'] = []
failed = snap(deployments=[dep(small, ['intel-xpu:0'], 'error', error='the engine stopped: out of memory on the card')])
downloading = snap(downloads=[{'id': qwen['id'], 'state': 'download', 'percent': 62, 'detail': '9.8 / 15.7 GB'}])
loading = snap(deployments=[dep(qwen, ['intel-xpu:0'], 'load', detail='loading weights', percent=41, session={})])
setup = snap(readiness={'state': 'needs-setup', 'message': ''})
settings = snap(pluginUpdate=True, reporting='on', deployments=[dep(small, ['intel-xpu:0'], shared='https://machine.example.ts.net:12434')])
cases = [
  ('01-connect', base, {'page': 'connect'}, 200),
  ('01-connect-drawing', base, {'page': 'connect'}, 20),
  ('01-connect-setup', setup, {'page': 'connect'}, 200),
  ('02-tree', base, {'page': 'tree'}, 0),
  ('02-tree-more', base, {'page': 'tree', 'more': {'intel-arc-pro-b70-32gb/intel-xpu:0': True}, 'closed': {'intel-arc-pro-b70-32gb/intel-xpu:1': False}}, 0),
  ('03-model', base, {'page': 'model', 'id': qwen['id'], 'keys': 'intel-xpu:0'}, 0),
  ('03-model-downloading', downloading, {'page': 'model', 'id': qwen['id'], 'keys': 'intel-xpu:0'}, 7),
  ('03-model-loading', loading, {'page': 'model', 'id': qwen['id'], 'keys': 'intel-xpu:0'}, 7),
  ('03-model-running', one, {'page': 'model', 'id': small['id'], 'keys': 'intel-xpu:0'}, 7),
  ('04-main-first-time', first, {'page': 'main'}, 0),
  ('04-main-nothing-running', idle, {'page': 'main'}, 0),
  ('04-main-running', one, {'page': 'main'}, 9),
  ('04-main-several-running', multi, {'page': 'main'}, 9),
  ('04-main-failed', failed, {'page': 'main'}, 0),
  ('04-main-problem', idle, {'page': 'main', 'problem': 'could not reach Docker; is it running?'}, 0),
  ('05-settings', settings, {'page': 'settings'}, 0),
]
out = []
for name, s, ui, tick in cases:
    for size in ('panel', 'full'):
        out.append({'name': name + '-' + size, 'snap': s, 'ui': dict(ui, wide=size == 'full', now=1792483200000), 'tick': tick, 'wide': size == 'full'})
open(sys.argv[2], 'w').write('var CASES = ' + json.dumps(out) + '\n')
open(sys.argv[2] + '.count', 'w').write(str(len(out)))
print(len(out), 'cases')
PY
cat > "$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "View8.js" as View8
import "cases.js" as Cases
ShellRoot {
  id: runner
  property int at: 0
  property bool failed: false
  readonly property var c: Cases.CASES[Math.min(at, Cases.CASES.length - 1)]
  FloatingWindow {
    implicitWidth: 1280; implicitHeight: 800; color: "#101010"
    Page8 {
      id: page
      objectName: "page"
      width: runner.c.wide ? 1280 : 340
      height: runner.c.wide ? 800 : 560
      wide: runner.c.wide
      tick: runner.c.tick
      mono: "JetBrainsMono Nerd Font"
      bg: "#161616"; surface: "#1c1c1c"; ink: "#ededed"; valueTone: "#c4c4c4"; labelTone: "#8c8c8c"; ruleTone: "#2e2e2e"; alertTone: "#f2a0a0"
      view: {
        try { return View8.build(runner.c.snap, runner.c.ui) }
        catch (e) { console.log("FAIL build " + runner.c.name + ": " + e.message); runner.failed = true; return { cards: [] } }
      }
      onActivated: function(a) {}
    }
  }
  Timer {
    id: shot; interval: 250; running: true
    onTriggered: page.grabToImage(function(img) {
      var c = runner.c
      img.saveToFile(Quickshell.env("OUT") + "/" + c.name + ".png")
      console.log("PASS rendered " + c.name + " " + page.width + "x" + page.height)
      runner.at++
      if (runner.at === Cases.CASES.length) Qt.exit(runner.failed ? 1 : 0); else shot.start()
    })
  }
}
QML
mkdir -p "$TMP/runtime" "$TMP/output" "$TMP/home"
chmod 700 "$TMP/runtime"
status=0
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$TMP/runtime" HOME="$TMP/home" \
  OUT="$TMP/output" timeout --kill-after=2 60 quickshell -p "$TMP" >"$TMP/log" 2>&1 || status=$?
if [[ -n ${PANEL_ARTIFACTS:-} ]]; then
  mkdir -p "$PANEL_ARTIFACTS"
  cp "$TMP/output/"*.png "$TMP/log" "$PANEL_ARTIFACTS/" 2>/dev/null || true
fi
want=$(cat "$TMP/cases.js.count")
got=$(grep -c 'PASS rendered' "$TMP/log" || true)
if ((status != 0)) || grep -Eq 'FAIL|ReferenceError|TypeError|Unable to assign|Binding loop|is not a type|Cannot assign|qrc:|\.qml:[0-9]+' "$TMP/log" || [[ $got != "$want" ]]; then
  cat "$TMP/log"
  echo "not ok - Local AI 8 pages: $got of $want rendered (exit $status)" >&2
  exit 1
fi
echo "ok - Local AI 8 renders all $want pages (panel and full screen) offscreen without a QML error"
