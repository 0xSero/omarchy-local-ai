#!/bin/bash
# Compile/render the real panel without a display, compositor, session bus or real backend.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v quickshell >/dev/null; then
  echo 'ok - offscreen panel # SKIP quickshell is not installed'
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
python3 - "$ROOT" "$TMP" <<'PY'
# Isolated shell chrome and snapshot; the plugin QML itself is copied unchanged.
import pathlib,shutil,json,sys
p=pathlib.Path(sys.argv[2])
p.mkdir(exist_ok=True)
source=pathlib.Path(sys.argv[1])
for name in ['Panel.qml','Model.js','qwen.svg','hf.svg']: shutil.copy(source/name,p/name)
shutil.copytree(source/"agents",p/"agents")
files={
'Commons/qmldir':'module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Util 1.0 Util.qml\n',
'Commons/Style.qml':'''pragma Singleton
import QtQuick
QtObject { property var font: ({family:"monospace",caption:12,body:14,subtitle:15}); function space(n) { return n } }
''',
'Commons/Color.qml':'''pragma Singleton
import QtQuick
QtObject { property color foreground: "#dddddd"; property color urgent: "#ff5555"; property var popups: ({background:Qt.rgba(0.07,0.07,0.08,1)}) }
''',
'Commons/Util.qml':'''pragma Singleton
import QtQuick
QtObject { function alpha(c,a) { return Qt.rgba(c.r,c.g,c.b,a) } }
''',
'Ui/qmldir':'module qs.Ui\nPanel 1.0 Panel.qml\nKeyboardPanel 1.0 KeyboardPanel.qml\nBarIconButton 1.0 BarIconButton.qml\n',
'Ui/Panel.qml':'''import QtQuick
Item { property string moduleName; property string ipcTarget; property var bar:null; property bool opened:false
function open(){opened=true} function close(){opened=false} function toggle(){opened=!opened} }
''',
'Ui/KeyboardPanel.qml':'''import QtQuick
Item { property var anchorItem; property var owner; property var bar; property bool open; property var focusTarget; property int padding
property int contentWidth; property int contentHeight; width:contentWidth; height:contentHeight
function fittedContentHeight(h){return h} }
''',
'Ui/BarIconButton.qml':'''import QtQuick
Item { property var bar; property string tooltipText; property Component iconComponent; signal pressed(); implicitWidth:24; implicitHeight:24 }
''',
'bin/omarchy-local-ai':'#!/bin/bash\nif [[ $1 == registry ]]; then echo "models up to date · 12345678"; exit 0; fi\ncat "${BASH_SOURCE[0]%/bin/*}/snapshot.json"\n',
'shell.qml':'''import QtQuick
import Quickshell
ShellRoot {
  id: runner
  property int at: 0
  property bool failed: false
  property var modes: ["setup","kind","run","error","crash","stopped","refreshed"]
  FloatingWindow {
    implicitWidth:340; implicitHeight:1000; color:"#121214"
    Loader { id: ld; source:"Panel.qml"; onLoaded: { item.open(); step.start() } }
  }
  function find(o,n) {
    if (o.objectName===n) return o
    var c=o.children||[]
    for(var i=0;i<c.length;i++){var r=find(c[i],n);if(r)return r}
    return null
  }
  Timer {
    id: step; interval:350
    onTriggered: {
      var p=ld.item, mode=runner.modes[runner.at]
      if(!p.snap.gpus){step.start();return}
      p.snap=Object.assign({},p.snap,{readiness:{state:mode==="setup"?"needs-setup":"ready"}})
      if(mode==="crash" || mode==="stopped")p.snap=Object.assign({},p.snap,{deployments:p.snap.deployments.map(function(d){return Object.assign({},d,{state:"error",error:"the engine stopped"})})})
      p.ui={view:mode==="crash"?"home":mode==="setup"?"home":mode==="kind"?"kind":"run",id:"test",problem:mode==="error"?"Could not open the agent terminal; try again.":""}
      if(mode==="refreshed"){p.ui={view:"home"};p.activate("registry")}
      capture.start()
    }
  }
  Timer {
    id: capture; interval:150
    onTriggered: {
      if(runner.modes[runner.at]==="refreshed" && (ld.item.ui.notice!=="models up to date · 12345678" || ld.item.ui.registryBusy)){
        console.log("FAIL registry completion was not shown");runner.failed=true
      }
      var content=runner.find(ld.item,"local-ai-content")
      if(!content){console.log("FAIL no content");Qt.quit();return}
      var name=runner.find(content,"local-ai-option-name"), fit=runner.find(content,"local-ai-option-fit")
      if(runner.modes[runner.at]==="kind" && (!name || !fit)){console.log("FAIL missing model choices");runner.failed=true}
      if(name && fit) {
        var right=name.mapToItem(content,name.width,0).x, left=fit.mapToItem(content,0,0).x
        var ok=right<=left && name.width>=0 && fit.width>=0
        if(!ok)runner.failed=true
        console.log(ok ? "PASS model name and fit do not overlap" : "FAIL option overlap")
      }
      content.grabToImage(function(img){
        img.saveToFile(Quickshell.env("OUT")+"/"+runner.modes[runner.at]+".png")
        console.log("PASS rendered "+runner.modes[runner.at]+" "+content.width+"x"+content.height)
        runner.at++;if(runner.at===runner.modes.length)Qt.exit(runner.failed?1:0);else step.start()
      })
    }
  }
}
'''
}
for name,data in files.items():
 f=p/name;f.parent.mkdir(exist_ok=True,parents=True);f.write_text(data)
