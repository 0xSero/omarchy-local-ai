import QtQuick
import qs.Commons

// A 15×15 field of rounded pixels, circularly clipped, lit from the centre with a quadratic
// falloff. The shimmer animates plain Rectangles: they repaint in this shell, where a
// Canvas's requestPaint does not. Progress never rides on it; that is the bar's job.
Item {
  id: orb
  required property var p   // the Panel: palette, ui tone, opened
  width: Style.space(66); height: width
  readonly property int cells: 15
  readonly property real px: width / cells
  readonly property real fullRadius: cells / 2 * 0.9
  readonly property int period: p.tone === "work" ? 1200 : p.tone === "ready" ? 2400 : p.tone === "error" ? 1800 : 3200
  readonly property color light: p.toneColor
  property real phase: 0
  NumberAnimation on phase { from: 0; to: 1; duration: orb.period; loops: Animation.Infinite; running: orb.p.opened }
  readonly property real litRadius: fullRadius * (0.84 + 0.16 * Math.sin(phase * 2 * Math.PI))
  Repeater {
    model: orb.cells * orb.cells
    Rectangle {
      required property int index
      readonly property int row: Math.floor(index / orb.cells)
      readonly property int col: index % orb.cells
      readonly property real dx: col + 0.5 - orb.cells / 2
      readonly property real dy: row + 0.5 - orb.cells / 2
      readonly property real d: Math.sqrt(dx * dx + dy * dy)
      readonly property real delay: ((row * 3 + col * 2) % 15) / 15
      readonly property real lit: {
        var edge = orb.litRadius, band = Math.min(2.6, edge); if (d >= edge) return 0
        var l = 1 - Math.pow(d / edge, 2) * 0.4; var t = (edge - d) / band; if (t < 1) l *= t * t * (3 - 2 * t)
        return l * (0.65 + 0.35 * Math.sin((orb.phase + delay) * 2 * Math.PI))
      }
      visible: d <= orb.cells / 2
      x: col * orb.px + orb.px / 6; y: row * orb.px + orb.px / 6
      width: orb.px - orb.px / 3; height: width; radius: width / 3
      color: lit > 0.005 ? Qt.rgba(p.orbField.r + (orb.light.r - p.orbField.r) * lit, p.orbField.g + (orb.light.g - p.orbField.g) * lit, p.orbField.b + (orb.light.b - p.orbField.b) * lit, 1) : p.orbField
    }
  }
}
