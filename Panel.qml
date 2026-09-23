import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
// The Local AI card: one bar mark and one popup with three views, home, stats and open. Model.js derives
// the hero and the rows from the snapshot the backend writes; this component draws them and turns row
// actions into backend verbs. Data in: one watched file. Data out: a handful of verbs.
Panel {
  id: root
  property var manifest: null
  moduleName: manifest && manifest.id ? manifest.id : "sero.local-ai"
  ipcTarget: moduleName
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string sourceDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: sourceDir + "/bin/omarchy-local-ai"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateName: moduleName === "sero.local-ai" ? "local-ai" : moduleName.replace(/^sero\./, "")   // a second copy keeps its own state
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/" + stateName
  readonly property var env: ["OMARCHY_AI_STATE=" + stateDir]

  // ---------------------------------------------------------------- palette: the Agents panel's contract, and shades of it
  readonly property color popupBg: Color.popups.background
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property color fg: Qt.darker(ink, 1.25)
  readonly property color dim: Qt.darker(ink, 1.8)
  readonly property color faint: Util.alpha(ink, 0.18)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color hoverFill: Util.alpha(ink, 0.07)
  readonly property color hairline: Util.alpha(ink, 0.12)
  readonly property string mono: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- snapshot and state
  property var snap: ({ state: "uninitialized", operation: {}, models: [], cards: [], recipes: [], gpus: [], agents: {}, stats: {}, reason: "", error: "", statusText: "", helpText: "" })
  property string view: "home"
  property string localError: ""
  property bool pending: false          // a verb was issued and no snapshot has confirmed it yet
  property string lastVerb: ""
  property int elapsed: 0
  property int cursor: 0
  readonly property var ui: Model.build({ snap: snap, view: view, pending: pending, lastVerb: lastVerb, elapsed: elapsed, localError: localError })
  readonly property string tone: ui.hero.tone
  readonly property bool working: tone === "work"
  readonly property var actionable: ui.rows.map(function(r, i) { return r.action && !r.disabled ? i : -1 }).filter(function(i) { return i >= 0 })
  readonly property int cursorAt: actionable.length ? actionable[Math.min(cursor, actionable.length - 1)] : -1

  function take(json) { // the snapshot, not our own pending flag, decides when pending ends
    try { var s = JSON.parse(json); if (Model.isWorking({ snap: s }) || (!!s.error && s.error !== snap.error) || (!action.running && ["load", "unload"].indexOf(lastVerb) < 0)) pending = false; snap = s; localError = ""; tick() }
    catch (e) { if (json.trim() === "") { localError = "no answer"; pending = false } }
  }
  function tick() { var t = Date.parse((snap.operation || {}).startedAt || ""); elapsed = working && !isNaN(t) ? Math.max(0, Math.round((Date.now() - t) / 1000)) : 0 }
  function refresh() { if (!poll.running) poll.running = true }
  function go(v) { view = v; cursor = 0; Qt.callLater(function() { flick.contentY = 0; focusContent() }) }
  function focusContent() { keys.forceActiveFocus() }
  function act(args) { if (action.running) return; lastVerb = args[0]; pending = true; pendingTimeout.restart(); action.command = [cli].concat(args); action.running = true }
  function activate(a) {
    if (!a) return
    var s = a.split(":"), v = s[0]
    if (v === "stats" || v === "open") go(v)
    else if (v === "back" || v === "home") go("home")
    else if (v === "run") { if (working) return; go("home"); act(["load", s[1]].concat(Model.loadKeys(snap, s[1]))) }
    else if (v === "stop") { go("home"); act(["unload", s[1]]) }
    else if (v === "stop-download") act(["unload"])
    else if (v === "agent") act(["agent-default", s[1]])
    else if (v === "open-agent") { if (agentLaunch.running) return; agentLaunch.command = [cli, "agent"]; agentLaunch.running = true }
    else if (v === "log") logOpen.running = true
  }
  function moveCursor(d) { if (actionable.length) cursor = ((cursor + d) % actionable.length + actionable.length) % actionable.length }
  function revealRow(i) { var it = rowsRep.itemAt(i); if (!it) return; var y = it.mapToItem(content, 0, 0).y
    if (y < flick.contentY) flick.contentY = y; else if (y + it.height > flick.contentY + flick.height) flick.contentY = y + it.height - flick.height }
  onCursorAtChanged: if (cursorAt >= 0) Qt.callLater(function() { root.revealRow(root.cursorAt) })

  // ---------------------------------------------------------------- the backend: one file in, verbs out
  FileView { path: root.stateDir + "/snapshot.json"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: root.take(text()) }
  Process { id: poll; command: [root.cli, "snapshot"]; environment: root.env; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } } }
  Process { id: action; environment: root.env; onExited: function(code) { if (["load", "unload"].indexOf(root.lastVerb) < 0) root.pending = false; root.refresh() } }
  Process { id: agentLaunch; environment: root.env; onExited: function(code) { root.refresh(); if (code === 0) root.close() } }
  Process { id: logOpen; command: ["omarchy-launch-tui", "--app-id=org.omarchy.local-ai-log", "less", "+G", root.stateDir + "/log"] }
  Timer { interval: root.pending ? 1000 : root.working ? 2000 : root.opened ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pending = false }
  Timer { interval: 1000; running: root.working; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
  onOpenedChanged: { if (opened) { refresh(); go("home") } }
  onToneChanged: cursor = 0

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function activate(a: string): string { root.activate(a); return root.tone + ":" + root.view }   // any row action, for scripts and tests
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component { Item { Rectangle { // the bar mark: one square. faint idle, ink ready, accent blinking while working, urgent on error
      anchors.centerIn: parent; width: Style.space(8); height: width
      color: root.tone === "ready" ? root.ink : root.tone === "work" ? root.accent : root.tone === "error" ? root.urgent : Util.alpha(root.ink, 0.4)
      SequentialAnimation on opacity { running: root.working; loops: Animation.Infinite; alwaysRunToEnd: true; NumberAnimation { to: 0.3; duration: 500 } NumberAnimation { to: 1; duration: 500 } } } } }
    tooltipText: "Local AI · " + root.ui.hero.title
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    padding: 0
    borderSpec: Border.flat("#2e2e2e", 1)
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    Rectangle { anchors.fill: parent; color: root.popupBg }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var k = event.key, r = root.cursorAt >= 0 ? root.ui.rows[root.cursorAt] : null
        if (k === Qt.Key_Escape) { if (root.view !== "home") root.go("home"); else root.close() }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
        else if (k === Qt.Key_Down || event.text === "j") root.moveCursor(1)
        else if (k === Qt.Key_Up || event.text === "k") root.moveCursor(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (r) root.activate(r.action) }
        else if (k === Qt.Key_Backspace && root.view !== "home") root.go("home")
        else if (event.text === "s" && root.view === "home") root.go("stats")
        else return
        event.accepted = true
      }
      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width; contentHeight: content.implicitHeight
        clip: true; interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: content
          anchors.left: parent.left; anchors.right: parent.right
          spacing: 0
          Item { // the hero: mark, eyebrow, title, and a word at the right that leads somewhere
            width: parent.width; height: Style.space(74)
            Canvas { // the dotted mark: a disc of dots, the state's colour
              x: Style.space(16); anchors.verticalCenter: parent.verticalCenter; width: Style.space(30); height: width
              property color c: root.tone === "work" ? root.accent : root.tone === "error" ? root.urgent : root.tone === "ready" ? root.ink : Util.alpha(root.ink, 0.35)
              onCChanged: requestPaint()
              onPaint: { var g = getContext("2d"), r = width / 2, s = 4; g.clearRect(0, 0, width, height); g.fillStyle = c
                for (var y = s / 2; y < height; y += s) for (var x = s / 2; x < width; x += s) if ((x - r) * (x - r) + (y - r) * (y - r) <= r * r) g.fillRect(x - 0.8, y - 0.8, 1.6, 1.6) } }
            Column { x: Style.space(56); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
              Text { textFormat: Text.PlainText; text: root.ui.hero.eyebrow; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; font.letterSpacing: 1.5 }
              Text { textFormat: Text.PlainText; text: root.ui.hero.title; color: root.ink; font.family: root.mono; font.pixelSize: Style.font.subtitle; width: panel.contentWidth - Style.space(130); elide: Text.ElideRight }
              Text { textFormat: Text.PlainText; text: root.ui.hero.sub; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; width: panel.contentWidth - Style.space(130); elide: Text.ElideRight } }
            Button { visible: root.ui.hero.right !== ""; anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
              text: root.ui.hero.right + " ›"; bordered: false; foreground: root.dim; fontFamily: root.mono; fontSize: Style.font.caption; onClicked: root.activate(root.ui.hero.rightAction) }
          }
          Repeater { id: rowsRep; model: root.ui.rows
            CardRow { required property var modelData; required property int index; objectName: "row-" + index; r: modelData; p: root; width: content.width; cursor: index === root.cursorAt } }
          Item { width: parent.width; height: Style.space(12) }
        }
      }
    }
  }
}
