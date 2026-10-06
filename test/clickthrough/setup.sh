#!/bin/bash
# The recording harness on the box: the live plugin's Panel.qml, Model.js, marks and its REAL backend (bin is a symlink,
# so every verb runs for real against ~/.local/state/omarchy/local-ai), inside shell stubs; a caption column; and an
# IPC target `rec` that says where a label is, so the driver clicks on what it names.
set -euo pipefail
P=$HOME/.config/omarchy/plugins/sero.local-ai
H=$HOME/la-rec
rm -rf "$H"; mkdir -p "$H/Commons" "$H/Ui" "$H/bin"
cp "$P/Panel.qml" "$P/Model.js" "$H/"; cp -r "$P/logos" "$P/agents" "$H/"
ln -s "$P/bin/omarchy-local-ai" "$H/bin/omarchy-local-ai"
cat >"$H/Commons/qmldir" <<'Q'
module qs.Commons
singleton Style 1.0 Style.qml
singleton Color 1.0 Color.qml
singleton Util 1.0 Util.qml
Q
cat >"$H/Commons/Style.qml" <<'Q'
pragma Singleton
import QtQuick
QtObject { property var font: ({family:"JetBrainsMono Nerd Font",caption:12,body:14,subtitle:15}); function space(n) { return n } }
Q
cat >"$H/Commons/Color.qml" <<'Q'
pragma Singleton
import QtQuick
QtObject { property color foreground: "#e6e6e6"; property color urgent: "#ff5555"; property var popups: ({background:Qt.rgba(0.07,0.07,0.08,1)}) }
Q
cat >"$H/Commons/Util.qml" <<'Q'
pragma Singleton
import QtQuick
QtObject { function alpha(c,a) { return Qt.rgba(c.r,c.g,c.b,a) } }
Q
cat >"$H/Ui/qmldir" <<'Q'
module qs.Ui
Panel 1.0 Panel.qml
KeyboardPanel 1.0 KeyboardPanel.qml
BarIconButton 1.0 BarIconButton.qml
Q
cat >"$H/Ui/Panel.qml" <<'Q'
import QtQuick
Item { property string moduleName; property string ipcTarget; property var bar:null; property bool opened:false
function open(){opened=true} function close(){} function toggle(){opened=!opened} }
Q
cat >"$H/Ui/KeyboardPanel.qml" <<'Q'
import QtQuick
Item { property var anchorItem; property var owner; property var bar; property bool open; property var focusTarget; property int padding
property int contentWidth; property int contentHeight; width:contentWidth; height:contentHeight
function fittedContentHeight(h){return h} }
Q
cat >"$H/Ui/BarIconButton.qml" <<'Q'
import QtQuick
Item { property var bar; property string tooltipText; property Component iconComponent; signal pressed(); implicitWidth:24; implicitHeight:24 }
Q
cat >"$H/shell.qml" <<'Q'
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: rec
  property var steps: []
  FloatingWindow {
    id: win
    title: "panel"
    implicitWidth: 760; implicitHeight: 860; color: "#0b0b0c"
    Loader { id: ld; x: 20; y: 20; source: "Panel.qml"; onLoaded: item.open() }
    Rectangle { x: 20; y: 20; width: 340; height: 800; color: "transparent"; border.color: "#2a2a2e"; border.width: 1; z: -1 }
    // the pointer, drawn: it glides to each click and rings where it pressed
    Item {
      id: cursor
      z: 100; x: 600; y: 400
      Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
      Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
      Rectangle { id: ring; x: -14; y: -14; width: 28; height: 28; radius: 14; color: "transparent"; border.color: "#ffffff"; border.width: 2; opacity: 0
        NumberAnimation on opacity { id: ringFade; from: 0.9; to: 0; duration: 600; running: false } }
      Canvas { width: 16; height: 22; onPaint: { var g = getContext("2d"); g.fillStyle = "#ffffff"; g.strokeStyle = "#000000"; g.lineWidth = 1.2
        g.beginPath(); g.moveTo(0, 0); g.lineTo(0, 17); g.lineTo(4.5, 13); g.lineTo(8, 20); g.lineTo(10.5, 19); g.lineTo(7, 12); g.lineTo(12.5, 12); g.closePath(); g.fill(); g.stroke() } }
    }
    Column {
      x: 400; y: 24; width: 340; spacing: 8
      Text { text: "Local AI 7.1.0 · click-through on omarchy"; color: "#e6e6e6"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
      Text { text: "real backend · real clicks · " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm"); color: "#8a8a90"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 }
      Item { width: 1; height: 8 }
      Repeater {
        model: rec.steps
        Text { required property var modelData; required property int index; width: 340; wrapMode: Text.WordWrap
          text: (index + 1) + ". " + modelData; color: index === rec.steps.length - 1 ? "#ffffff" : "#8a8a90"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 }
      }
    }
  }
  function find(o, t, n, acc) {
    if (!o) return acc
    if (o.text === t && o.visible !== false && o.width > 0 && o.opacity !== 0) acc.push(o)
    var c = o.children || []
    for (var i = 0; i < c.length; i++) find(c[i], t, n, acc)
    return acc
  }
  Timer { id: later; property var ma; property bool full; interval: 420; onTriggered: { if (!full) ringFade.restart(); ma.clicked(null) } }
  // the deepest, topmost enabled MouseArea at a point (window coordinates)
  function hit(item, x, y) {
    var c = item.children || []
    for (var i = c.length - 1; i >= 0; i--) {
      var ch = c[i]
      if (!ch || ch.visible === false || ch.opacity === 0) continue
      var q = ch.mapFromItem(null, x, y)
      var inside = q.x >= 0 && q.y >= 0 && q.x < ch.width && q.y < ch.height
      var deeper = hit(ch, x, y)
      if (deeper) return deeper
      if (inside && ch.enabled && ch.clicked !== undefined && ch.cursorShape !== undefined) return ch
    }
    return null
  }
  function fullItem() {
    var d = ld.item ? ld.item.data : []
    for (var i = 0; i < d.length; i++) if (d[i] && d[i].contentItem && d[i].visible) return d[i].contentItem
    return null
  }
  IpcHandler {
    target: "rec"
    // where a label is, in its window: "x y" of its centre, or "" (n: the nth match, 0 first; full: in the full window)
    function pos(t: string, n: int, full: bool): string {
      var root = full ? fullItem() : win.contentItem
      var hits = find(root, t, n, []).filter(function(o) { var p = o.mapToItem(null, 0, 0); return p.y >= 0 && p.y < (full ? 800 : 860) })
      var o = hits[n]
      if (!o) return ""
      var p = o.mapToItem(null, o.width / 2, o.height / 2)
      return Math.round(p.x) + " " + Math.round(p.y)
    }
    function step(s: string): void { rec.steps = rec.steps.concat([s]) }
    // click on a label: the cursor goes there, then the topmost enabled MouseArea under that point gets the click,
    // exactly the handler a pointer press there runs
    function click(t: string, n: int, full: bool): string {
      var root = full ? fullItem() : win.contentItem
      var hits = find(root, t, n, []).filter(function(o) { var p = o.mapToItem(null, 0, 0); return p.y >= 0 && p.y < (full ? 800 : 860) })
      var o = hits[n]
      if (!o) return ""
      var p = o.mapToItem(null, o.width / 2, o.height / 2)
      if (!full) { cursor.x = p.x; cursor.y = p.y }
      var ma = hit(root, p.x, p.y)
      if (!ma) return "no target"
      later.ma = ma; later.full = full; later.restart()
      return "ok"
    }
    function full(): bool { return !!fullItem() }
  }
}
Q
echo "harness at $H"
