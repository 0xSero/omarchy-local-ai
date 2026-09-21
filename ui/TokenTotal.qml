import QtQuick
import qs.Commons
import qs.Ui
import "ui.js" as Ui

// Same geometry, type and proportional fill as Agents' native ModelRow.
Item {
  id: root
  required property var r
  required property var p
  property bool cursor: false
  readonly property var usage: r.history || ({total:0, since:""})
  implicitHeight: name.implicitHeight + Style.spacing.lg
  Accessible.role: Accessible.Button
  Accessible.name: r.label + ", " + r.status + ", " + total.text + " tokens"
  Accessible.onPressAction: p.activate(r.action)
  Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: Util.alpha(p.ink, 0.05) }
  Rectangle {
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    width: parent.width * Math.max(0, Math.min(1, r.share || 0))
    radius: Style.cornerRadius; color: Util.alpha(p.ink, 0.14)
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }
  Rectangle { anchors.fill: parent; color: "transparent"; border.width: root.cursor ? 1 : 0; border.color: p.ink }
  Text {
    id: name
    anchors { left: parent.left; leftMargin: Style.space(8); right: total.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
    text: r.label; color: r.urgent ? p.urgent : p.ink
    font.family: p.mono; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight
  }
  Text {
    id: total
    anchors { right: parent.right; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
    text: root.usage.since ? (root.usage.estimated ? "≈" : "") + Ui.kmg(Math.round(root.usage.total)) : "—"
    color: p.dim; font.family: p.mono; font.pixelSize: Style.font.bodySmall; font.bold: true
  }
  MouseArea {
    id: hover
    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
    onClicked: p.activate(r.action)
  }
  PanelToolTip {
    visible: hover.containsMouse
    text: r.status + " · " + (root.usage.since ? Math.round(root.usage.total).toLocaleString() + " generated tokens · " + Ui.kmg(Math.round(root.usage.today || 0)) + " today" + (root.usage.estimated ? " (estimated)" : "") : "Usage unavailable")
    fontFamily: p.mono
  }
}