(p/'bin/omarchy-local-ai').chmod(0o755)
g={'key':'nvidia:0','hw':'test','name':'RTX 3090','vramGb':24,'usedMiB':10000,'tempC':45}
r={'id':'test','name':'Qwen3.8-Flash-Next with a deliberately long model name','cards':1,'family':'qwen','weights':[],'ctx':262144,'format':'EXL3','sizeGb':40}
s={'version':'6.5.4','gpus':[g],'kinds':[{'hw':'test','keys':[g['key']],'free':[g['key']],'taken':[],'models':[r,dict(r,id='small',name='Small model',unfit='needs 96 GB RAM, you have 64')],'groups':[]}], 'deployments':[dict(r,keys=[g['key']],state='ready',agent='pi',folder='/home/test/Work',shared='https://machine.example.ts.net:12434',port=12434,session={},startedAt='2026-09-29T17:00:00Z')],'tailnet':'test','defaults':{'agent':'pi','folder':'/home/test/Work'}}
(p/'snapshot.json').write_text(json.dumps(s))

PY
mkdir -p "$TMP/runtime" "$TMP/output" "$TMP/home"
chmod 700 "$TMP/runtime"
if ! env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$TMP/runtime" HOME="$TMP/home" \
  OUT="$TMP/output" timeout --kill-after=2 20 quickshell -p "$TMP" >"$TMP/log" 2>&1; then
  cat "$TMP/log"
  exit 1
fi
if grep -Eq 'FAIL|ReferenceError|TypeError|Unable to assign|Binding loop' "$TMP/log" ||
  [[ $(grep -c 'PASS rendered' "$TMP/log") != 7 ]] || ! grep -q 'PASS model name and fit do not overlap' "$TMP/log"; then
  cat "$TMP/log"
  exit 1
fi
for name in setup kind run error crash stopped refreshed; do test -s "$TMP/output/$name.png"; done
if [[ -n ${PANEL_ARTIFACTS:-} ]]; then
  mkdir -p "$PANEL_ARTIFACTS"
  cp "$TMP/output/"*.png "$TMP/log" "$PANEL_ARTIFACTS/"
fi
echo 'ok - real panel renders setup, choices, sharing, errors, stopped models and refresh results offscreen without overlap'
