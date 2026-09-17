import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui.js" as Ui
// The card: a recessed state slab (orb, state word, title) over rows on a raised body, a pinned
// footer for the verbs. Three places: home (cards and what runs on them), a card type (how many,
// which recipe), a running model (its numbers, agent, share, stop). Work and error take the whole
// card over. ui.js decides what the rows are; this file draws them and runs the verbs.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string sourceDir: String(Qt.resolvedUrl("..")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: sourceDir + "/bin/omarchy-local-ai"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/local-ai"

  // ---------------------------------------------------------------- the locked palette: matte black, fills not borders, sharp corners
  readonly property color popupBg: "#1a1a1a"
  readonly property color popupLine: "#2e2e2e"
  readonly property color ink: "#f5f5f5"
  readonly property color fg: "#bebebe"
  readonly property color dim: "#8a8a8d"
  readonly property color faint: "#555555"
  readonly property color urgent: "#D35F5F"
  readonly property color accent: "#e68e0d"
  readonly property color orbField: "#4b4b4b"
  readonly property color recessed: Qt.rgba(0, 0, 0, 0.24)
  readonly property color restFill: Util.alpha(ink, 0.04)
  readonly property color hoverFill: Util.alpha(ink, 0.08)
  readonly property color selectedFill: Util.alpha(ink, 0.16)
  readonly property color hairline: Util.alpha(ink, 0.07)
  readonly property string mono: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- snapshot and navigation
  property var snap: ({ state: "uninitialized", operation: {}, models: [], cards: [], recipes: [], gpus: [], share: {}, agents: {}, reason: "", error: "" })
  property var path: ["home"]           // home › card › model
  readonly property string view: path[path.length - 1]
  property string hw: ""                // the card type open
  property int count: 1                 // how many of it
  property string pick: ""              // the recipe picked
  property string slotSel: ""           // the running model open
  property string agentPick: ""
  property bool expanded: false
  property bool agentOpen: false
  property bool copied: false
  property string toast: ""
  property string localError: ""
  property bool pending: false          // a verb was issued and no snapshot has confirmed it yet
  property string lastVerb: ""
  property var queue: []                // verbs to run after the current one exits
  property int elapsed: 0
  property int cursor: 0
  readonly property var ui: Ui.build({ snap: snap, view: view, hw: hw, count: count, pick: pick, slotSel: slotSel, agentPick: agentPick, agentOpen: agentOpen, copied: copied, pending: pending, lastVerb: lastVerb, elapsed: elapsed, localError: localError })
  readonly property string tone: ui.tone
  readonly property color toneColor: tone === "work" ? accent : tone === "error" ? urgent : tone === "ready" ? ink : dim
  readonly property bool working: tone === "work"
  readonly property var all: ui.rows.concat(ui.foot)
  readonly property var actionable: all.map(function(r, i) { return r.action && !r.disabled ? i : -1 }).filter(function(i) { return i >= 0 })
  readonly property int cursorAt: actionable.length ? actionable[Math.min(cursor, actionable.length - 1)] : -1

  function take(json) {
    try { var s = JSON.parse(json), busyNow = ["download", "starting", "unload", "share"].indexOf(s.state) >= 0, newError = !!s.error && s.error !== snap.error; freed(snap, s); snap = s; localError = ""; if (busyNow || newError || (actionDone && ["run", "load", "unload", "share"].indexOf(lastVerb) < 0)) pending = false; tick() }   // the snapshot, not our own pending flag, decides when pending ends
    catch (e) { if (json.trim() === "") { localError = "no answer"; pending = false } }
  }
  function freed(before, after) { // a model that left while we were stopping: say which card came free
    var gone = (before.models || []).filter(function(m) { return m.state !== "stopped" && !(after.models || []).some(function(n) { return n.recipeId === m.recipeId && n.state !== "stopped" }) })
    if (gone.length && (lastVerb === "unload" || before.state === "unload")) { var c = Ui.cardOfKeys(before, gone[0].keys); say((c ? c.name : "card") + " " + gone[0].keys.map(function(k) { return "#" + k.split(":")[1] }).join(" ") + " · freed") }
  }
  function tick() { var t = Date.parse((snap.operation || {}).startedAt || ""); elapsed = working && !isNaN(t) ? Math.max(0, Math.round((Date.now() - t) / 1000)) : 0 }
  function say(t) { toast = t; toastTimer.restart() }
  function refresh() { if (!poll.running) poll.running = true }
  function go(v) { var p = path.slice(); p.push(v); path = p; cursor = 0; agentOpen = false }
  function back() { if (path.length > 1) { var p = path.slice(); p.pop(); path = p } cursor = 0; agentOpen = false }
  function home() { path = ["home"]; cursor = 0; agentOpen = false }
  // verbs hand off to the controller one at a time; run, load, unload and share are done when a snapshot
  // shows their worker, the rest when the process exits
  property bool actionDone: false
  function act(args) { if (action.running) { queue = queue.concat([args]); return } lastVerb = args[0]; actionDone = false; pending = true; pendingTimeout.restart(); action.command = [cli].concat(args); action.running = true }
  function activate(a) {
    if (!a) return
    var s = a.split(":"), v = s[0]
    if (v === "expand") expanded = !expanded
    else if (v === "home") home()
    else if (v === "back") back()
    else if (v === "card") { hw = s[1]; count = 1; pick = ""; go("card") }
    else if (v === "count") { count = parseInt(s[1], 10) || 1; pick = "" }
    else if (v === "pick") pick = s[1]
    else if (v === "model") { slotSel = s[1]; home(); go("model") }
    else if (v === "run") { if (working) return; var g = Ui.cardByHw(snap, hw), free = g ? Ui.freeKeys(snap, g) : []; home(); act(["run", s[1], Ui.freest(snap, free) || (g ? g.keys[0] : "")].filter(function(x) { return x !== "" })) }
    else if (v === "run-again") { if (working) return; home(); act(["load"]) }
    else if (v === "refresh") { localError = ""; refresh() }
    else if (v === "stop") { if (working) return; home(); act(["unload", s[1]]) }
    else if (v === "stop-download") { if (action.running) return; lastVerb = "unload"; actionDone = false; action.command = [cli, "unload"]; action.running = true }
    else if (v === "agent-toggle") agentOpen = !agentOpen
    else if (v === "agent") { agentPick = s[1]; agentOpen = false }
    else if (v === "open-agent") { if (agentLaunch.running) return; agentLaunch.command = [cli, "open-agent", s[1], s[2]]; agentLaunch.running = true; say(s[1] + " · " + (Ui.modelById(snap, s[2]) || { name: "" }).name) }
    else if (v === "share") { if (working) return; act(["share"]) }
    else if (v === "copy") { var m = Ui.modelById(snap, s[1]); if (copy.running || !m) return; copy.command = ["bash", "-c", "command -v wl-copy >/dev/null 2>&1 || exit 127; printf %s \"$1\" | wl-copy", "_", m.shareUrl]; copy.running = true }
    else if (v === "log") { logOpen.running = true; say("log · open") }
  }
  function moveCursor(d) { if (actionable.length) cursor = ((cursor + d) % actionable.length + actionable.length) % actionable.length }
  function cursorRow() { return cursorAt >= 0 ? all[cursorAt] : null }

  // ---------------------------------------------------------------- the controller
  FileView { path: root.stateDir + "/snapshot.json"; watchChanges: true; onFileChanged: reload(); onLoaded: root.take(text()) }
  Process { id: poll; command: [root.cli, "snapshot"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } } }
  Process { id: action; onExited: { if (root.queue.length) { var n = root.queue[0]; root.queue = root.queue.slice(1); root.lastVerb = n[0]; root.pending = true; pendingTimeout.restart(); action.command = [root.cli].concat(n); action.running = true; return } root.actionDone = true; if (["run", "load", "unload", "share"].indexOf(root.lastVerb) < 0) root.pending = false; root.refresh() } }
  Process { id: agentLaunch; onExited: function(code) { root.refresh(); if (code === 0) root.close() } }
  Process { id: copy; onExited: function(code) { if (code === 0) { root.copied = true; copiedTimer.restart(); root.say("link copied") } else root.say(code === 127 ? "wl-copy · missing" : "copy · failed") } }
  Process { id: logOpen; command: ["omarchy-launch-tui", "--app-id=org.omarchy.local-ai-log", "less", "+G", root.stateDir + "/log"] }
  Timer { interval: root.pending ? 1000 : root.working ? 2000 : root.opened ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pending = false }
  Timer { interval: 1000; running: root.working; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
  Timer { id: toastTimer; interval: 3500; onTriggered: root.toast = "" }
  Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = false }
  // the share toggle finishes with the link on the clipboard
  onSnapChanged: { if (lastVerb === "share" && slotSel !== "" && view === "model" && !working) { var m = Ui.modelById(snap, slotSel); if (m && m.shareUrl) { lastVerb = ""; activate("copy:" + slotSel) } } }
  onOpenedChanged: { if (opened) { refresh(); if (!working) home() } }
  onToneChanged: { if (tone === "error" || (tone === "work" && lastVerb !== "share")) home(); cursor = 0 }
  onViewChanged: cursor = 0

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function load(): string { root.act(["load"]); return "ok" }
    function unload(): string { root.act(["unload"]); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
    function activate(a: string): string { root.activate(a); return root.tone + ":" + root.view }   // any row action, for scripts and tests
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component { Item { Rectangle { // the bar mark: one square. faint idle, ink ready, accent blinking while working, urgent on error
      anchors.centerIn: parent; width: Style.space(8); height: width
      color: root.tone === "ready" ? (root.bar ? root.bar.foreground : root.ink) : root.tone === "work" ? root.accent : root.tone === "error" ? (root.bar ? root.bar.urgent : root.urgent) : Util.alpha(root.bar ? root.bar.foreground : root.ink, 0.4)
      SequentialAnimation on opacity { running: root.working; loops: Animation.Infinite; alwaysRunToEnd: true; NumberAnimation { to: 0.3; duration: 500 } NumberAnimation { to: 1; duration: 500 } } } } }
    tooltipText: "Local AI · " + root.ui.title
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
    borderSpec: Border.flat(root.popupLine, 1)
    contentWidth: root.expanded ? panel.availableCardWidth : panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    readonly property real ceiling: panel.fittedContentHeight(root.expanded ? panel.availableCardHeight : Style.space(720)) - panel.verticalContentInset
    // Fit the scrolling body to the screen as well as the compact panel cap.
    Rectangle { anchors.fill: parent; color: root.popupBg }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var k = event.key, r = root.cursorRow()
        if (k === Qt.Key_F11) root.expanded = !root.expanded
        else if (k === Qt.Key_Escape) { if (root.expanded) root.expanded = false; else if (root.view !== "home") root.back(); else root.close() }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
        else if (k === Qt.Key_Down || event.text === "j") root.moveCursor(1)
        else if (k === Qt.Key_Up || event.text === "k") root.moveCursor(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (r) root.activate(r.action) }
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && root.view === "card") { var g = Ui.cardByHw(root.snap, root.hw), n = g ? Ui.freeKeys(root.snap, g).length : 1; root.count = Math.max(1, Math.min(n, root.count + (k === Qt.Key_Right ? 1 : -1))); root.pick = "" }
        else if (k === Qt.Key_Backspace && root.view !== "home") root.back()
        else return
        event.accepted = true
      }
      Column {
        id: content
        anchors.left: parent.left; anchors.right: parent.right
        spacing: 0
        Item {
          id: sizeControl
          width: parent.width; height: Style.space(32)
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(16); anchors.verticalCenter: parent.verticalCenter; text: "local ai"; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption }
          Rectangle {
            anchors.right: parent.right; anchors.rightMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter
            width: sizeLabel.implicitWidth + Style.space(16); height: Style.space(26)
            color: sizeMouse.containsMouse ? root.hoverFill : root.restFill
            Text { id: sizeLabel; anchors.centerIn: parent; text: root.expanded ? "compact ↙" : "full screen ↗"; color: root.fg; font.family: root.mono; font.pixelSize: Style.font.caption }
            MouseArea { id: sizeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.activate("expand") }
          }
        }
        Rectangle { // ---- the state slab
          id: slab
          width: parent.width; color: root.recessed; implicitHeight: Math.max(Style.space(104), slabRow.implicitHeight + Style.space(32))
          Row {
            id: slabRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(16); spacing: Style.space(14)
            Orb { id: orb; p: root; anchors.verticalCenter: parent.verticalCenter }
            Column {
              width: parent.width - orb.width - parent.spacing; anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
              Text { text: root.ui.eyebrow; color: root.toneColor; font.family: root.mono; font.pixelSize: Style.fontPx(0.75); font.bold: true; font.letterSpacing: Style.fontPx(0.75) * 0.14; font.capitalization: Font.AllUppercase; textFormat: Text.PlainText }
              Text { width: parent.width; text: root.ui.title; color: root.ink; font.family: root.mono; font.pixelSize: Style.fontPx(1.583); font.bold: true; font.letterSpacing: -Style.fontPx(1.583) * 0.03; elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText }
              Text { width: parent.width; visible: text !== ""; text: root.ui.sub; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; elide: Text.ElideRight; textFormat: Text.PlainText }
              Row { // the load steps
                visible: root.ui.steps >= 0; spacing: Style.space(6)
                Repeater { model: ["weights", "image", "engine", "check"]
                  Text { required property string modelData; required property int index; text: (index ? "› " : "") + modelData; color: index === root.ui.steps ? root.accent : index < root.ui.steps ? root.dim : root.faint; font.family: root.mono; font.pixelSize: Style.fontPx(0.75); font.letterSpacing: Style.fontPx(0.75) * 0.06; textFormat: Text.PlainText } }
              }
            }
          }
        }
        Item { // ---- the path, with back in it
          id: crumb
          visible: root.ui.path.length > 1; width: parent.width; height: visible ? Style.space(38) : 0
          Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.hairline }
          Row {
            anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
            Rectangle { width: Style.space(26); height: Style.space(22); color: backMouse.containsMouse ? root.hoverFill : root.restFill; opacity: root.working ? 0.4 : 1
              Text { anchors.centerIn: parent; text: "‹"; color: root.fg; font.family: root.mono; font.pixelSize: Style.font.body; textFormat: Text.PlainText }
              MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; enabled: !root.working; cursorShape: Qt.PointingHandCursor; onClicked: root.back() } }
            Repeater { model: root.ui.path
              Text { required property var modelData; required property int index; anchors.verticalCenter: parent.verticalCenter; text: (index ? "›  " : "") + modelData.n; color: index === root.ui.path.length - 1 ? root.fg : root.faint; font.family: root.mono; font.pixelSize: Style.font.caption; textFormat: Text.PlainText } }
          }
        }
        Flickable { // ---- the rows: the one part that scrolls
          id: body
          width: parent.width
          readonly property real room: panel.ceiling - sizeControl.height - slab.height - crumb.height - foot.height - toastBox.height   // what the ceiling leaves for this part
          height: Math.max(0, root.expanded ? room : Math.min(list.implicitHeight + Style.space(24), room))
          contentHeight: list.implicitHeight + Style.space(24); clip: true; boundsBehavior: Flickable.StopAtBounds
          Column {
            id: list
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(12); spacing: Style.space(6)
            Repeater { id: rowsRep; model: root.ui.rows
              CardRow { required property var modelData; required property int index; r: modelData; p: root; x: r.child ? Style.space(18) : 0; width: list.width - x; cursor: index === root.cursorAt } }
          }
          function reveal(i) { // keep the cursor row in view
            var it = rowsRep.itemAt(i); if (!it) return
            var y = it.y + Style.space(12), h = it.height
            if (y < contentY) contentY = Math.max(0, y - Style.space(12)); else if (y + h > contentY + height) contentY = Math.min(contentHeight - height, y + h - height + Style.space(12))
          }
          Connections { target: root; function onCursorAtChanged() { if (root.cursorAt >= 0 && root.cursorAt < root.ui.rows.length) body.reveal(root.cursorAt) } }
        }
        Column { // ---- the footer: the verbs, pinned
          id: foot
          visible: root.ui.foot.length > 0; width: parent.width; spacing: 0
          Rectangle { width: parent.width; height: 1; color: root.hairline; visible: body.contentHeight > body.height }
          Column { anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(12); spacing: Style.space(6); topPadding: Style.space(6); bottomPadding: Style.space(12)
            Repeater { model: root.ui.foot
              CardRow { required property var modelData; required property int index; r: modelData; p: root; width: parent.width; cursor: root.ui.rows.length + index === root.cursorAt } } }
        }
        Rectangle { // ---- a word that passes
          id: toastBox
          visible: root.toast !== ""; width: parent.width; height: visible ? Style.space(28) : 0; color: root.recessed
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.toast; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
        }
      }
    }
  }
}
