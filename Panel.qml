import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Local AI. A header band (tabs, tokens generated, the line) and a footer band (the machine, logs · refresh) around a
// body that keeps its height: home launches what runs and shows usage; gpus is one row per model, card and build, and
// every row opens in place with its buttons. Model.js turns the backend's snapshot into the view; this file draws it
// and runs the backend's verbs. Errors go to the desktop's notifications, never into the panel.
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
  readonly property color band: Util.alpha(theme, 0.045)
  readonly property color edge: Util.alpha(theme, 0.09)
  readonly property color raised: Util.alpha(theme, 0.035)

  readonly property int gutter: Style.space(24)
  readonly property int headH: Style.space(156)
  readonly property int footH: Style.space(44)
  // the body keeps the tallest height it has had since the panel opened, so the footer never jumps up
  property real bodyH: Style.space(320)
  readonly property var logos: ["deepseek", "gemma", "glm", "hf", "hunyuan", "kimi", "laguna", "lfm", "mimo", "minimax", "mistral", "muse", "nemotron", "qwen", "step"]

  property var snap: ({})
  property var ui: ({ tab: "gpus", view: "", id: "", open: "", picks: {}, registryBusy: false })
  property bool reachable: true
  property var queue: []
  property bool again: false
  readonly property var view: {
    try { return Model.build(snap, ui) } catch (e) { return { mark: "failed", items: [], header: {}, footer: "" } }
  }

  // ---------------------------------------------------------------- navigation and verbs

  function nav(patch) { ui = Object.assign({}, ui, patch); flick.contentY = 0 }
  function back() { nav(ui.view === "agent" || ui.view === "folder" || ui.view === "share" || ui.view === "model" ? { view: "", id: "" } : { view: "", id: "", open: "" }) }
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
    case "tab": nav({ tab: a[1], view: "", id: "", open: "" }); break
    case "full": ui = Object.assign({}, ui, { full: a[1] === "on", view: "", id: "" }); if (a[1] === "on") root.close(); break
    case "toggle": ui = Object.assign({}, ui, { open: ui.open === a[1] ? "" : a[1] }); break
    case "back": back(); break
    case "go": nav({ view: a[1], id: a[2] }); break
    case "pick": var p = Object.assign({}, ui.picks); p[a[1]] = a[2]; ui = Object.assign({}, ui, { picks: p }); break
    case "run": run(["run", a[1], a[2]]); nav({ tab: "gpus", view: "", id: "", open: "" }); break
    case "again": run(["stop", a[1]]); run(["run", a[1], a[2]]); break
    case "switch": run(["stop", a[1]]); run(["run", a[2], a[3]]); nav({ tab: "gpus", view: "", id: "", open: "" }); break
    case "stop": run(["stop", a[1]]); ui = Object.assign({}, ui, { open: "" }); break
    case "open": run(["open", a[1]]); break
    case "share": run(["share", a[1]].concat(a[2] ? [a[2]] : [])); if (a[2]) back(); break
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
  onOpenedChanged: if (opened) { refresh(); bodyH = Style.space(320); nav({ view: "", id: "", open: "" }) }

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
    contentHeight: panel.fittedContentHeight(root.headH + root.bodyH + root.footH)

    Rectangle { anchors.fill: parent; color: root.bg }
    Item {
      id: keys
      objectName: "local-ai-panel"
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.ui.view || root.ui.open ? root.back() : root.close()

      // the header band: tabs, tokens generated, today, the line
      Rectangle {
        id: head
        width: parent.width
        height: root.headH
        color: root.band
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.edge }
        Row {
          x: root.gutter
          y: Style.space(18)
          spacing: Style.space(26)
          Repeater {
            model: ["home", "gpus"]
            Label {
              required property string modelData
              readonly property bool on: root.view.tab === modelData
              text: modelData
              color: on ? root.ink : root.labelTone
              font.pixelSize: Style.font.caption + 1
              Rectangle { visible: parent.on; y: parent.height + Style.space(4); width: parent.width; height: 1.5; color: root.ink }
              Click { action: "tab|" + modelData }
            }
          }
        }
        Row {
          x: root.gutter
          y: Style.space(56)
          spacing: Style.space(8)
          Label { id: total; text: (root.view.header || {}).empty ? "0" : (root.view.header || {}).tokens || ""; color: (root.view.header || {}).empty ? root.labelTone : root.ink; font.pixelSize: Style.space(26) }
          Label { anchors.baseline: total.baseline; text: "tokens generated"; color: root.labelTone }
        }
        Label { anchors.right: parent.right; anchors.rightMargin: root.gutter; y: Style.space(16); text: "󰊓"; color: root.labelTone; font.pixelSize: Style.font.body + 1; Click { action: "full|on" } }
        Label { anchors.right: parent.right; anchors.rightMargin: root.gutter; y: Style.space(66); text: (root.view.header || {}).today || ""; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
        Line { x: root.gutter; y: Style.space(96); width: parent.width - 2 * root.gutter; height: Style.space(44); values: (root.view.header || {}).line || [] }
      }

      Flickable {
        id: flick
        y: root.headH
        width: parent.width
        height: root.bodyH
        contentHeight: content.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          objectName: "local-ai-content"
          width: flick.width
          topPadding: Style.space(6)
          bottomPadding: Style.space(14)
          onImplicitHeightChanged: root.bodyH = Math.min(Style.space(600), Math.max(root.bodyH, implicitHeight))

          Repeater {
            // keyed by position, so a refresh updates items in place instead of rebuilding them
            model: (root.view.items || []).length
            Loader {
              required property int index
              readonly property var r: (root.view.items || [])[index] || ({ type: "" })
              width: content.width
              sourceComponent: ({ msg: msgC, note: noteC, row: rowC, rule: ruleC, launch: launchC, tiers: tiersC, calendar: calendarC,
                back: backC, list: listC, opt: optC, links: linksC, button: buttonC, field: fieldC })[r.type] || null
            }
          }
        }
      }

      // the footer band: the machine in one line, and the quiet doors
      Rectangle {
        y: root.headH + root.bodyH
        width: parent.width
        height: root.footH
        color: root.band
        Rectangle { width: parent.width; height: 1; color: root.edge }
        Label { x: root.gutter; anchors.verticalCenter: parent.verticalCenter; text: root.view.footer || ""; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: root.gutter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)
          Label { text: "logs"; color: root.labelTone; font.pixelSize: Style.font.caption - 1; Click { action: "log" } }
          Label { text: root.ui.registryBusy ? "refreshing…" : "refresh"; color: root.labelTone; font.pixelSize: Style.font.caption - 1; Click { action: root.ui.registryBusy ? "" : "registry" } }
        }
      }
    }
  }

  // ---------------------------------------------------------------- full screen

  // The same panel, wider: the header carries the tiers, gpus is every row opened as a tile, home is launch and a year.
  FloatingWindow {
    id: fullWin
    visible: !!root.ui.full
    implicitWidth: Style.space(1280)
    implicitHeight: Style.space(800)
    color: root.bg
    title: "Local AI"
    onVisibleChanged: if (!visible && root.ui.full) root.ui = Object.assign({}, root.ui, { full: false })
    readonly property var f: root.view.full || ({})
    Item {
      objectName: "local-ai-full"
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.activate("full|off")
      Rectangle {
        id: fhead
        width: parent.width
        height: Style.space(220)
        color: root.band
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.edge }
        Label { x: Style.space(40); y: Style.space(28); text: "Local AI"; color: root.ink; font.pixelSize: Style.font.body + 2 }
        Row {
          x: Style.space(170); y: Style.space(30)
          spacing: Style.space(26)
          Repeater {
            model: ["home", "gpus"]
            Label {
              required property string modelData
              readonly property bool on: root.view.tab === modelData
              text: modelData
              color: on ? root.ink : root.labelTone
              font.pixelSize: Style.font.caption + 1
              Rectangle { visible: parent.on; y: parent.height + Style.space(4); width: parent.width; height: 1.5; color: root.ink }
              Click { action: "tab|" + modelData }
            }
          }
        }
        Label { anchors.right: parent.right; anchors.rightMargin: Style.space(40); y: Style.space(28); text: "󰊔  esc"; color: root.labelTone; Click { action: "full|off" } }
        Row {
          x: Style.space(40); y: Style.space(70)
          spacing: Style.space(12)
          Label { id: ftotal; text: (root.view.header || {}).tokens || "0"; color: root.ink; font.pixelSize: Style.space(40) }
          Label { anchors.baseline: ftotal.baseline; text: "tokens generated"; color: root.labelTone; font.pixelSize: Style.font.body }
        }
        Line { x: Style.space(40); y: Style.space(130); width: Style.space(760); height: Style.space(70); values: (root.view.header || {}).line || [] }
        Grid {
          x: Style.space(860); y: Style.space(72)
          columns: 3
          columnSpacing: Style.space(40)
          rowSpacing: Style.space(22)
          Repeater {
            model: fullWin.f.tiers ? fullWin.f.tiers.cells : []
            Column {
              required property var modelData
              required property int index
              Label { text: modelData[0]; color: index === 0 ? root.ink : root.valueTone; font.pixelSize: Style.space(22) }
              Label { text: modelData[1]; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
            }
          }
        }
      }
      Flickable {
        y: fhead.height
        width: parent.width
        height: parent.height - fhead.height - Style.space(52)
        contentHeight: fbody.implicitHeight + Style.space(40)
        clip: true
        Flow {
          id: fbody
          x: Style.space(40); y: Style.space(30)
          width: parent.width - Style.space(80)
          spacing: Style.space(20)
          // gpus: a tile per row, opened
          Repeater {
            model: fullWin.f.tiles || []
            Rectangle {
              required property var modelData
              width: Style.space(380)
              height: tileRow.height + Style.space(8)
              radius: Style.space(6)
              color: root.band
              border.width: 1
              border.color: root.edge
              Loader { id: tileRow; y: Style.space(4); width: parent.width; property var r: modelData; sourceComponent: rowC }
            }
          }
          // home: launch, then the year
          Column {
            visible: !fullWin.f.tiles
            width: Style.space(420)
            Repeater {
              model: fullWin.f.items || []
              Loader { required property var modelData; width: parent.width; property var r: modelData; sourceComponent: ({ note: noteC, launch: launchC, msg: msgC, row: rowC })[modelData.type] || null }
            }
          }
          Loader { visible: !fullWin.f.tiles && !!fullWin.f.calendar; property var r: fullWin.f.calendar || ({}); width: Style.space(700); sourceComponent: fullWin.f.calendar ? calendarC : null }
        }
      }
      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: Style.space(52)
        color: root.band
        Rectangle { width: parent.width; height: 1; color: root.edge }
        Label { x: Style.space(40); anchors.verticalCenter: parent.verticalCenter; text: (root.view.footer || "") + "  ·  Local AI " + (root.snap.version || ""); color: root.labelTone }
        Row {
          anchors.right: parent.right; anchors.rightMargin: Style.space(40); anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)
          Label { text: "logs"; color: root.labelTone; Click { action: "log" } }
          Label { text: root.ui.registryBusy ? "refreshing…" : "refresh models"; color: root.labelTone; Click { action: root.ui.registryBusy ? "" : "registry" } }
        }
      }
    }
  }

  // ---------------------------------------------------------------- items

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
        topPadding: Style.space(26)
        bottomPadding: Style.space(14)
        spacing: Style.space(8)
        Label { width: parent.width; text: rr.head; color: root.ink; font.pixelSize: Style.font.body + 2; wrapMode: Text.WordWrap }
        Repeater { model: rr.lines || []; Label { required property string modelData; width: msgCol.width; wrapMode: Text.WordWrap; text: modelData; color: root.labelTone } }
        Item { width: 1; height: rr.button ? Style.space(6) : 0 }
        Btn { visible: !!rr.button; label: rr.button ? rr.button.label : ""; action: rr.button ? rr.button.action : "" }
      }
    }
  }

  Component {
    id: noteC
    Item {
      readonly property var rr: parent.r
      height: Style.space(30)
      Label { x: root.gutter; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(4); text: rr.text; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
    }
  }

  Component { id: ruleC; Item { height: Style.space(10); Rectangle { x: root.gutter; y: Style.space(5); width: parent.width - 2 * root.gutter; height: 1; color: root.ruleTone } } }

  // A row: the mark, the name, what it is doing on the right and ⌄; the card's facts and a memory bar under it. Click
  // opens it in place, on a raised surface, with what it holds and its buttons.
  Component {
    id: rowC
    Item {
      id: row
      readonly property var rr: parent.r
      readonly property var d: rr.detail || null
      readonly property bool open: !!rr.open && !!d
      readonly property color tone: rr.dim ? root.dimTone : rr.quiet ? root.labelTone : rr.mark && rr.mark.kind === "lab" ? root.ink : root.valueTone
      height: Style.space(62) + (open ? detail.implicitHeight + Style.space(8) : 0)
      Rectangle {
        visible: row.open
        x: Style.space(8); y: Style.space(2)
        width: parent.width - Style.space(16); height: parent.height - Style.space(4)
        radius: Style.space(6)
        color: root.raised
        border.width: 1
        border.color: root.edge
      }
      Click { height: Style.space(62); action: row.d ? "toggle|" + rr.id : "" }
      Mark { id: mk; x: root.gutter; y: Style.space(13); logo: rr.mark || ({}); tone: row.tone }
      Label {
        id: rowName
        x: root.gutter + Style.space(24)
        width: Math.min(implicitWidth, rowRight.x - x - Style.space(24))
        anchors.verticalCenter: mk.verticalCenter
        elide: Text.ElideRight
        text: rr.name || ""
        color: row.tone
        font.pixelSize: Style.font.caption + 1
      }
      Rectangle { visible: !!rr.live; x: rowName.x + rowName.width + Style.space(8); anchors.verticalCenter: mk.verticalCenter; width: 5; height: 5; radius: 2.5; color: root.ink }
      Label {
        id: rowRight
        anchors.right: parent.right
        anchors.rightMargin: root.gutter + (row.d ? Style.space(14) : 0)
        anchors.verticalCenter: mk.verticalCenter
        text: rr.right || ""
        color: rr.live ? root.valueTone : rr.dim ? root.dimTone : root.labelTone
      }
      Label { visible: !!row.d; anchors.right: parent.right; anchors.rightMargin: root.gutter; anchors.verticalCenter: mk.verticalCenter; text: row.open ? "⌃" : "⌄"; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
      Label {
        x: root.gutter + Style.space(24); y: Style.space(30)
        width: parent.width - x - root.gutter
        elide: Text.ElideRight
        text: rr.facts || ""
        color: rr.dim ? root.dimTone : root.labelTone
        font.pixelSize: Style.font.caption - 1
      }
      Rectangle {
        visible: rr.frac != null || rr.progress >= 0
        x: root.gutter + Style.space(24); y: Style.space(50)
        width: parent.width - x - root.gutter; height: 3; radius: 1.5
        color: root.ruleTone
        Rectangle { width: parent.width * Math.max(0, Math.min(1, rr.progress >= 0 ? rr.progress / 100 : rr.frac || 0)); height: 3; radius: 1.5; color: rr.progress >= 0 ? root.ink : rr.dim ? root.dimTone : root.labelTone }
      }

      // opened: the row's own contents
      Column {
        id: detail
        visible: row.open
        x: root.gutter + Style.space(24)
        y: Style.space(66)
        width: parent.width - x - root.gutter
        spacing: Style.space(10)
        // running: six figures, the activity spark, its settings, its buttons
        Grid {
          visible: !!row.d && row.d.kind === "run"
          columns: 3
          width: parent.width
          rowSpacing: Style.space(8)
          Repeater {
            model: row.d && row.d.cells || []
            Column {
              required property var modelData
              width: detail.width / 3
              Label { text: modelData[0]; color: root.ink; font.pixelSize: Style.font.caption + 2 }
              Label { text: modelData[1]; color: root.labelTone; font.pixelSize: Style.font.caption - 2 }
            }
          }
        }
        Spark { visible: !!row.d && row.d.kind === "run" && (row.d.spark || []).length > 1; width: parent.width; height: Style.space(18); values: row.d && row.d.spark || [] }
        Repeater {
          model: row.d && row.d.kv || []
          Item {
            required property var modelData
            visible: !!modelData.v
            width: detail.width
            height: visible ? Style.space(20) : 0
            Label { anchors.verticalCenter: parent.verticalCenter; text: modelData.k; color: root.labelTone }
            Label { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.v; color: root.valueTone }
            Click { action: modelData.action || "" }
          }
        }
        // held or stopped: what it is and why
        Repeater { model: row.d && row.d.lines || []; Label { required property string modelData; width: detail.width; wrapMode: Text.WordWrap; text: modelData; color: root.valueTone } }
        Label { visible: !!row.d && !!row.d.note; text: row.d && row.d.note || ""; color: root.labelTone; font.pixelSize: Style.font.caption - 2 }
        // free (or held, read only): every model for the card
        ModelList { visible: !!row.d && (row.d.models || []).length > 0; width: parent.width; models: row.d && row.d.models || [] }
        Row {
          visible: !!row.d && (!!row.d.button || (row.d.links || []).length > 0)
          spacing: Style.space(14)
          Btn { visible: !!row.d && !!row.d.button; label: row.d && row.d.button ? row.d.button.label : ""; action: row.d && row.d.button ? row.d.button.action : "" }
          Repeater {
            model: row.d && row.d.links || []
            Label { required property var modelData; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: root.labelTone; Click { action: modelData.action } }
          }
        }
      }
    }
  }

  // launch: a running model in its agent and folder, Open on the right; the agent and the folder each change here
  Component {
    id: launchC
    Item {
      readonly property var rr: parent.r
      height: Style.space(52)
      Mark { id: lm; x: root.gutter; y: Style.space(10); logo: ({ kind: "lab", name: rr.family }); tone: root.ink }
      Label { x: root.gutter + Style.space(24); width: parent.width - x - openBtn.width - root.gutter - Style.space(12); anchors.verticalCenter: lm.verticalCenter; elide: Text.ElideRight; text: rr.name; color: root.ink; font.pixelSize: Style.font.caption + 1 }
      Row {
        x: root.gutter + Style.space(24); y: Style.space(28)
        spacing: Style.space(6)
        Label { text: rr.agent; color: root.valueTone; font.pixelSize: Style.font.caption - 1; Click { action: rr.agentAction } }
        Label { text: "·"; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
        Label { text: rr.folder; color: root.valueTone; font.pixelSize: Style.font.caption - 1; Click { action: rr.folderAction } }
      }
      Btn { id: openBtn; anchors.right: parent.right; anchors.rightMargin: root.gutter; y: Style.space(10); label: "Open"; action: rr.open }
    }
  }

  // today, week, month, 3 months, year, lifetime
  Component {
    id: tiersC
    Item {
      readonly property var rr: parent.r
      height: Style.space(112)
      Grid {
        id: tierGrid
        x: root.gutter; y: Style.space(18)
        width: parent.width - 2 * root.gutter
        columns: 3
        rowSpacing: Style.space(14)
        Repeater {
          model: rr.cells || []
          Column {
            required property var modelData
            required property int index
            width: tierGrid.width / 3
            Label { text: modelData[0]; color: index === 0 ? root.ink : root.valueTone; font.pixelSize: Style.font.body + 2 }
            Label { text: modelData[1]; color: root.labelTone; font.pixelSize: Style.font.caption - 2 }
          }
        }
      }
    }
  }

  // the calendar: a column a week, a row a weekday, each day shaded by its tokens; hover says the day
  Component {
    id: calendarC
    Item {
      id: cal
      readonly property var rr: parent.r
      readonly property real cell: Style.space(9)
      readonly property real step: Style.space(11)
      property int hover: -1
      height: Style.space(16) + 7 * step + Style.space(34)
      Repeater {
        model: cal.rr.months || []
        Label { required property var modelData; x: root.gutter + Style.space(12) + modelData.col * cal.step; text: modelData.label; color: root.labelTone; font.pixelSize: Style.font.caption - 3 }
      }
      Repeater {
        model: [["M", 0], ["W", 2], ["F", 4]]
        Label { required property var modelData; x: root.gutter; y: Style.space(14) + modelData[1] * cal.step - 1; text: modelData[0]; color: root.labelTone; font.pixelSize: Style.font.caption - 4 }
      }
      Repeater {
        model: (cal.rr.cells || []).length
        Rectangle {
          required property int index
          readonly property int level: cal.rr.cells[index]
          x: root.gutter + Style.space(12) + Math.floor(index / 7) * cal.step
          y: Style.space(16) + index % 7 * cal.step
          width: cal.cell; height: cal.cell; radius: 1.5
          visible: level >= 0
          color: Util.alpha(root.theme, [0.07, 0.22, 0.42, 0.66, 0.95][Math.max(0, level)])
          border.width: index === cal.rr.today || index === cal.hover ? 1 : 0
          border.color: root.ink
          MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: cal.hover = index; onExited: if (cal.hover === index) cal.hover = -1 }
        }
      }
      Label {
        x: root.gutter + Style.space(12)
        y: Style.space(16) + 7 * cal.step + Style.space(8)
        text: (cal.rr.labels || [])[cal.hover >= 0 ? cal.hover : cal.rr.today] || ""
        color: root.valueTone
        font.pixelSize: Style.font.caption - 1
      }
    }
  }

  // ‹ back to the rows, and what this page is about
  Component {
    id: backC
    Item {
      readonly property var rr: parent.r
      height: Style.space(52)
      Label { id: backLabel; x: root.gutter; y: Style.space(20); width: Math.min(implicitWidth, (parent.width - 2 * root.gutter) * 0.7); elide: Text.ElideRight; text: "‹ " + rr.label; color: root.ink; font.pixelSize: Style.font.body + 1 }
      Label { anchors.left: backLabel.right; anchors.leftMargin: Style.space(10); anchors.baseline: backLabel.baseline; width: parent.width - x - root.gutter; elide: Text.ElideRight; text: rr.sub || ""; color: root.labelTone; font.pixelSize: Style.font.caption - 1 }
      Click { action: "back" }
    }
  }

  Component {
    id: listC
    Item {
      readonly property var rr: parent.r
      height: ml.implicitHeight + Style.space(10)
      ModelList { id: ml; x: root.gutter; width: parent.width - 2 * root.gutter; models: rr.models || [] }
    }
  }

  // a choice: an agent (its mark in black and white) or a folder; the chosen one dotted
  Component {
    id: optC
    Item {
      readonly property var rr: parent.r
      height: Style.space(34)
      Rectangle { visible: !!rr.on; x: root.gutter - Style.space(12); anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: root.ink }
      Mark { visible: !!rr.agent; x: root.gutter; anchors.verticalCenter: parent.verticalCenter; agent: rr.agent || ""; tone: rr.on ? root.ink : root.valueTone }
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
      height: Style.space(40)
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
      height: Style.space(58)
      Btn { x: root.gutter; y: Style.space(14); label: rr.label; action: rr.action || "" }
    }
  }

  Component {
    id: fieldC
    Item {
      readonly property var rr: parent.r
      height: fieldCol.implicitHeight
      Column {
        id: fieldCol
        x: root.gutter
        topPadding: Style.space(14)
        bottomPadding: Style.space(8)
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
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    enabled: action !== ""
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activate(action)
  }

  // every model for a card: the picked one highlighted, the first tagged, what each needs under its name, `remove`
  // beside one on disk; a model that cannot run here is dim and does nothing
  component ModelList: Column {
    id: list
    property var models: []
    Repeater {
      model: list.models
      Item {
        required property var modelData
        width: list.width
        height: Style.space(34)
        Rectangle { visible: !!modelData.on; x: -Style.space(6); width: parent.width + Style.space(6); height: parent.height - 2; radius: 3; color: Util.alpha(root.theme, 0.07) }
        Mark { id: lmk; y: Style.space(4); logo: ({ kind: "lab", name: modelData.family }); tone: modelData.off ? root.dimTone : modelData.on ? root.ink : root.valueTone }
        Label { x: Style.space(20); y: Style.space(4); width: parent.width - x - removeLink.width - Style.space(8); elide: Text.ElideRight; text: modelData.name
          color: modelData.off ? root.dimTone : modelData.on ? root.ink : root.valueTone }
        Label { x: Style.space(20); y: Style.space(19); text: [modelData.tag, modelData.note].filter(Boolean).join(" · "); color: modelData.off ? root.dimTone : root.labelTone; font.pixelSize: Style.font.caption - 2 }
        Click { action: modelData.action || "" }
        Label { id: removeLink; visible: !!modelData.remove; anchors.right: parent.right; y: Style.space(4); text: visible ? "remove" : ""; color: root.labelTone; font.pixelSize: Style.font.caption - 2
          Click { action: modelData.remove || "" } }
      }
    }
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
    width: Style.space(agent ? 16 : 15)
    height: width
    FileView {
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

  // Tokens over time, cumulative: a line over a faint area; flat when there is nothing yet
  component Line: Canvas {
    property var values: []
    onValuesChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var g = getContext("2d"), v = values || [], n = v.length, top = Math.max.apply(null, v.concat([1]))
      g.clearRect(0, 0, width, height)
      g.strokeStyle = root.valueTone
      g.lineWidth = 1.4
      g.beginPath()
      if (n < 2 || top <= 1) { g.moveTo(0, height - 1); g.lineTo(width, height - 1); g.strokeStyle = root.ruleTone; g.stroke(); return }
      for (var i = 0; i < n; i++) {
        var x = i / (n - 1) * width, y = height - 1 - v[i] / top * (height * 0.92)
        if (i) g.lineTo(x, y)
        else g.moveTo(x, y)
      }
      g.stroke()
      g.lineTo(width, height)
      g.lineTo(0, height)
      g.closePath()
      g.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
      g.fill()
    }
  }

  // a small bar chart, newest at the right
  component Spark: Item {
    id: sp
    property var values: []
    readonly property real peak: Math.max.apply(null, (values || []).concat([1]))
    readonly property real step: width / Math.max(1, (values || []).length)
    Repeater {
      model: (sp.values || []).length
      Rectangle {
        required property int index
        x: index * sp.step
        width: Math.max(1, sp.step - 1)
        height: Math.max(1, sp.values[index] / sp.peak * sp.height)
        y: sp.height - height
        color: sp.values[index] > 0 ? Util.alpha(root.theme, 0.5) : root.ruleTone
      }
    }
  }

  // the one solid button
  component Btn: Rectangle {
    id: btn
    property string label
    property string action
    visible: label !== ""
    implicitWidth: btnText.implicitWidth + Style.space(26)
    implicitHeight: Style.space(28)
    radius: Style.space(3)
    color: root.ink
    opacity: action === "" ? 0.4 : 1
    Label { id: btnText; anchors.centerIn: parent; text: btn.label; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 1) }
    Click { action: btn.action }
  }
}
