import QtQuick
import qs.Commons
import "ui.js" as Ui

// Fixed 24-hour scale; empty intervals remain unknown, never invented activity.
Item {
  id: root
  required property var history
  required property color ink
  required property color dim
  required property color accent
  required property string fontFamily
  Accessible.role: Accessible.StaticText
  Accessible.name: known ? Math.round(history.total) + " observed tokens since " + history.since + ". Daily token activity in fifteen-minute intervals." : "No token history recorded yet."
  property int hovered: -1
  readonly property var bins: history.bins || []
  readonly property real peak: Math.max.apply(null, [1].concat(bins.map(function(n) { return n || 0 })))
  readonly property bool known: bins.some(function(n) { return n !== null })
  function clock(i) { return (Math.floor(i / 4) < 10 ? "0" : "") + Math.floor(i / 4) + ":" + (i % 4 === 0 ? "00" : (i % 4) * 15) }
  Text {
    anchors.left: parent.left; anchors.top: parent.top
    text: root.hovered >= 0 ? (root.bins[root.hovered] == null ? "No reading" : Ui.kmg(Math.round(root.bins[root.hovered])) + " tokens") : root.known ? Ui.kmg(Math.round(root.history.total)) + " tokens" : "No token history yet"
    color: root.hovered >= 0 ? root.ink : root.dim
    font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
  Text {
    anchors.right: parent.right; anchors.top: parent.top
    text: root.hovered >= 0 ? root.clock(root.hovered) + "–" + root.clock(root.hovered + 1) : root.history.since ? "since " + Qt.formatDateTime(new Date(root.history.since), "HH:mm") : "today"
    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
  }
  Item {
    id: plot
    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: axis.top; topMargin: Style.space(24); bottomMargin: Style.space(5) }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Util.alpha(root.ink, 0.1) }
    Repeater {
      model: 96
      Rectangle {
        required property int index
        readonly property var count: root.bins[index]
        x: index * plot.width / 96
        width: Math.max(1, plot.width / 96 - 1)
        height: count > 0 ? Math.max(2, plot.height * count / root.peak) : count === 0 ? 2 : 0
        anchors.bottom: parent.bottom
        radius: Math.min(1, width / 2)
        color: index === root.hovered ? root.accent : Util.alpha(root.ink, root.hovered < 0 || index === root.hovered ? 0.65 : 0.28)
      }
    }
    Rectangle {
      visible: root.hovered >= 0; x: (root.hovered + 0.5) * plot.width / 96
      width: 1; height: parent.height; color: Util.alpha(root.accent, 0.45)
    }
    MouseArea {
      anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton
      onPositionChanged: function(mouse) { root.hovered = Math.max(0, Math.min(95, Math.floor(mouse.x / width * 96))) }
      onExited: root.hovered = -1
    }
  }
  Item {
    id: axis
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: Style.space(12)
    Repeater {
      model: ["00:00", "12:00", "24:00"]
      Text {
        required property string modelData
        required property int index
        x: index * (axis.width - width) / 2
        text: modelData; color: Util.alpha(root.dim, 0.75)
        font.family: root.fontFamily; font.pixelSize: Style.fontPx(0.65)
      }
    }
  }
}
