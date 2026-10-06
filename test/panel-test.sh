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
MODES=(gpus home open-run open-free open-held model agent folder share setup docker stopped starting cpu full-gpus full-home)
python3 - "$ROOT" "$TMP" "${MODES[@]}" <<'PY'
# Isolated shell chrome and snapshot; the plugin QML itself is copied unchanged.
import pathlib,shutil,json,sys
MODES=sys.argv[3:]
p=pathlib.Path(sys.argv[2])
p.mkdir(exist_ok=True)
source=pathlib.Path(sys.argv[1])
for name in ['Panel.qml','Model.js']: shutil.copy(source/name,p/name)
shutil.copytree(source/"logos",p/"logos")
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
  property var modes: __MODES__
  FloatingWindow {
    implicitWidth:340; implicitHeight:1000; color:"#121214"
    Loader { id: ld; source:"Panel.qml"; onLoaded: { item.open(); step.start() } }
  }
  function fullOf(p) { var w=p.data||[]; for(var i=0;i<w.length;i++){ if(w[i]&&w[i].contentItem){var r=find(w[i].contentItem,"local-ai-full"); if(r) return r} } return null }
  function find(o,n) {
    if (o.objectName===n) return o
    var c=o.children||[]
    for(var i=0;i<c.length;i++){var r=find(c[i],n);if(r)return r}
    return null
  }
  Timer {
    id: step; interval:350
    onTriggered: {
      var p=ld.item, mode=runner.modes[runner.at], base=runner.base
      if(!p.snap.gpus){step.start();return}
      if(!base){base=runner.base=p.snap}
      var s=JSON.parse(JSON.stringify(base)), ui={tab:"gpus",view:"",id:"",open:"",picks:{}}
      if(mode==="home")ui.tab="home"
      if(mode==="open-run")ui.open="d:test"
      if(mode==="open-free")ui.open="g:nvidia:1"
      if(mode==="open-held"){s.kinds[0].free=[];s.kinds[0].taken=["nvidia:1"];ui.open="g:nvidia:1"}
      if(["model","agent","folder","share"].indexOf(mode)>=0)ui=Object.assign(ui,{view:mode,id:"test"})
      if(mode==="model"){s.deployments[0].keys=["nvidia:1"];s.kinds[0].free=[]}
      if(mode==="setup")s.readiness={state:"needs-setup"}
      if(mode==="docker")s.readiness={state:"docker-down"}
      if(mode==="stopped"){s.deployments[0].state="error";s.deployments[0].error="the engine stopped";ui.open="d:test"}
      if(mode==="starting"){s.deployments[0].state="download";s.deployments[0].detail="downloading";s.deployments[0].percent=42}
      if(mode==="cpu"){s.gpus=[s.gpus[2]];s.kinds=[s.kinds[1]];s.deployments=[]}
      if(mode==="full-gpus")ui.full=true
      if(mode==="full-home"){ui.full=true;ui.tab="home"}
      p.snap=s; p.ui=ui
      capture.start()
    }
  }
  property var base: null
  Timer {
    id: capture; interval:300
    onTriggered: {
      var p=ld.item, mode=runner.modes[runner.at], content=runner.find(p,"local-ai-content")
      if(!content){console.log("FAIL no content");Qt.quit();return}
      var want={gpus:"row",home:"calendar","open-run":"row","open-free":"row","open-held":"row",model:"list",agent:"opt",folder:"opt",share:"field",setup:"msg",docker:"msg",stopped:"row",starting:"row",cpu:"row","full-gpus":"row","full-home":"calendar"}[mode]
      if(!(p.view.items||[]).some(function(i){return i.type===want})){console.log("FAIL "+mode+" has no "+want);runner.failed=true}
      if(mode.indexOf("full")===0&&!p.view.full){console.log("FAIL no full view");runner.failed=true}
      if(content.height<80){console.log("FAIL "+mode+" drew nothing");runner.failed=true}
      var shot=mode.indexOf("full")===0?runner.find(p.children.length?p:p,"local-ai-full")||fullOf(p):runner.find(p,"local-ai-panel")
      if(!shot){console.log("FAIL nothing to capture for "+mode);runner.failed=true;shot=content}
      shot.grabToImage(function(img){
        img.saveToFile(Quickshell.env("OUT")+"/"+mode+".png")
        console.log("PASS rendered "+mode+" "+content.width+"x"+content.height)
        runner.at++;if(runner.at===runner.modes.length)Qt.exit(runner.failed?1:0);else step.start()
      })
    }
  }
}
'''
}
files['shell.qml'] = files['shell.qml'].replace('__MODES__', json.dumps(MODES))
for name,data in files.items():
 f=p/name;f.parent.mkdir(exist_ok=True,parents=True);f.write_text(data)
(p/'bin/omarchy-local-ai').chmod(0o755)
g={'key':'nvidia:1','hw':'test','name':'NVIDIA GeForce RTX 3090','backend':'nvidia','vramGb':24,'usedMiB':600,'tempC':45}
b={'key':'intel-xpu:0','hw':'b70','name':'Arc Pro B70','backend':'intel-xpu','vramGb':32,'usedMiB':None,'tempC':41}
c={'key':'cpu:0','hw':'cpu','name':'x86-64 AVX2 CPU','backend':'cpu','vramGb':0,'ramGb':64}
r={'id':'test','name':'Qwen3.8-Flash-Next with a deliberately long model name','cards':1,'family':'qwen','weights':[],'ctx':262144,'format':'EXL3','sizeGb':40}
small=dict(r,id='small',name='Gemma 4 26B A4B',family='gemma',onDisk=True)
s={'version':'7.0.0','readiness':{'state':'ready'},'host':{'freeRamGb':41},'total':2810000,'life':{'start':1759100000,'today':9,'days':[10,0,50,230,40,90,0,300,120,800]},
 'gpus':[g,b,c],'kinds':[{'hw':'test','keys':[g['key']],'free':[g['key']],'taken':[],'models':[small,r,dict(r,id='big',name='Big model',unfit='needs 96 GB RAM, you have 64')],'groups':[]},
  {'hw':'cpu','keys':['cpu:0'],'free':['cpu:0'],'taken':[],'models':[dict(r,id='lfm',name='LFM2.5-2.6B',family='lfm')],'groups':[]},
  {'hw':'b70','keys':[b['key']],'free':[],'taken':[],'models':[r],'groups':[]}],
 'deployments':[dict(r,keys=[b['key']],state='ready',agent='claude',folder='/home/test/Work',shared='https://machine.example.ts.net:12434',port=12434,session={'all':{'decode':61}},startedAt='2026-09-29T17:00:00Z')],
 'tailnet':'machine.example.ts.net','agents':['pi','claude','codex','crush'],'defaults':{'agent':'pi','folder':'/home/test/Work'},'folders':['/home/test/notes']}
(p/'snapshot.json').write_text(json.dumps(s))

PY
mkdir -p "$TMP/runtime" "$TMP/output" "$TMP/home"
chmod 700 "$TMP/runtime"
if ! env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
  QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$TMP/runtime" HOME="$TMP/home" \
  OUT="$TMP/output" timeout --kill-after=2 40 quickshell -p "$TMP" >"$TMP/log" 2>&1; then
  cat "$TMP/log"
  exit 1
fi
if grep -Eq 'FAIL|ReferenceError|TypeError|Unable to assign|Binding loop|Cannot open|is not a type' "$TMP/log" ||
  [[ $(grep -c 'PASS rendered' "$TMP/log") != ${#MODES[@]} ]]; then
  cat "$TMP/log"
  exit 1
fi
for name in "${MODES[@]}"; do test -s "$TMP/output/$name.png"; done
if [[ -n ${PANEL_ARTIFACTS:-} ]]; then
  mkdir -p "$PANEL_ARTIFACTS"
  cp "$TMP/output/"*.png "$TMP/log" "$PANEL_ARTIFACTS/"
fi
echo 'ok - the real panel renders every state offscreen: bands, home, rows opened (running, free, in use), model, agent, folder, share, not ready, stopped, starting, CPU, full screen'
