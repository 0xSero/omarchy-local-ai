import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "View8.js" as View8

// Local AI 8: connect, your hardware and its models, a model, what runs, settings; the same pages in the panel and
// full screen. View8.js turns the backend's snapshot into a page, Page8.qml draws it, and this file runs the verbs.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-local-ai")).replace(/^file:\/\//, ""))
  readonly property color theme: bar ? bar.foreground : Color.foreground
  readonly property color dotTone: bar && bar.barForeground !== undefined ? bar.barForeground : theme
  readonly property color bg: Color.popups.background
  readonly property color surface: Util.alpha(theme, 0.06)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string mono: bar ? bar.fontFamily : Style.font.family
  readonly property var tones: Model.tones(theme, bg, surface, urgent)
  function tone(t) { return Qt.rgba(t.r, t.g, t.b, 1) }
  // a card sits one step up from the panel: the surface over the background, drawn solid
  readonly property color card: Qt.rgba(bg.r + (theme.r - bg.r) * 0.06, bg.g + (theme.g - bg.g) * 0.06, bg.b + (theme.b - bg.b) * 0.06, 1)

  property var snap: ({})
  property var ui: ({ page: "connect" })
  property var queue: []
  property bool again: false
  property bool full: false
  property var fullWindow: null

  function draw(u) {
    try { return View8.build(snap, Object.assign({}, u, { now: Date.now() })) }
    catch (e) { return { header: { toggle: "full|on" }, cards: [{ alert: true, rows: [{ type: "note", alert: true, text: "could not read the backend's answer: " + e.message }] }] } }
  }
  readonly property var view: draw(ui)
  readonly property var wideView: full ? draw(Object.assign({}, ui, { wide: true })) : ({})

  // the animation clock: ten frames a second while a page has something moving and is on screen
  property int tick: 0
  Timer {
    interval: 110; repeat: true
    running: (root.opened || root.full) && !!(root.full ? root.wideView.anim : root.view.anim)
    onTriggered: root.tick++
  }

  function nav(patch) { ui = Object.assign({}, ui, { problem: "", notice: "" }, patch) }
  function run(args) { queue.push(args); if (!verb.running) next() }
  function next() {
    if (!queue.length) return refresh()
    var args = queue.shift()
    verb.operation = args[0]
    verb.command = (args[0] === "setup" ? [cli] : ["timeout", "--kill-after=5", args[0] === "update" ? "900" : "120", cli]).concat(args)
    verb.running = true
  }
  function refresh() { if (poll.running) again = true; else poll.running = true }

  // An action is "verb|arg|arg", from View8.js
  function activate(action) {
    var a = (action || "").split("|")
    switch (a[0]) {
    case "page": if (a[1] === "main" && ui.page === "connect") tick = 0; nav({ page: a[1] }); break
    case "model": nav({ page: "model", id: a[1], keys: a[2] || "" }); break
    case "node": {
      var closed = Object.assign({}, ui.closed || {}), open = closed[a[1]] === undefined ? a[2] !== "1" : !closed[a[1]]
      closed[a[1]] = open
      ui = Object.assign({}, ui, { closed: closed })
      break
    }
    case "more": { var more = Object.assign({}, ui.more || {}); more[a[1]] = !more[a[1]]; ui = Object.assign({}, ui, { more: more }); break }
    case "run": run(["run", a[1], a[2]]); nav({ page: "main" }); break
    case "again": run(["stop", a[1]]); run(["run", base(a[1]), a[2]]); nav({ page: "main" }); break
    case "stop": run(["stop", a[1]]); break
    case "open": run(["open", a[1]]); break
    case "download": run(["download", a[1]].concat(a[2] ? [a[2]] : [])); break
    case "share": run(["share", a[1]].concat(a[2] ? [a[2]] : [])); break
    case "default": run(["set", "agent", a[1]]); break
    case "set": run(["set", a[1], a[2]]); break
    case "update": ui = Object.assign({}, ui, { updatingAgent: a[1] }); run(["update", a[1]]); break
    case "setup": run(["setup"]); break
    case "url": Quickshell.execDetached(["omarchy-launch-browser", a.slice(1).join("|")]); root.close(); full = false; break
    case "full": full = a[1] !== "off"; if (full) root.close(); else root.open(); break
    case "report": report.running = true; break
    }
  }
  // the same actions from a script: qs ipc call <ipcTarget>.ui act "page|tree"
  IpcHandler {
    target: root.ipcTarget + ".ui"
    function act(action: string): void { if (!root.opened && !root.full) root.open(); root.activate(action) }
    function page(): string { return root.ui.page + (root.full ? " full" : "") }
  }
  function base(id) { return id.indexOf("--") >= 0 ? id.slice(0, id.lastIndexOf("--")) : id }

  // Report a bug: a GitHub issue filled in with the cards, versions, state and the last 50 log lines, opened in the
  // browser for the user to read and send (nothing is sent from here)
  Process {
    id: report
    command: ["tail", "-n", "50", Quickshell.env("HOME") + "/.local/state/omarchy/local-ai/log"]
    stdout: StdioCollector { id: reportOut; waitForEnd: true }
    onExited: function(code) {
      var cards = (root.snap.gpus || []).map(function(g) { return g.name + (g.vramGb ? " " + g.vramGb + " GB" : "") }).join(", ")
      var running = (root.snap.deployments || []).map(function(d) { return d.id + " " + d.state + (d.error ? ": " + d.error : "") }).join("\n")
      var log = (reportOut.text || "").slice(-5000)
      var body = "**What happened**\n\n<!-- what you did and what you expected -->\n\n**Machine**\n\n- Local AI " + (root.snap.version || "?") +
        "\n- cards: " + (cards || "none found") + "\n- readiness: " + ((root.snap.readiness || {}).state || "?") +
        (running ? "\n\n**Models**\n\n```\n" + running + "\n```" : "") + "\n\n**Last 50 log lines**\n\n```\n" + log + "\n```\n"
      var url = "https://github.com/0xSero/omarchy-local-ai/issues/new?title=" + encodeURIComponent("Local AI " + (root.snap.version || "") + ": ") +
        "&body=" + encodeURIComponent(body)
      Quickshell.execDetached(["omarchy-launch-browser", url])
      root.close()
      root.full = false
    }
  }

  function polled(code, text) {
    var s = code === 0 ? Model.parse(text) : null
    var ok = s && Array.isArray(s.gpus) && Array.isArray(s.kinds) && Array.isArray(s.deployments)
    if (ok) snap = s
    ui = Object.assign({}, ui, { pollProblem: ok ? "" : "Could not refresh Local AI; retrying." })
  }
  Process {
    id: poll
    command: ["timeout", "--kill-after=5", "90", root.cli, "snapshot"]
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    onExited: function(code) { root.polled(code, pollOut.text); if (root.again) { root.again = false; Qt.callLater(root.refresh) } }
  }
  // A verb that fails says why on its last "local-ai:" line; the panel opens to show it
  function finished(code, operation, output, error) {
    ui = Object.assign({}, ui, { updatingAgent: operation === "update" ? "" : ui.updatingAgent || "" })
    if (code !== 0) {
      var m = (error || "").split("\n").filter(function(l) { return l.indexOf("local-ai: ") === 0 }).pop()
      queue = []
      if (!root.opened && !root.full) root.open()
      ui = Object.assign({}, ui, { problem: code === 124 || code === 137 ? "That took too long; try again." : m ? m.slice(10) : "that did not work (see the log)" })
    } else if (operation === "open") {
      root.close()
      full = false
    } else if (operation === "update") {
      ui = Object.assign({}, ui, { notice: output.trim() })
    }
    next()
  }
  Process {
    id: verb
    property string operation: ""
    stdout: StdioCollector { id: verbOut; waitForEnd: true }
    stderr: StdioCollector { id: verbErr; waitForEnd: true }
    onExited: function(code) { root.finished(code, operation, verbOut.text, verbErr.text) }
  }
  Timer {
    interval: root.view.mark === "busy" ? (root.opened || root.full ? 1500 : 5000) : root.opened || root.full ? 5000 : 30000
    running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }
  onOpenedChanged: if (opened) refresh(); else if (ui.problem) ui = Object.assign({}, ui, { problem: "" })

  onFullChanged: {
    if (full) {
      refresh()
      if (!fullWindow) fullWindow = Qt.createComponent("FullScreen.qml").createObject(root, { content: fullBody, screen: panel.screen || Quickshell.screens[0], color: root.bg })
    } else if (fullWindow) {
      fullWindow.destroy()
      fullWindow = null
    }
  }

  // the bar mark: nine dots, faint when nothing runs, lit when a model is ready, urgent when one failed, a ripple
  // while one starts
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

  Component {
    id: pageComponent
    Page8 {
      mono: root.mono
      bg: root.bg
      surface: root.card
      tick: root.tick
      ink: root.tone(root.tones.ink)
      valueTone: root.tone(root.tones.value)
      labelTone: root.tone(root.tones.label)
      ruleTone: root.tone(root.tones.rule)
      alertTone: root.tone(root.tones.alert)
      onActivated: function(action) { root.activate(action) }
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(Style.space(560), panel.screen ? panel.screen.height - Style.space(96) : 0)
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: { if (root.ui.page === "model") root.nav({ page: "tree" }); else if (root.ui.page !== "main" && root.ui.page !== "connect") root.nav({ page: "main" }); else root.close() }
      Loader {
        anchors.fill: parent
        sourceComponent: pageComponent
        onLoaded: { item.view = Qt.binding(function() { return root.view }); item.wide = false; item.objectName = "local-ai-8-panel" }
      }
    }
  }

  Component {
    id: fullBody
    FocusScope {
      focus: true
      Keys.onEscapePressed: { if (root.ui.page === "model") root.nav({ page: "tree" }); else if (root.ui.page !== "main" && root.ui.page !== "connect") root.nav({ page: "main" }); else root.full = false }
      Loader {
        anchors.fill: parent
        sourceComponent: pageComponent
        onLoaded: { item.view = Qt.binding(function() { return root.wideView }); item.wide = true; item.objectName = "local-ai-8-full" }
      }
    }
  }
}
