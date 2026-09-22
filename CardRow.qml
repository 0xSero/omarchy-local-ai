import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// One row of the card, drawn from a row object produced by Model.js. p is the Panel: palette, cursor, activate, act.
Item {
  id: item
  required property var r
  required property var p
  property bool cursor: false
  readonly property bool actionable: !!r.action && !r.disabled
  readonly property real pad: Style.space(16)
  readonly property color lead: r.dim || r.disabled ? p.dim : p.ink
  implicitHeight: r.type === "gap" ? Style.space(10) : r.type === "num2" ? Style.space(52) : r.type === "bars" ? (r.big ? Style.space(76) : Style.space(40)) : r.type === "prog" ? Style.space(40)
    : r.type === "gpu" ? Style.space(24) : r.type === "h" ? Style.space(30) : r.type === "hbar" ? Style.space(22) : r.type === "spark" ? Style.space(48) : r.type === "axis" ? Style.space(16)
    : r.type === "text" ? wrapped.implicitHeight + Style.space(16) : r.type === "field" ? Style.space(40) : r.type === "opt" ? Style.space(30) : Style.space(34)

  Rectangle { anchors.fill: parent; visible: item.cursor && item.actionable; color: p.hoverFill }
  MouseArea { anchors.fill: parent; enabled: item.actionable; cursorShape: Qt.PointingHandCursor; onClicked: p.activate(r.action) }

  // two figures side by side
  Row { visible: r.type === "num2"; x: pad; anchors.verticalCenter: parent.verticalCenter; width: parent.width - pad * 2
    Repeater { model: r.type === "num2" ? [r.a, r.b] : []
      Column { required property var modelData; required property int index; width: parent.width / 2; spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: modelData.v; color: p.ink; font.family: p.mono; font.pixelSize: Style.font.display; anchors.right: index ? parent.right : undefined }
        Text { textFormat: Text.PlainText; text: modelData.k; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption; anchors.right: index ? parent.right : undefined } } } }
  // bars: one per day, the last one in ink
  Row { visible: r.type === "bars"; x: pad; width: parent.width - pad * 2; height: parent.height - Style.space(10); anchors.bottom: parent.bottom; spacing: Style.space(3)
    Repeater { model: r.type === "bars" ? r.values : []
      Rectangle { required property var modelData; required property int index; width: (parent.width - Style.space(3) * (r.values.length - 1)) / r.values.length; anchors.bottom: parent.bottom
        readonly property real peak: Math.max.apply(null, r.values.concat([1])); height: Math.max(2, parent.height * modelData / peak); color: index === r.hi ? p.fg : p.faint } } }
  // progress
  Item { visible: r.type === "prog"; x: pad; width: parent.width - pad * 2; height: parent.height
    Text { textFormat: Text.PlainText; y: Style.space(6); text: r.left || ""; color: p.fg; font.family: p.mono; font.pixelSize: Style.font.bodySmall }
    Text { textFormat: Text.PlainText; y: Style.space(6); anchors.right: parent.right; text: r.right || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.bodySmall }
    Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(8); width: parent.width; height: 3; color: p.faint
      Rectangle { id: fill; readonly property bool sweeping: (r.pct || 0) === 0; property real sweepX: 0; height: parent.height; color: p.fg; width: sweeping ? parent.width * 0.25 : parent.width * (r.pct || 0) / 100; x: sweeping ? sweepX : 0
        NumberAnimation on sweepX { running: r.type === "prog" && fill.sweeping && p.opened; loops: Animation.Infinite; from: 0; to: fill.parent.width * 0.75; duration: 1400; easing.type: Easing.InOutSine } } } }
  // a reason, wrapped
  Text { id: wrapped; textFormat: Text.PlainText; visible: r.type === "text"; x: pad; width: parent.width - pad * 2; anchors.verticalCenter: parent.verticalCenter
    text: (r.lead ? r.lead + " " : "") + (r.text || ""); color: p.fg; font.family: p.mono; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WrapAtWordBoundaryOrAnywhere }
  // one GPU: index, name, temperature, load bar, memory
  Item { visible: r.type === "gpu"; x: pad; width: parent.width - pad * 2; height: parent.height
    readonly property color c: r.busy ? p.fg : p.dim
    Text { textFormat: Text.PlainText; x: 0; anchors.verticalCenter: parent.verticalCenter; text: r.idx || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption }
    Text { textFormat: Text.PlainText; x: Style.space(28); width: Style.space(96); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: r.name || ""; color: r.busy ? p.ink : p.dim; font.family: p.mono; font.pixelSize: Style.font.caption }
    Text { textFormat: Text.PlainText; x: Style.space(130); anchors.verticalCenter: parent.verticalCenter; text: r.temp || ""; color: parent.c; font.family: p.mono; font.pixelSize: Style.font.caption }
    Rectangle { x: Style.space(166); width: parent.width - Style.space(166) - Style.space(70); height: 3; anchors.verticalCenter: parent.verticalCenter; color: p.faint
      Rectangle { width: parent.width * (r.pct || 0) / 100; height: parent.height; color: p.fg } }
    Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: r.used !== "" ? r.used + " / " + r.total : r.total; color: parent.c; font.family: p.mono; font.pixelSize: Style.font.caption } }
  // a section word with a figure at the right
  Item { visible: r.type === "h"; x: pad; width: parent.width - pad * 2; height: parent.height
    Text { textFormat: Text.PlainText; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4); text: r.label || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption; font.letterSpacing: 1.5 }
    Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4); text: r.right || ""; color: p.fg; font.family: p.mono; font.pixelSize: Style.font.caption } }
  // a horizontal bar with a label and a figure
  Item { visible: r.type === "hbar"; x: pad; width: parent.width - pad * 2; height: parent.height
    Text { textFormat: Text.PlainText; width: Style.space(90); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: r.label || ""; color: p.fg; font.family: p.mono; font.pixelSize: Style.font.caption }
    Rectangle { x: Style.space(100); width: parent.width - Style.space(100) - Style.space(56); height: 5; anchors.verticalCenter: parent.verticalCenter; color: p.faint
      Rectangle { width: parent.width * (r.pct || 0) / 100; height: parent.height; color: p.fg } }
    Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: r.right || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption } }
  // a line over time
  Canvas { visible: r.type === "spark"; x: pad; width: parent.width - pad * 2; height: parent.height - Style.space(8); y: Style.space(4)
    onPaint: { var ctx = getContext("2d"), vs = r.values || [], n = vs.length, ok = vs.filter(function(v) { return v != null }), max = Math.max.apply(null, ok.concat([1])); ctx.clearRect(0, 0, width, height)
      ctx.strokeStyle = p.fg; ctx.lineWidth = 1.2; ctx.beginPath(); var started = false
      for (var i = 0; i < n; i++) { if (vs[i] == null) { started = false; continue } var px = n > 1 ? i / (n - 1) * width : 0, py = height - vs[i] / max * (height - 4) - 2; if (started) ctx.lineTo(px, py); else ctx.moveTo(px, py); started = true }
      ctx.stroke() }
    Component.onCompleted: requestPaint(); onVisibleChanged: requestPaint()
    Connections { target: item; function onRChanged() { requestPaint() } } }
  // axis labels under a chart
  Row { visible: r.type === "axis"; x: pad; width: parent.width - pad * 2; anchors.verticalCenter: parent.verticalCenter
    Repeater { model: r.type === "axis" ? r.labels : []
      Text { required property var modelData; textFormat: Text.PlainText; width: parent.width / r.labels.length; horizontalAlignment: Text.AlignHCenter; text: modelData; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption } } }
  // an option with a radio mark
  Item { visible: r.type === "opt"; x: pad; width: parent.width - pad * 2; height: parent.height
    Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: (r.on ? "● " : "○ ") + (r.label || ""); color: r.disabled ? p.faint : r.on ? p.ink : p.fg; font.family: p.mono; font.pixelSize: Style.font.bodySmall }
    Text { textFormat: Text.PlainText; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: r.small || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption } }
  // the project folder, editable
  Controls.TextField { id: field; visible: r.type === "field"; x: pad; width: parent.width - pad * 2; anchors.verticalCenter: parent.verticalCenter
    text: r.value || ""; color: p.ink; selectionColor: p.hoverFill; selectedTextColor: p.ink; font.family: p.mono; font.pixelSize: Style.font.bodySmall; placeholderText: "project folder"
    background: Rectangle { color: "transparent"; border.color: field.activeFocus ? p.dim : p.faint; border.width: 1 }
    onAccepted: { var v = text; if (v === "~" || v.indexOf("~/") === 0) v = p.home + v.slice(1); p.act(["agent-dir", v]); p.focusContent() }
    Keys.onEscapePressed: p.focusContent() }
  // a row: name, detail, and the verb at the right
  Item { visible: r.type === "row"; x: pad; width: parent.width - pad * 2; height: parent.height
    Text { textFormat: Text.PlainText; id: lbl; anchors.verticalCenter: parent.verticalCenter; text: r.label || ""; color: item.lead; font.family: p.mono; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight; width: Math.min(implicitWidth, parent.width - verb.width - Style.space(20)) }
    Text { textFormat: Text.PlainText; anchors.left: lbl.right; anchors.leftMargin: Style.space(8); anchors.right: verb.left; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: r.small || ""; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
    Text { textFormat: Text.PlainText; id: verb; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: r.verb ? r.verb + " ›" : ""; color: item.actionable ? p.ink : p.faint; font.family: p.mono; font.pixelSize: Style.font.bodySmall } }
}
