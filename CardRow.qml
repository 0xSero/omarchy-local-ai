import QtQuick
import qs.Commons
import qs.Ui

// One row of the card, drawn from a row object produced by Model.js. p is the Panel (palette, cursor,
// activate). Types: sec (a section word), row (noun · datum, with cells or chips under it, or tabs
// beside it), status (verb · progress), bar, stat (two figures), text (a wrapped reason).
Item {
  id: item
  required property var r
  required property var p
  property bool cursor: false
  readonly property bool actionable: !!r.action && !r.disabled
  readonly property bool primary: r.kind === "primary"
  readonly property bool disclosure: typeof r.expanded === "boolean"
  readonly property bool hasLine2: !!(r.cells && r.cells.length) || !!(r.chips && r.chips.length)
  readonly property real pad: Style.space(12)
  readonly property real indent: r.kind === "dd" ? Style.space(12) : 0
  readonly property color labelColor: r.disabled ? p.faint : r.kind === "danger" || r.urgent ? p.urgent : p.ink
  readonly property color valueColor: r.disabled ? p.faint : r.urgent ? p.urgent : p.dim
  implicitHeight: r.type === "sec" ? Style.space(46) : r.type === "bar" ? Style.space(6) : r.type === "stat" ? Style.space(56) : r.type === "status" ? Style.space(46)
    : r.detail ? Style.space(58) : r.type === "text" ? wrapped.implicitHeight + Style.space(20) : (disclosure || r.kind === "dd" || r.compact) ? Style.space(34) : Style.space(46) + (hasLine2 ? Style.space(22) : 0)

  PanelSeparator { visible: r.type === "sec"; anchors.top: parent.top; anchors.topMargin: Style.space(8); width: parent.width; foreground: p.ink }
  PanelSectionHeader {
    visible: r.type === "sec"; anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4)
    text: r.label.toUpperCase(); foreground: p.ink; fontFamily: p.mono
  }
  Button { // the same control states and borders as the native provider buttons
    anchors.fill: parent
    visible: r.type === "row" && !(r.tabs && r.tabs.length)
    enabled: item.actionable; bordered: false; selected: primary || !!r.selected
    hasCursor: item.cursor; foreground: p.ink; fontFamily: p.mono
    onClicked: p.activate(r.action)
  }
  Text {
    textFormat: Text.PlainText
    visible: disclosure; x: pad; anchors.verticalCenter: parent.verticalCenter
    text: r.expanded ? "▾" : "▸"; color: p.ink; font.family: p.mono; font.pixelSize: Style.font.body
  }
  Rectangle {
    anchors.fill: parent; visible: r.type === "status" || r.type === "text"
    color: p.restFill; border.width: 1; border.color: p.hairline
  }
  Rectangle { // the bar: a fill when a step reports a percent, a sweep while it cannot
    visible: r.type === "bar"; anchors.fill: parent; color: p.restFill
    Rectangle {
      id: fill; readonly property bool sweeping: (r.percent || 0) === 0; property real sweepX: 0
      height: parent.height; color: p.accent; width: sweeping ? parent.width * 0.25 : Math.max(2, parent.width * (r.percent || 0) / 100); x: sweeping ? sweepX : 0
      NumberAnimation on sweepX { running: r.type === "bar" && fill.sweeping && p.opened; loops: Animation.Infinite; from: 0; to: fill.parent.width * 0.75; duration: 1400; easing.type: Easing.InOutSine }
      Behavior on width { enabled: !fill.sweeping; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    }
  }
  Text { // line one: the noun
    textFormat: Text.PlainText
    visible: r.type === "row" || r.type === "status"
    anchors.left: parent.left; anchors.leftMargin: pad + indent + (disclosure ? Style.space(20) : 0); y: hasLine2 || r.detail ? Style.space(8) : (item.height - height) / 2
    width: parent.width - anchors.leftMargin - pad - value.width - Style.space(12)
    text: r.label; color: labelColor; font.family: p.mono; font.pixelSize: Style.font.bodySmall; font.bold: disclosure; elide: Text.ElideRight
  }
  Text { // line one: the datum
    textFormat: Text.PlainText
    id: value; visible: (r.type === "row" && !(r.tabs && r.tabs.length)) || r.type === "status"
    anchors.right: parent.right; anchors.rightMargin: pad; y: hasLine2 || r.detail ? Style.space(8) : (item.height - height) / 2
    text: r.value; color: r.type === "status" ? p.ink : valueColor; font.family: p.mono; font.pixelSize: r.type === "status" ? Style.font.subtitle : Style.font.caption
    width: Math.min(implicitWidth, item.width * 0.6); elide: Text.ElideLeft
  }
  Text {
    textFormat: Text.PlainText
    visible: !!r.detail
    anchors { left: parent.left; right: parent.right; leftMargin: pad; rightMargin: pad; bottom: parent.bottom; bottomMargin: Style.space(8) }
    text: r.detail || ""; color: r.urgent ? p.urgent : p.dim
    font.family: p.mono; font.pixelSize: Style.font.caption; elide: Text.ElideRight
  }
  Row { // the count toggle, beside the noun
    visible: r.type === "row" && !!(r.tabs && r.tabs.length); anchors.right: parent.right; anchors.rightMargin: pad; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(4)
    Repeater { model: r.tabs || []
      Button { required property var modelData; text: modelData.text; selected: !!modelData.on; bordered: true
        foreground: p.ink; fontFamily: p.mono; fontSize: Style.font.caption; verticalPadding: Style.space(4)
        onClicked: p.activate(modelData.action) } }
  }
  Row { // line two: cells (one per physical card) or chips (capabilities)
    visible: hasLine2; anchors.left: parent.left; anchors.leftMargin: pad; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(10); spacing: Style.space(6)
    Repeater { model: (r.cells || []).concat(r.chips || [])
      Rectangle { required property var modelData; readonly property bool isCell: modelData.mark !== undefined
        readonly property color markColor: modelData.mark === "used" ? p.ink : modelData.mark === "claimed" ? p.accent : modelData.mark === "freeing" ? Qt.rgba(p.accent.r, p.accent.g, p.accent.b, 0.5) : modelData.mark === "crashed" ? p.urgent : "transparent"
        width: cellText.implicitWidth + Style.space(14) + (isCell && modelData.mark !== "" ? Style.space(12) : 0); height: Style.space(20); color: modelData.off ? "transparent" : p.restFill
        Rectangle { visible: parent.isCell && modelData.mark !== ""; x: Style.space(7); anchors.verticalCenter: parent.verticalCenter; width: Style.space(7); height: width; color: parent.markColor; border.width: modelData.mark === "free" ? 1 : 0; border.color: p.faint }
        Text { textFormat: Text.PlainText; id: cellText; anchors.right: parent.right; anchors.rightMargin: Style.space(7); anchors.verticalCenter: parent.verticalCenter; text: modelData.text; color: modelData.off ? p.faint : modelData.mark === "used" ? p.fg : p.dim; font.strikeout: !!modelData.off; font.family: p.mono; font.pixelSize: Style.font.caption } } }
  }
  Row { // two figures
    visible: r.type === "stat"; anchors.fill: parent; spacing: Style.space(4)
    Repeater { model: r.stat || []
      Rectangle { required property var modelData; width: (parent.width - Style.space(4)) / 2; height: parent.height; color: "transparent"
        Column { anchors.left: parent.left; anchors.leftMargin: pad; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
          PanelSectionHeader { text: modelData.k.toUpperCase(); foreground: p.ink; fontFamily: p.mono }
          Row { spacing: Style.space(5)
            Text { textFormat: Text.PlainText; text: modelData.v; color: p.ink; font.family: p.mono; font.pixelSize: Style.font.title }
            Text { textFormat: Text.PlainText; anchors.baseline: parent.children[0].baseline; text: modelData.u; color: p.dim; font.family: p.mono; font.pixelSize: Style.font.caption } } } } }
  }
  Text { // a wrapped datum: the one place a whole reason is shown
    textFormat: Text.PlainText
    id: wrapped; visible: r.type === "text"; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: pad; anchors.verticalCenter: parent.verticalCenter
    text: r.label + " · " + r.value; color: r.urgent ? p.urgent : p.dim; font.family: p.mono; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
}
