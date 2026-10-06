import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Local AI: one line per GPU, model or build; hover a line for its drawer (Run · config, Open · stop · ⋯).
// Model.js turns the backend's snapshot into a list of items; this file draws them and runs the backend's verbs.
// Errors go to the desktop's notifications, never into the panel.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // the URL keeps a "%", "#" or "?" in the plugin's path encoded
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-local-ai")).replace(/^file:\/\//, ""))
  readonly property string keyFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/local-ai/gateway.key"
  readonly property color theme: bar ? bar.foreground : Color.foreground
  readonly property color dotTone: bar && bar.barForeground !== undefined ? bar.barForeground : theme
  readonly property color bg: Color.popups.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string mono: bar ? bar.fontFamily : Style.font.family
  readonly property var tones: Model.tones(theme, bg, Util.alpha(theme, 0.06))
  function tone(t) { return Qt.rgba(tones[t].r, tones[t].g, tones[t].b, 1) }
  readonly property color ink: tone("ink")
  readonly property color valueTone: tone("value")
  readonly property color labelTone: tone("label")
  readonly property color dimTone: tone("dim")
  readonly property color ruleTone: tone("rule")
  readonly property color drawerTone: Util.alpha(theme, 0.08)

  // One grid and one gap: every line starts and ends on the gutter, and every item carries half the gap above and
  // below it, so the clear space between any two things is the same.
  readonly property int gutter: Style.space(24)
  readonly property int gap: Style.space(28)
  readonly property int lineH: Style.space(38)
  readonly property int drawerW: Style.space(166)
  // lab and card marks shipped in logos/, drawn in the line's own tone
  readonly property var logos: ["deepseek", "gemma", "glm", "hf", "hunyuan", "kimi", "laguna", "lfm", "mimo", "minimax", "mistral", "muse", "nemotron", "qwen", "step", "nvidia-hw", "intel-hw", "amd-hw"]

  property var snap: ({})
  property var ui: ({ tab: "gpus", view: "", id: "", open: "", picks: {}, registryBusy: false })
  property bool reachable: true
  property var queue: []
  property bool again: false
  readonly property var view: {
    try { return Model.build(snap, ui) } catch (e) { return { mark: "failed", items: [] } }
  }

  // ---------------------------------------------------------------- navigation and verbs

  function nav(patch) { ui = Object.assign({}, ui, { open: "" }, patch); flick.contentY = 0 }
  function back() { nav(ui.view === "agent" || ui.view === "folder" || ui.view === "share" ? { view: "more" } : { view: "", id: "" }) }
  function run(args) { queue.push(args); if (!verb.running) next() }
  function next() {
    if (!queue.length) return refresh()
    var args = queue.shift()
    verb.operation = args[0]
    verb.command = (args[0] === "setup" ? [cli] : ["timeout", "--kill-after=5", "120", cli]).concat(args)
    verb.running = true
  }
  function refresh() { if (poll.running) again = true; else poll.running = true }
  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Local AI", "-g", "󰧑", "-u", "normal", title, body || "", "--exec", cli, "log"])
  }
  function terminal(cmd) { Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", cmd]); root.close() }

  // An action is "verb|arg|arg", from Model.js
  function activate(action) {
    var a = (action || "").split("|")
    switch (a[0]) {
    case "tab": nav({ tab: a[1], view: "", id: "" }); break
    case "back": back(); break
    case "config": nav({ view: "config", id: a[1] }); break
    case "more": nav({ view: "more", id: a[1] }); break
    case "go": nav({ view: a[1], id: a[2] }); break
    case "pick": var p = Object.assign({}, ui.picks); p[a[1]] = a[2]; ui = Object.assign({}, ui, { picks: p }); break
    case "run": run(["run", a[1], a[2]]); nav({ tab: "gpus", view: "", id: "" }); break
    case "again": run(["stop", a[1]]); run(["run", a[1], a[2]]); break
    case "stop": run(["stop", a[1]]); nav({ view: "", id: "" }); break
    case "open": run(["open", a[1]]); break
    case "share": run(["share", a[1]].concat(a[2] ? [a[2]] : [])); if (a[2]) nav({ view: "more" }); break
    case "set": run(["set", a[1], decodeURIComponent(a[2]), a[3]]); back(); break
    case "default": run(["set", "agent", a[1]]); break
    case "forget": run(["forget", a[1]]); break
    case "registry": ui = Object.assign({}, ui, { registryBusy: true }); run(["registry"]); break
    case "setup": run(["setup"]); break
    case "docker": terminal("sudo systemctl start docker"); break
    case "omarchy-update": terminal("omarchy-update"); break
    case "folder":
      folderDialog.recipe = a[1]
      folderDialog.currentFolder = "file://" + encodeURI(decodeURIComponent(a[2]) || Quickshell.env("HOME")).replace(/#/g, "%23").replace(/\?/g, "%3F")
      root.close()
      Qt.callLater(function() { folderDialog.open() })
      break
    case "log": Quickshell.execDetached([cli, "log"]); root.close(); break
    case "url": Quickshell.execDetached(["omarchy-launch-browser", a[1]]); root.close(); break
    case "copy": copy.command = ["wl-copy", a[1]]; copy.running = true; break
    case "copykey": copy.command = ["bash", "-c", "wl-copy < \"$1\"", "_", keyFile]; copy.running = true; break
    }
  }

  // A snapshot the panel cannot read keeps the last one; losing the backend, and anything that newly went wrong
  // in it, is said once in a notification
  function polled(code, text) {
    var s = code === 0 ? Model.parse(text) : null
    var ok = !!s && Array.isArray(s.gpus) && Array.isArray(s.kinds) && Array.isArray(s.deployments)
    if (ok) {
      if (snap.gpus) Model.problems(snap, s).forEach(function(p) { notify(p.title, p.body) })
      snap = s
    } else if (reachable) notify("Can't reach Local AI", "The panel keeps trying.")
    reachable = ok
  }
  Process {
    id: poll
    command: ["timeout", "--kill-after=5", "90", root.cli, "snapshot"]
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    onExited: function(code) { root.polled(code, pollOut.text); if (root.again) { root.again = false; Qt.callLater(root.refresh) } }
  }
  // A verb that fails says why on its last "local-ai:" line, and that goes to a notification
  function finished(code, operation, output, error) {
    ui = Object.assign({}, ui, { registryBusy: false })
    if (code !== 0) {
      var m = (error || "").split("\n").filter(function(l) { return l.indexOf("local-ai: ") === 0 }).pop()
      queue = []
      notify("Couldn't " + ({ run: "start the model", stop: "stop the model", open: "open the agent", share: "change the share",
        set: "change that", forget: "remove the download", registry: "refresh models", setup: "set up Local AI" })[operation] || operation,
        code === 124 || code === 137 ? "That took too long; try again." : m ? m.slice(10) : "See the log.")
    } else if (operation === "open") root.close()
    else if (operation === "registry") notify("Models refreshed", output.trim())
    next()
  }
  Process {
    id: verb
    property string operation: ""
    stdout: StdioCollector { id: verbOut; waitForEnd: true }
    stderr: StdioCollector { id: verbErr; waitForEnd: true }
    onExited: function(code) { root.finished(code, operation, verbOut.text, verbErr.text) }
  }
  FolderDialog {
    id: folderDialog
    property string recipe: ""
    title: "Choose the agent's folder"
    onAccepted: { root.run(["set", "folder", decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, "")), recipe]); root.open() }
    onRejected: root.open()
  }
  Process { id: copy }
  Timer {
    interval: root.view.mark === "busy" ? (root.opened ? 1500 : 5000) : root.opened ? 5000 : 30000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }
  onOpenedChanged: if (opened) { refresh(); nav({ view: "", id: "" }) }

  // ---------------------------------------------------------------- the bar mark

  // Nine dots: faint when idle, lit when a model is ready, urgent when one stopped, a diagonal ripple while working
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
              color: root.view.mark === "failed" ? root.urgent : on ? root.dotTone : Util.alpha(root.dotTone, 0.3)
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the panel

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
      Keys.onEscapePressed: root.ui.view ? root.back() : root.close()

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
          topPadding: Style.space(6)
          bottomPadding: root.gap / 2

          Repeater {
            // keyed by position, so a refresh updates items in place instead of rebuilding them
            model: (root.view.items || []).length
            Loader {
              required property int index
              readonly property var r: (root.view.items || [])[index] || ({ type: "" })
              width: content.width
              sourceComponent: ({ tabs: tabsC, top: topC, bars: barsC, note: noteC, line: lineC, msg: msgC, back: backC, pick: lineC,
                kv: kvC, opt: optC, links: linksC, button: buttonC, field: fieldC })[r.type] || null
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- items

  // home · gpus; a page under gpus keeps gpus underlined
  Component {
    id: tabsC
    Item {
      readonly property var rr: parent.r
      height: Style.space(40)
      Row {
        x: root.gutter
        y: Style.space(18)
        spacing: Style.space(26)
        Repeater {
          model: ["home", "gpus"]
          Label {
            required property string modelData
            readonly property bool on: rr.on === modelData
            text: modelData
            color: on ? root.ink : root.labelTone
            Rectangle { visible: parent.on; y: parent.height + Style.space(4); width: parent.width; height: 1.5; color: root.ink }
            Click { action: "tab|" + modelData }
          }
        }
      }
    }
  }

  // tokens generated, then its cumulative line under it
  Component {
    id: topC
    Item {
      readonly property var rr: parent.r
      height: topCol.implicitHeight + root.gap
      Column {
        id: topCol
        x: root.gutter
        y: root.gap / 2
        width: parent.width - 2 * root.gutter
        spacing: Style.space(10)
        Row {
          spacing: Style.space(8)
          Label { id: tokens; text: rr.tokens; color: root.ink; font.pixelSize: Style.space(24) }
          Label { anchors.baseline: tokens.baseline; text: "tokens generated"; color: root.labelTone }
        }
        Line { width: parent.width; height: Style.space(rr.h || 44); values: rr.line || [] }
      }
    }
  }

  // a bar per day; hovering one says its date and tokens, the last day is said otherwise
  Component {
    id: barsC
    Item {
      id: barsItem
      property var rr: parent.r
      property int hover: -1
      readonly property var values: rr.values || []
      readonly property real peak: Math.max.apply(null, values.concat([1]))
      height: Style.space(64) + Style.space(30) + root.gap / 2
      Row {
        x: root.gutter
        width: parent.width - 2 * root.gutter
        height: Style.space(64)
        Repeater {
          model: barsItem.values.length
          Item {
            required property int index
            width: parent.width / barsItem.values.length
            height: parent.height
            Rectangle {
              x: 1
              width: Math.max(1, parent.width - 3)
              height: barsItem.values[index] / barsItem.peak * parent.height
              anchors.bottom: parent.bottom
              color: index === barsItem.hover || barsItem.hover < 0 && index === barsItem.values.length - 1 ? root.ink : root.ruleTone
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: barsItem.hover = index; onExited: if (barsItem.hover === index) barsItem.hover = -1 }
          }
        }
      }
      Rectangle { x: root.gutter; y: Style.space(64); width: parent.width - 2 * root.gutter; height: 1; color: root.ruleTone }
      Label {
        x: root.gutter
        y: Style.space(64) + Style.space(10)
        text: (barsItem.rr.labels || [])[barsItem.hover >= 0 ? barsItem.hover : barsItem.values.length - 1] || ""
        color: root.labelTone
        font.pixelSize: Style.font.caption - 1
      }
    }
  }

  Component {
    id: noteC
    Item {
      height: noteText.implicitHeight + root.gap / 2
      readonly property var rr: parent.r
      Label { id: noteText; x: root.gutter; y: root.gap / 2; text: rr.text; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
    }
  }

  // A line: a mark, a name, on the right what it is doing; hovering slides its drawer in from the right, one button
  // and quiet links. A free line names, while hovered, the model its Run starts. A config pick is the same line.
  Component {
    id: lineC
    Item {
      id: line
      readonly property var rr: parent.r
      readonly property bool pick: rr.type === "pick"
      readonly property bool open: !!rr.drawer && (hov.hovered || root.ui.open === rr.id)
      readonly property var shown: open && rr.next ? rr.next : rr
      readonly property color tone: rr.dim || rr.off ? root.dimTone : open || rr.on ? root.ink : rr.quiet ? root.labelTone : root.valueTone
      height: root.lineH + (pick && rr.note ? Style.space(14) : 0) + (rr.progress >= 0 ? Style.space(4) : 0)
      HoverHandler { id: hov }
      Click { action: line.pick ? line.rr.action || "" : "" }
      TapHandler { enabled: !!line.rr.drawer && !line.pick; onTapped: root.ui = Object.assign({}, root.ui, { open: root.ui.open === line.rr.id ? "" : line.rr.id }) }
      Rectangle { visible: !!rr.on; x: root.gutter - Style.space(12); y: root.lineH / 2 - 2; width: 4; height: 4; radius: 2; color: root.ink }
      Mark { id: mk; x: root.gutter; y: (root.lineH - height) / 2; logo: line.shown.logo || ({}); tone: line.tone }
      Label {
        x: root.gutter + Style.space(22)
        width: (line.open ? parent.width - root.drawerW - Style.space(8) : info.x - Style.space(10)) - x
        anchors.verticalCenter: mk.verticalCenter
        elide: Text.ElideRight
        text: line.shown.name || ""
        color: line.tone
      }
      Label {
        visible: line.pick && !!line.rr.note
        x: root.gutter + Style.space(22)
        y: root.lineH / 2 + Style.space(8)
        text: line.rr.note || ""
        color: line.rr.off ? root.dimTone : root.labelTone
        font.pixelSize: Style.font.caption - 1
      }
      Label {
        id: info
        visible: !line.open
        anchors.right: parent.right
        anchors.rightMargin: root.gutter
        anchors.verticalCenter: mk.verticalCenter
        text: line.rr.info || ""
        color: line.rr.dim ? root.dimTone : root.labelTone
      }
      Rectangle {
        visible: line.rr.progress >= 0
        x: root.gutter; y: root.lineH / 2 + Style.space(12)
        width: parent.width - 2 * root.gutter; height: 2; color: root.ruleTone
        Rectangle { width: parent.width * (line.rr.progress || 0) / 100; height: 2; color: root.ink }
      }
      // the drawer: a sliver with a fold at rest, the full width while open
      Rectangle {
        visible: !!line.rr.drawer
        x: parent.width - (line.open ? root.drawerW : Style.space(5))
        y: root.lineH / 2 - Style.space(15)
        width: root.drawerW
        height: Style.space(30)
        radius: Style.space(4)
        color: root.drawerTone
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Rectangle { width: 1; height: parent.height; color: Util.alpha(root.theme, 0.16) }
        Row {
          visible: line.open
          x: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)
          Repeater {
            model: line.rr.drawer || []
            Item {
              required property var modelData
              required property int index
              width: index === 0 ? Style.space(70) : quiet.implicitWidth
              height: Style.space(26)
              visible: !!modelData
              Btn { visible: index === 0; anchors.fill: parent; label: modelData ? modelData.label : ""; action: modelData ? modelData.action : "" }
              Label { id: quiet; visible: index > 0; anchors.verticalCenter: parent.verticalCenter; text: modelData ? modelData.label : ""; color: root.labelTone
                Click { action: modelData ? modelData.action : "" } }
            }
          }
        }
      }
    }
  }

  // A heading, its sentence, and the one button
  Component {
    id: msgC
    Item {
    readonly property var rr: parent.r
    height: msgCol.implicitHeight
    Column {
      id: msgCol
      x: root.gutter
      width: parent.width - 2 * root.gutter
      topPadding: root.gap / 2
      bottomPadding: root.gap / 2
      spacing: Style.space(6)
      Label { width: parent.width; text: rr.head; color: root.ink; font.pixelSize: Style.font.body + 2; wrapMode: Text.WordWrap }
      Repeater { model: rr.lines || []; Label { required property string modelData; width: msgCol.width; wrapMode: Text.WordWrap; text: modelData; color: root.labelTone } }
      Item { width: 1; height: rr.button ? root.gap - Style.space(6) : 0 }
      Btn { visible: !!rr.button; label: rr.button ? rr.button.label : ""; action: rr.button ? rr.button.action : "" }
    }
    }
  }

  // ‹ where you came from, and what this page is about
  Component {
    id: backC
    Item {
      readonly property var rr: parent.r
      height: Style.space(20) + root.gap
      Row {
        x: root.gutter
        y: root.gap / 2
        spacing: Style.space(10)
        Label { id: backLabel; width: Math.min(implicitWidth, (content.width - 2 * root.gutter) * 0.7); elide: Text.ElideRight
          text: "‹ " + rr.label; color: root.ink; font.pixelSize: Style.font.body + 1 }
        Label { anchors.baseline: backLabel.baseline; width: Math.max(0, content.width - 2 * root.gutter - backLabel.width - Style.space(10)); elide: Text.ElideRight
          text: rr.sub || ""; color: root.labelTone }
      }
      Click { action: "back" }
    }
  }

  Component {
    id: kvC
    Item {
      readonly property var rr: parent.r
      height: root.lineH
      Label { x: root.gutter; anchors.verticalCenter: parent.verticalCenter; text: rr.k; color: root.labelTone }
      Label { anchors.right: parent.right; anchors.rightMargin: root.gutter; anchors.verticalCenter: parent.verticalCenter; text: rr.v; color: root.valueTone }
      Click { action: rr.action || "" }
    }
  }

  // a choice in a list: an agent (its mark in the line's tone) or a folder; the chosen one dotted
  Component {
    id: optC
    Item {
      readonly property var rr: parent.r
      height: root.lineH
      Rectangle { visible: !!rr.on; x: root.gutter - Style.space(12); anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: root.ink }
      Mark { id: optMark; visible: !!rr.agent; x: root.gutter; anchors.verticalCenter: parent.verticalCenter; agent: rr.agent || ""; tone: rr.on ? root.ink : root.valueTone }
      Label { x: root.gutter + (rr.agent ? Style.space(24) : 0); width: parent.width - x - root.gutter - Style.space(60); elide: Text.ElideMiddle; anchors.verticalCenter: parent.verticalCenter; text: rr.name
        color: rr.on ? root.ink : rr.quiet ? root.labelTone : root.valueTone }
      Label { anchors.right: parent.right; anchors.rightMargin: root.gutter; anchors.verticalCenter: parent.verticalCenter; text: rr.note || ""; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
      Click { action: rr.action || "" }
    }
  }

  Component {
    id: linksC
    Item {
      readonly property var rr: parent.r
      height: root.lineH
      Row {
        x: root.gutter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(16)
        Repeater {
          model: rr.items || []
          Label { required property var modelData; text: modelData.label; color: root.labelTone; Click { action: modelData.action } }
        }
      }
    }
  }

  Component {
    id: buttonC
    Item {
      readonly property var rr: parent.r
      height: Style.space(30) + root.gap
      Btn { x: root.gutter; y: root.gap / 2; label: rr.label; action: rr.action || "" }
      Label { visible: !!rr.right; anchors.right: parent.right; anchors.rightMargin: root.gutter; y: root.gap / 2 + Style.space(8)
        text: rr.right ? rr.right.label : ""; color: root.labelTone; font.pixelSize: Style.font.caption - 1
        Click { action: rr.right ? rr.right.action : "" } }
    }
  }

  // a value, and under it what it is with its links
  Component {
    id: fieldC
    Item {
      readonly property var rr: parent.r
      height: fieldCol.implicitHeight
      Column {
        id: fieldCol
        x: root.gutter
        topPadding: root.gap / 2
        bottomPadding: root.gap / 2
        spacing: Style.space(6)
        Label { text: rr.value; color: root.ink }
        Repeater { model: rr.links || []; Label { required property var modelData; text: modelData.label; color: root.labelTone; font.pixelSize: Style.font.caption - 1; Click { action: modelData.action } } }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  component Label: Text {
    textFormat: Text.PlainText
    color: root.valueTone
    font.family: root.mono
    font.pixelSize: Style.font.caption
  }

  component Click: MouseArea {
    property string action
    anchors.fill: parent
    enabled: action !== ""
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activate(action)
  }

  // A lab's, a card maker's or an agent's mark: a lab's or a card maker's in the line's tone, an agent's in black and
  // white, both by rewriting the SVG's colours (no shader, so any renderer draws it). The CPU is a chip glyph; a mark
  // not shipped is its initial.
  component Mark: Item {
    id: m
    property var logo: ({})
    property string agent: ""
    property color tone: root.valueTone
    readonly property string file: agent ? (["claude", "codex", "omp", "opencode", "hermes", "copilot", "crush"].indexOf(agent) >= 0 ? "agents/" + agent + (agent === "crush" ? ".png" : ".svg") : "")
      : logo.kind === "hw" ? (logo.name === "cpu" ? "" : "logos/" + logo.name + "-hw.svg")
      : root.logos.indexOf(logo.name) >= 0 ? "logos/" + logo.name + ".svg" : ""
    property string svg: ""
    width: Style.space(agent ? 16 : 14)
    height: width
    FileView {
      id: fv
      path: m.file && m.file.endsWith(".svg") ? decodeURIComponent(String(Qt.resolvedUrl(m.file)).replace(/^file:\/\//, "")) : ""
      blockLoading: true
      onLoaded: m.svg = text()
    }
    Image {
      id: img
      anchors.fill: parent
      sourceSize: Qt.size(64, 64)
      fillMode: Image.PreserveAspectFit
      opacity: m.agent ? 0.9 : 1
      source: !m.file ? "" : m.file.endsWith(".png") ? Qt.resolvedUrl(m.file) : !m.svg ? ""
        : "data:image/svg+xml;utf8," + encodeURIComponent(m.agent ? Model.grayscale(m.svg) : Model.mono(m.svg, String(m.tone)))
    }
    Label {
      anchors.centerIn: parent
      visible: img.status !== Image.Ready
      text: m.agent === "pi" ? "π" : m.agent === "grok" ? "𝕏" : m.logo.name === "cpu" ? "󰘚" : String(m.logo.name || m.agent || "?").charAt(0).toUpperCase()
      color: m.tone
      font.pixelSize: m.logo.name === "cpu" ? Style.space(15) : Style.font.caption - 1
    }
  }

  // Tokens over time, cumulative: a line over a faint area
  component Line: Canvas {
    property var values: []
    onValuesChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var g = getContext("2d"), v = values || [], n = v.length, top = Math.max.apply(null, v.concat([1]))
      g.clearRect(0, 0, width, height)
      if (n < 2) return
      g.beginPath()
      for (var i = 0; i < n; i++) {
        var x = i / (n - 1) * width, y = height - 1 - v[i] / top * (height * 0.92)
        if (i) g.lineTo(x, y)
        else g.moveTo(x, y)
      }
      g.strokeStyle = root.valueTone
      g.lineWidth = 1.4
      g.stroke()
      g.lineTo(width, height)
      g.lineTo(0, height)
      g.closePath()
      g.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
      g.fill()
    }
  }

  // the one solid button
  component Btn: Rectangle {
    id: btn
    property string label
    property string action
    visible: label !== ""
    implicitWidth: btnText.implicitWidth + Style.space(28)
    implicitHeight: Style.space(30)
    radius: Style.space(3)
    color: root.ink
    opacity: action === "" ? 0.4 : 1
    Label { id: btnText; anchors.centerIn: parent; text: btn.label; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 1) }
    Click { action: btn.action }
  }
}
