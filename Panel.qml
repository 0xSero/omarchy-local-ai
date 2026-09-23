import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Local AI: the model validated for your GPU, one click to run it, one click to open your agent on it.
// Model.js turns the backend's snapshot into a view; this file draws it and runs the backend's verbs.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string cli: String(Qt.resolvedUrl("bin/omarchy-local-ai")).replace(/^file:\/\//, "")
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property color fg: Qt.darker(ink, 1.3)
  readonly property color dim: Qt.darker(ink, 1.9)
  readonly property color faint: Util.alpha(ink, 0.14)
  readonly property color lit: Util.alpha(ink, 0.06)
  readonly property color bg: Color.popups.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string mono: bar ? bar.fontFamily : Style.font.family

  property var snap: ({})
  property var ui: ({ view: "home", id: "", open: "", key: "", problem: "" })
  property bool revealed: false
  property var queue: []
  // A snapshot the view cannot read says so, rather than looking like a machine with no GPU
  readonly property var view: {
    try {
      return Model.build(snap, ui)
    } catch (e) {
      return { title: "LOCAL AI", right: "", mark: "failed", rows: [{ type: "error", label: "could not read the backend's answer: " + e.message }] }
    }
  }

  function nav(patch) {
    ui = Object.assign({ view: ui.view, id: ui.id, open: "", key: ui.key, problem: "" }, patch)
    revealed = false
    flick.contentY = 0
  }
  function home() { nav({ view: "home", id: "", key: "" }) }
  function run(args) { queue.push(args); if (!verb.running) next() }
  function next() {
    if (!queue.length) return refresh()
    verb.command = [cli].concat(queue.shift())
    verb.running = true
  }
  function refresh() { if (!poll.running) poll.running = true }

  // An action is "verb|arg|arg", from Model.js
  function activate(action) {
    var a = (action || "").split("|")
    switch (a[0]) {
    case "run": run(["run", a[1], a[2]]); home(); break
    case "again": run(["stop", a[1]]); run(["run", a[1], a[2]]); home(); break
    case "stop": run(["stop", a[1]]); home(); break
    case "open": run(["open", a[1]]); root.close(); break
    case "share": run(["share", a[1]]); break
    case "set": run(["set", a[1], a[2]].concat(a[3] ? [a[3]] : [])); nav({ open: "" }); break
    case "more": nav({ view: "run", id: a[1] }); break
    case "kind": nav({ view: "kind", id: a[1], key: "" }); break
    case "tick": nav({ key: a[1] }); break
    case "pick": nav({ open: ui.open === a[1] ? "" : a[1] }); break
    case "home": home(); break
    case "log": logOpen.running = true; root.close(); break
    case "url": Quickshell.execDetached(["omarchy-launch-browser", a[1]]); root.close(); break
    case "copy":
      if (revealed) copy.command = ["wl-copy", a[1]]
      copy.running = revealed
      revealed = true
      break
    }
  }

  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.snap = Model.parse(text) || root.snap }
  }
  // A verb that fails says why on its last "local-ai:" line; the panel opens to show it
  Process {
    id: verb
    stderr: StdioCollector { id: verbErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        var m = (verbErr.text || "").split("\n").filter(function(l) { return l.indexOf("local-ai: ") === 0 }).pop()
        root.queue = []
        if (!root.opened) root.open()
        root.ui = Object.assign({}, root.ui, { problem: m ? m.slice(10) : "that did not work (see the log)" })
      }
      root.next()
    }
  }
  Process { id: copy }
  Process { id: logOpen; command: [root.cli, "log"] }
  Timer {
    interval: root.view.mark === "busy" ? 1500 : root.opened ? 5000 : 30000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }
  onOpenedChanged: if (opened) { refresh(); if (!ui.problem) home() }

  // Nine dots: faint when idle, lit when a model is ready, urgent when one failed, a diagonal ripple while working
  property int ripple: 0
  Timer { interval: 160; repeat: true; running: root.view.mark === "busy"; onTriggered: root.ripple = (root.ripple + 1) % 5 }
  BarIconButton {
    id: button
    objectName: "local-ai-mark"
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Local AI"
    onPressed: root.toggle()
    iconComponent: Component {
      Item {
        Grid {
          anchors.centerIn: parent
          columns: 3
          spacing: Style.space(2)
          Repeater {
            model: 9
            Rectangle {
              required property int index
              readonly property bool on: root.view.mark === "busy" ? (index % 3 + Math.floor(index / 3)) === root.ripple % 5 : !!root.view.mark
              width: Style.space(3)
              height: width
              radius: width / 2
              color: root.view.mark === "failed" ? root.urgent : on ? root.ink : Util.alpha(root.ink, 0.3)
            }
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    padding: 0
    contentWidth: Style.space(340)
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Rectangle { anchors.fill: parent; color: root.bg }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.ui.view === "home" ? root.close() : root.home()

      Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          objectName: "local-ai-content"
          width: flick.width
          topPadding: Style.space(14)
          bottomPadding: Style.space(14)
          spacing: Style.space(10)

          // The top line: the name and version, or the way back; the week, or the page's name
          Item {
            width: parent.width
            height: Style.space(16)
            Label {
              id: head
              x: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: root.view.back ? "‹ home" : root.view.title
              color: root.dim
              font.letterSpacing: root.view.back ? 0 : 1.5
            }
            Label {
              visible: !root.view.back
              anchors.left: head.right
              anchors.leftMargin: Style.space(8)
              anchors.baseline: head.baseline
              text: root.view.version || ""
              color: root.faint
              font.pixelSize: Style.font.caption - 2
            }
            Click { anchors.fill: head; action: root.view.back ? "home" : "" }
            Right { margin: 16; text: root.view.back ? root.view.title : root.view.right; color: root.dim; font.letterSpacing: root.view.back ? 1.5 : 0 }
          }

          Loader {
            active: !!root.view.hero
            x: Style.space(12)
            width: parent.width - Style.space(24)
            height: active && item ? item.implicitHeight + Style.space(20) : 0
            sourceComponent: Component { Hero { h: root.view.hero } }
          }

          Repeater {
            model: root.view.rows
            Item {
              required property var modelData
              readonly property var r: modelData
              width: content.width
              height: row.height

              // A Loader sizes its item, so a row's side inset lives on the Loader
              Loader {
                id: row
                readonly property real inset: ["run", "soon", "grid", "busy"].indexOf(r.type) >= 0 ? Style.space(12) : 0
                x: inset
                width: parent.width - 2 * inset
                sourceComponent: ({ run: runC, free: freeC, soon: soonC, busy: busyC, grid: gridC, gpu: gpuC,
                  field: fieldC, opt: optC, path: pathC, acts: actsC })[r.type] || textC
              }

              // A running model: its all-time token line behind its name, card, speed and tokens; Open and More
              Component {
                id: runC
                Rectangle {
                  height: Style.space(156)
                  color: r.error ? Util.alpha(root.urgent, 0.07) : root.lit
                  clip: true
                  Line { anchors.fill: parent; values: r.line }
                  Column {
                    x: Style.space(18)
                    y: Style.space(18)
                    width: parent.width - Style.space(36)
                    spacing: Style.space(6)
                    Row {
                      spacing: Style.space(10)
                      Logo { family: r.family; size: 18; anchors.verticalCenter: parent.verticalCenter }
                      Label { text: r.name; color: root.ink; font.pixelSize: Style.font.subtitle }
                    }
                    Label { text: r.gpu; color: root.dim }
                    Item { width: 1; height: Style.space(4) }
                    Label {
                      width: parent.width
                      text: r.sub.join("  ·  ")
                      color: r.error ? root.urgent : root.fg
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                    Rectangle {
                      visible: r.progress >= 0
                      width: parent.width
                      height: 2
                      color: root.faint
                      Rectangle { width: parent.width * (r.progress || 0) / 100; height: parent.height; color: root.ink }
                    }
                  }
                  Row {
                    x: Style.space(18)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(16)
                    spacing: Style.space(8)
                    Btn {
                      label: r.primary.label + (r.primary.quiet ? "" : " ›")
                      action: r.primary.action
                      primary: !r.primary.quiet
                      danger: !!r.primary.quiet
                    }
                    Btn { label: "More"; action: r.more }
                  }
                }
              }

              // A free card kind: one dashed line; its left opens the kind's page, its right runs the model
              Component {
                id: freeC
                Item {
                  height: Style.space(40)
                  Canvas {
                    x: Style.space(12)
                    width: parent.width - Style.space(24)
                    height: parent.height
                    onPaint: {
                      var g = getContext("2d")
                      g.setLineDash([3, 3])
                      g.strokeStyle = root.faint
                      g.strokeRect(0.5, 0.5, width - 1, height - 1)
                    }
                  }
                  Label { id: kindLabel; x: Style.space(26); anchors.verticalCenter: parent.verticalCenter; text: r.label; color: root.dim }
                  Click { anchors.fill: kindLabel; action: r.more }
                  Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(26)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)
                    Logo { family: r.family; size: 11; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: "run " + r.model + " ›" }
                  }
                  Click {
                    anchors.fill: undefined
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    width: parent.width * 0.5
                    height: parent.height
                    action: r.action || r.more
                  }
                }
              }

              // No card to run on: a chip, one line, and where the list of supported cards lives
              Component {
                id: soonC
                Column {
                  topPadding: Style.space(28)
                  bottomPadding: Style.space(20)
                  spacing: Style.space(18)
                  Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(64)
                    height: width
                    onPaint: {
                      var g = getContext("2d"), a = width * 0.22, b = width * 0.78, p = width * 0.12
                      g.clearRect(0, 0, width, height)
                      g.strokeStyle = root.dim
                      g.lineWidth = 1.5
                      g.strokeRect(a, a, b - a, b - a)
                      g.strokeRect(width * 0.38, width * 0.38, width * 0.24, width * 0.24)
                      for (var i = 0; i < 4; i++) {
                        var t = a + (b - a) * (i + 0.5) / 4
                        g.beginPath()
                        g.moveTo(t, a); g.lineTo(t, p)
                        g.moveTo(t, b); g.lineTo(t, width - p)
                        g.moveTo(a, t); g.lineTo(p, t)
                        g.moveTo(b, t); g.lineTo(width - p, t)
                        g.stroke()
                      }
                    }
                  }
                  Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: r.head
                    color: root.ink
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                  Btn { anchors.horizontalCenter: parent.horizontalCenter; label: "See supported cards ›"; action: r.action }
                }
              }

              // Cards Local AI cannot use (another program holds them, or no model is validated): a bordered warning
              Component {
                id: busyC
                Box {
                  height: Style.space(40)
                  border.color: Util.alpha(root.urgent, 0.45)
                  Label { x: Style.space(14); anchors.verticalCenter: parent.verticalCenter; text: r.label }
                  Right { margin: 14; text: r.note; color: root.urgent }
                }
              }

              // A section's name, or an error in its place
              Component {
                id: textC
                Label {
                  readonly property bool sec: r.type === "sec"
                  leftPadding: Style.space(16); rightPadding: Style.space(16); topPadding: sec ? Style.space(6) : 0
                  width: parent.width
                  text: r.label || ""
                  color: sec ? root.dim : root.urgent
                  font.letterSpacing: sec ? 1.5 : 0
                  wrapMode: Text.WordWrap
                }
              }

              // Six figures, three by two, hairline gaps
              Component {
                id: gridC
                Grid {
                  columns: 3
                  spacing: 1
                  Repeater {
                    model: r.cells
                    Rectangle {
                      required property var modelData
                      width: (parent.width - 2) / 3
                      height: Style.space(44)
                      color: root.lit
                      Column {
                        x: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)
                        Row {
                          spacing: Style.space(3)
                          Label { id: figure; text: modelData.v; color: root.ink; font.pixelSize: Style.font.body }
                          Label { anchors.baseline: figure.baseline; text: modelData.u; color: root.dim }
                        }
                        Label { text: modelData.k; color: root.dim }
                      }
                    }
                  }
                }
              }

              Component { id: gpuC; GpuRow { g: r; height: Style.space(24); inset: 16 } }

              // A label on the left, a value on the right; a secret value is blurred until clicked
              Component {
                id: fieldC
                Item {
                  height: Style.space(28)
                  Label { x: Style.space(16); anchors.verticalCenter: parent.verticalCenter; text: r.label; color: root.dim }
                  Right {
                    margin: 16
                    text: r.secret && !root.revealed ? r.value.replace(/[^.:\/]/g, "•") : r.value + (r.secret ? "  copy" : r.action ? " ›" : "")
                    color: r.plain ? root.fg : root.ink
                  }
                  Click { action: r.action || "" }
                }
              }

              Component {
                id: optC
                Item {
                  height: Style.space(24)
                  Label { x: Style.space(28); anchors.verticalCenter: parent.verticalCenter; text: (r.on ? "● " : "○ ") + r.label; color: r.on ? root.ink : root.fg }
                  Click { action: r.action }
                }
              }

              // Any folder, typed
              Component {
                id: pathC
                Item {
                  height: Style.space(30)
                  Controls.TextField {
                    x: Style.space(28)
                    width: parent.width - Style.space(44)
                    placeholderText: "or type a path"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: Style.font.caption
                    background: Box {}
                    onAccepted: {
                      var path = text.indexOf("~") === 0 ? Quickshell.env("HOME") + text.slice(1) : text
                      root.activate("set|folder|" + path + "|" + r.id)
                    }
                  }
                }
              }

              Component {
                id: actsC
                Row {
                  leftPadding: Style.space(16)
                  topPadding: Style.space(6)
                  spacing: Style.space(8)
                  Repeater {
                    model: r.items
                    Btn {
                      required property var modelData
                      label: modelData.label
                      action: modelData.action
                      primary: !!modelData.primary
                      danger: !!modelData.danger
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  component Label: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.mono
    font.pixelSize: Style.font.caption
  }

  // A hairline frame
  component Box: Rectangle { color: "transparent"; border.width: 1; border.color: root.faint }

  // A label against its row's right edge
  component Right: Label {
    property int margin
    anchors.right: parent.right
    anchors.rightMargin: Style.space(margin)
    anchors.verticalCenter: parent.verticalCenter
  }

  // A whole row, or the item it fills, that runs an action; nothing when the action is ""
  component Click: MouseArea {
    property string action
    anchors.fill: parent
    enabled: action !== ""
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activate(action)
  }

  component Logo: Image {
    property string family
    property int size
    width: Style.space(size)
    height: width
    visible: !!family
    source: family ? Qt.resolvedUrl(family + ".svg") : ""
    sourceSize: Qt.size(Style.space(32), Style.space(32))
    fillMode: Image.PreserveAspectFit
  }

  // One card: a box to tick when there is a choice, its name (and what holds it), memory in use, temperature
  component GpuRow: Item {
    property var g
    property int inset
    readonly property bool box: g.check !== undefined
    width: parent.width
    height: Style.space(36)
    opacity: g.disabled ? 0.45 : 1
    Rectangle {
      visible: parent.box
      x: Style.space(parent.inset)
      width: Style.space(10)
      height: width
      anchors.verticalCenter: parent.verticalCenter
      color: parent.g.check ? root.ink : "transparent"
      border.width: 1
      border.color: root.fg
    }
    Column {
      x: Style.space(parent.inset + (parent.box ? 20 : 0))
      width: Style.space(100)
      anchors.verticalCenter: parent.verticalCenter
      Label { width: parent.width; text: parent.parent.g.name; color: root.ink; elide: Text.ElideRight }
      Label { visible: !!text; text: parent.parent.g.status || ""; color: root.dim; font.pixelSize: Style.font.caption - 2 }
    }
    Rectangle {
      x: Style.space(parent.inset + (parent.box ? 124 : 104))
      width: parent.width - x - Style.space(120)
      height: 3
      anchors.verticalCenter: parent.verticalCenter
      color: root.faint
      Rectangle {
        width: parent.width * parent.parent.g.pct / 100
        height: parent.height
        color: root.fg
        opacity: parent.parent.g.estimate ? 0.5 : 1
      }
    }
    Right { margin: parent.inset; text: parent.g.mem + (parent.g.temp ? "  " + parent.g.temp : ""); color: root.dim }
    Click { action: parent.g.action || "" }
  }

  // Tokens over time, cumulative, rising to the right, a faint fill under it
  component Line: Canvas {
    property var values: []
    onValuesChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var g = getContext("2d"), v = values || [], n = v.length, top = Math.max.apply(null, v.concat([1]))
      g.clearRect(0, 0, width, height)
      if (n < 2 || top <= 1) return
      g.beginPath()
      for (var i = 0; i < n; i++) {
        var x = i / (n - 1) * width, y = height - 4 - v[i] / top * (height * 0.8)
        if (i) g.lineTo(x, y)
        else g.moveTo(x, y)
      }
      g.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
      g.lineWidth = 1.2
      g.stroke()
      g.lineTo(width, height)
      g.lineTo(0, height)
      g.closePath()
      g.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
      g.fill()
    }
  }

  component Btn: Box {
    id: btn
    property string label
    property string action
    property bool primary
    property bool danger
    visible: label !== ""
    implicitWidth: btnText.implicitWidth + Style.space(24)
    implicitHeight: btnText.implicitHeight + Style.space(10)
    color: primary ? root.ink : "transparent"
    border.width: primary ? 0 : 1
    border.color: danger ? Util.alpha(root.urgent, 0.5) : root.faint
    opacity: action === "" ? (primary ? 0.35 : 0.6) : 1
    Label {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? root.bg : btn.danger ? root.urgent : root.fg
    }
    Click { action: btn.action }
  }

  // The top of a model's page: its name above a lit panel (its token line with the scale and dates, or a free
  // kind's cards to tick), and under it on the right what the model is
  component Hero: Column {
    property var h
    spacing: Style.space(10)
    Row {
      leftPadding: Style.space(6)
      topPadding: Style.space(6)
      spacing: Style.space(10)
      Logo { family: h.family; size: 20; anchors.verticalCenter: parent.verticalCenter }
      Label { text: h.name; color: root.ink; font.pixelSize: Style.font.title }
    }
    Rectangle {
      width: parent.width
      height: h.gpus ? h.gpus.length * Style.space(36) + Style.space(12) : Style.space(110)
      color: root.lit
      clip: true
      // The same token line as on home, edge to edge, with its numbers over it
      Item {
        anchors.fill: parent
        visible: !h.gpus
        Line { anchors.fill: parent; values: h.line || [] }
        Label { x: Style.space(8); y: Style.space(6); text: h.top || ""; color: root.dim }
        Label { x: Style.space(8); y: parent.height / 2 - Style.space(10); text: h.mid || ""; color: root.dim }
        Label { x: Style.space(8); y: parent.height - Style.space(22) - height; text: "0"; color: root.dim }
        Label { x: Style.space(8); y: parent.height - Style.space(3) - height; text: h.since || ""; color: root.dim }
        Label { x: parent.width - Style.space(12) - width; y: parent.height - Style.space(3) - height; text: h.now || ""; color: root.dim }
      }
      Column {
        y: Style.space(6)
        width: parent.width
        visible: !!h.gpus
        Repeater {
          model: h.gpus || []
          GpuRow { required property var modelData; g: modelData; inset: 14 }
        }
      }
    }
    Item {
      width: parent.width
      height: sub.implicitHeight + (h.caps.length ? chips.implicitHeight + Style.space(6) : 0)
      Label { id: sub; anchors.right: parent.right; text: h.sub }
      Flow {
        id: chips
        anchors.right: parent.right
        anchors.top: sub.bottom
        anchors.topMargin: Style.space(6)
        width: parent.width
        layoutDirection: Qt.RightToLeft
        spacing: Style.space(6)
        Repeater {
          model: h.caps
          Box {
            required property var modelData
            width: chip.implicitWidth + Style.space(12)
            height: chip.implicitHeight + Style.space(4)
            Label { id: chip; anchors.centerIn: parent; text: modelData }
          }
        }
      }
    }
  }
}
