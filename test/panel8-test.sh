#!/bin/bash
# The real Panel8.qml offscreen with a stub shell and a stub backend: it polls, starts on connect, and every page an
# action leads to draws without a QML error; a verb runs the backend with the right arguments.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v quickshell >/dev/null; then
  echo 'ok - Local AI 8 panel # SKIP quickshell is not installed'
  exit 0
fi
TMP=$(mktemp -d "${TMPDIR:-$HOME}/panel8.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT" "$TMP" <<'PY'
import pathlib, shutil, json, sys
src, p = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for n in ['Panel8.qml', 'Page8.qml', 'View8.js', 'Model.js', 'FullScreen.qml']: shutil.copy(src / n, p / n)
snap = json.load(open(src / 'test/fixtures/snapshot-2xb70.json'))
files = {
'Commons/qmldir': 'module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Util 1.0 Util.qml\n',
'Commons/Style.qml': 'pragma Singleton\nimport QtQuick\nQtObject { property var font: ({family:"monospace"}); function space(n) { return n } }\n',
'Commons/Color.qml': 'pragma Singleton\nimport QtQuick\nQtObject { property color foreground: "#dddddd"; property color urgent: "#ff5555"; property var popups: ({background:Qt.rgba(0.086,0.086,0.086,1)}) }\n',
'Commons/Util.qml': 'pragma Singleton\nimport QtQuick\nQtObject { function alpha(c,a) { return Qt.rgba(c.r,c.g,c.b,a) } }\n',
'Ui/qmldir': 'module qs.Ui\nPanel 1.0 Panel.qml\nKeyboardPanel 1.0 KeyboardPanel.qml\nBarIconButton 1.0 BarIconButton.qml\n',
'Ui/Panel.qml': 'import QtQuick\nItem { property string moduleName; property string ipcTarget; property var bar:null; property bool opened:false\nfunction open(){opened=true} function close(){opened=false} function toggle(){opened=!opened} }\n',
'Ui/KeyboardPanel.qml': 'import QtQuick\nItem { property var anchorItem; property var owner; property var bar; property bool open; property var focusTarget; property int padding\nproperty int contentWidth; property int contentHeight; width:contentWidth; height:contentHeight\nproperty var screen: null\nfunction fittedContentWidth(w){return w} function fittedContentHeight(h){return h} }\n',
'Ui/BarIconButton.qml': 'import QtQuick\nItem { property var bar; property string tooltipText; property Component iconComponent; signal pressed(); implicitWidth:24; implicitHeight:24 }\n',
'bin/omarchy-local-ai': '#!/bin/bash\nd="${BASH_SOURCE[0]%/bin/*}"\necho "$*" >> "$d/calls"\nif [[ $1 == snapshot ]]; then cat "$d/snapshot.json"; fi\n',
'snapshot.json': json.dumps(snap),
'shell.qml': '''import QtQuick
import Quickshell
ShellRoot {
  id: runner
  property int at: 0
  property bool failed: false
  property var steps: [["", "connect"], ["page|main", "main"], ["page|tree", "tree"], ["node|intel-arc-pro-b70-32gb", "tree"],
    ["model|qwen38-27b-exl3-4bpw-arcb70-vllm-exl3xpu-tp1|intel-xpu:0", "model"], ["page|settings", "settings"],
    ["more|intel-arc-pro-b70-32gb/intel-xpu:0", "settings"], ["run|qwen38-27b-exl3-4bpw-arcb70-vllm-exl3xpu-tp1|intel-xpu:0", "main"]]
  FloatingWindow {
    implicitWidth: 400; implicitHeight: 700; color: "#101010"
    Loader { id: ld; source: "Panel8.qml"; onLoaded: { item.open(); step.start() } }
  }
  function find(o, n) { if (o.objectName === n) return o; var c = o.children || []; for (var i = 0; i < c.length; i++) { var r = find(c[i], n); if (r) return r } return null }
  Timer {
    id: step; interval: 400
    onTriggered: {
      var p = ld.item, s = runner.steps[runner.at]
      if (!p.snap.gpus) { step.start(); return }
      if (s[0]) p.activate(s[0])
      check.start()
    }
  }
  Timer {
    id: check; interval: 400
    onTriggered: {
      var p = ld.item, s = runner.steps[runner.at]
      var got = p.ui.page
      var page = runner.find(p, "local-ai-8-panel")
      if (got !== s[1] || !page) { console.log("FAIL step " + runner.at + " " + s[0] + ": page " + got); runner.failed = true }
      else console.log("PASS " + (s[0] || "start") + " -> " + got)
      runner.at++
      if (runner.at === runner.steps.length) Qt.exit(runner.failed ? 1 : 0); else step.start()
    }
  }
}
'''}
for n, d in files.items():
    f = p / n; f.parent.mkdir(parents=True, exist_ok=True); f.write_text(d)
(p / 'bin/omarchy-local-ai').chmod(0o755)
PY
mkdir -p "$TMP/runtime" "$TMP/home"; chmod 700 "$TMP/runtime"
status=0
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$TMP/runtime" HOME="$TMP/home" \
  timeout --kill-after=2 40 quickshell -p "$TMP" >"$TMP/log" 2>&1 || status=$?
if ((status != 0)) || grep -Eq 'FAIL|ReferenceError|TypeError|Unable to assign|Binding loop|is not a type|Cannot assign|\.qml:[0-9]+' "$TMP/log" ||
  [[ $(grep -c '^.*PASS ' "$TMP/log") != 8 ]] || ! grep -q '^run qwen38-27b-exl3-4bpw-arcb70-vllm-exl3xpu-tp1 intel-xpu:0$' "$TMP/calls"; then
  cat "$TMP/log"; echo "--- backend calls"; cat "$TMP/calls" 2>/dev/null
  echo 'not ok - Local AI 8 panel' >&2
  exit 1
fi
echo 'ok - Local AI 8 panel starts on connect, every action leads to its page, and Load runs the backend'
