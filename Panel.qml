import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
// The Local AI card: one bar mark and one popup. Model.js derives rows and actions from the
// snapshot the backend writes; this component owns navigation state and turns row actions into
// backend verbs. Data in: one watched file. Data out: four verbs.
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
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/local-ai"

  // ---------------------------------------------------------------- theme: the Agents panel's contract, and shades of it
  readonly property color popupBg: Color.popups.background
  readonly property color popupLine: "#2e2e2e"
  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property color fg: Qt.darker(ink, 1.15)
  readonly property color dim: Qt.darker(ink, 1.55)
  readonly property color faint: Qt.darker(ink, 1.8)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color recessed: Qt.rgba(0, 0, 0, 0.24)
  readonly property color restFill: Util.alpha(ink, 0.04)
  readonly property color hoverFill: Util.alpha(ink, 0.08)
  readonly property color selectedFill: Style.selectedFillFor(ink, Color.accent)
  readonly property color hairline: Util.alpha(ink, 0.12)
  readonly property string mono: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- snapshot and navigation
  property var snap: ({ state: "uninitialized", operation: {}, models: [], cards: [], recipes: [], gpus: [], agents: {}, reason: "", error: "", statusText: "", helpText: "" })
  property var path: ["home"]           // home › card › model
  readonly property string view: path[path.length - 1]
  property string hw: ""                // the card type open
  property int count: 1                 // how many of it
  property string slotSel: ""           // the running model open
  property bool launcherOpen: false
  property string launchPick: ""
  property bool launchModelOpen: false
  property string agentPick: ""
  property bool expanded: false
  property bool agentOpen: false
  property bool editingFolder: false
  property bool browseWhileWorking: false
  property string toast: ""
  property string localError: ""
  property bool pending: false          // a verb was issued and no snapshot has confirmed it yet
  property bool actionDone: false
  property string lastVerb: ""
  property var queue: []                // verbs to run after the current one exits
  property int elapsed: 0
  property int cursor: 0
  readonly property var ui: Model.build({ snap: snap, view: view, browseWhileWorking: browseWhileWorking, hw: hw, count: count, slotSel: slotSel, launcherOpen: launcherOpen, launchPick: launchPick, launchModelOpen: launchModelOpen, agentPick: agentPick, agentOpen: agentOpen, pending: pending, lastVerb: lastVerb, elapsed: elapsed, localError: localError })
  readonly property string tone: ui.tone
  readonly property color toneColor: tone === "work" ? accent : tone === "error" ? urgent : tone === "ready" ? ink : dim
  readonly property bool working: Model.isWorking({ snap: snap, pending: pending, lastVerb: lastVerb })
  onWorkingChanged: { if (!working) browseWhileWorking = false; else if (!browseWhileWorking) Qt.callLater(home) }
  readonly property var all: ui.rows.concat(ui.foot)
  readonly property var actionable: all.map(function(r, i) { return r.action && !r.disabled ? i : -1 }).filter(function(i) { return i >= 0 })
  readonly property int cursorAt: actionable.length ? actionable[Math.min(cursor, actionable.length - 1)] : -1

  function take(json) {
    try { var s = JSON.parse(json), busyNow = ["download", "starting", "unload"].indexOf(s.state) >= 0, newError = !!s.error && s.error !== snap.error; freed(snap, s); snap = s; localError = ""; if (busyNow || newError || (actionDone && ["load", "unload"].indexOf(lastVerb) < 0)) pending = false; tick() }   // the snapshot, not our own pending flag, decides when pending ends
    catch (e) { if (json.trim() === "") { localError = "no answer"; pending = false } }
  }
  function freed(before, after) { // a model that left while we were stopping: say which card came free
    var gone = (before.models || []).filter(function(m) { return m.state !== "stopped" && !(after.models || []).some(function(n) { return n.recipeId === m.recipeId && n.state !== "stopped" }) })
    if (gone.length && (lastVerb === "unload" || before.state === "unload")) { var c = Model.cardOfKeys(before, gone[0].keys); say((c ? c.name : "card") + " " + gone[0].keys.map(function(k) { return "#" + k.split(":")[1] }).join(" ") + " · freed") }
  }
  function tick() { var t = Date.parse((snap.operation || {}).startedAt || ""); elapsed = working && !isNaN(t) ? Math.max(0, Math.round((Date.now() - t) / 1000)) : 0 }
  function say(t) { toast = t; toastTimer.restart() }
  function refresh() { if (!poll.running) poll.running = true }
  function go(v) { var p = path.slice(); p.push(v); path = p; cursor = 0; agentOpen = false }
  function back() { if (path.length > 1) { var p = path.slice(); p.pop(); path = p } cursor = 0; agentOpen = false }
  function home() { path = ["home"]; cursor = 0; agentOpen = false; Qt.callLater(function() { scrollBy(-1e9) }) }
  function focusContent() { keys.forceActiveFocus() }
  function editFolder() { folderInput.text = (snap.agents || {}).directory || Quickshell.env("HOME"); editingFolder = true; Qt.callLater(function() { folderInput.forceActiveFocus(); folderInput.selectAll(); revealItem(folderInput) }) }
  function saveFolder() { var p = folderInput.text; if (p === "~" || p.indexOf("~/") === 0) p = Quickshell.env("HOME") + p.slice(1); act(["agent-dir", p]) }
  // verbs hand off to the backend one at a time; load and unload are done when a snapshot shows their worker, the rest when the process exits
  function act(args) { if (action.running) { queue = queue.concat([args]); return } lastVerb = args[0]; actionDone = false; pending = true; pendingTimeout.restart(); action.command = [cli].concat(args); action.running = true }
  function scrollBy(amount) { flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + amount)) }
  function revealItem(it) {
    if (!it) return
    var y = it.mapToItem(content, 0, 0).y
    if (y < flick.contentY) scrollBy(y - flick.contentY)
    else if (y + it.height > flick.contentY + flick.height) scrollBy(y + it.height - flick.height - flick.contentY)
  }
  function revealRow(i) { var it = i < ui.rows.length ? rowsRep.itemAt(i) : footRep.itemAt(i - ui.rows.length); if (it) revealItem(it) }
  onCursorAtChanged: if (cursorAt >= 0) Qt.callLater(function() { root.revealRow(root.cursorAt) })
  function navigateCrumb(a) { activate(a); editingFolder = false; Qt.callLater(function() { scrollBy(-1e9); focusContent() }) }
  function activate(a) {
    if (!a) return
    var s = a.split(":"), v = s[0]
    if (working && Model.changesDeployment(a)) return
    if (working && ["home", "card", "gpu", "model", "count", "back"].indexOf(v) >= 0) browseWhileWorking = true
    if (v === "work") { browseWhileWorking = false; home(); return }
    if (v === "choose-folder") editFolder()
    else if (v === "expand") expanded = !expanded
    else if (v === "home") home()
    else if (v === "back") back()
    else if (v === "gpu" || v === "card") { hw = s[1]; count = 1; home(); go("card") }
    else if (v === "count") { count = parseInt(s[1], 10) || 1 }
    else if (v === "model") { slotSel = s[1]; var model = Model.modelById(snap, slotSel), group = model ? Model.cardOfKeys(snap, model.keys) : null; home(); if (group) { hw = group.hardwareId; go("card") } go("model") }
    else if (v === "run") { var recipe = Model.recipeById(snap, s[1]), g = recipe ? Model.cardByHw(snap, recipe.hardwareId) : null; if (!g) return; var plan = Model.loadPlan(snap, recipe, g); home(); act(["load", s[1]].concat(plan.keys)) }
    else if (v === "run-again") { if (!snap.selected) return; home(); act(["load", snap.selected.recipeId]) }
    else if (v === "refresh") { localError = ""; refresh() }
    else if (v === "stop") { home(); act(["unload", s[1]]) }
    else if (v === "stop-download") { if (action.running) return; lastVerb = "unload"; actionDone = false; action.command = [cli, "unload"]; action.running = true }
    else if (v === "launcher-toggle") { launcherOpen = !launcherOpen; launchModelOpen = false; agentOpen = false; cursor = 0 }
    else if (v === "launch-model-toggle") { launchModelOpen = !launchModelOpen; agentOpen = false }
    else if (v === "launch-model") { launchPick = s.slice(1).join(":"); launchModelOpen = false; cursor = 0 }
    else if (v === "agent-toggle") { agentOpen = !agentOpen; launchModelOpen = false }
    else if (v === "agent") { agentPick = s[1]; agentOpen = false; cursor = root.view === "home" ? 3 : 1 }
    else if (v === "open-agent") { if (agentLaunch.running) return; agentLaunch.command = [cli, "agent", s[1], s[2]]; agentLaunch.running = true; say(s[1] + " · " + (Model.modelById(snap, s[2]) || { name: "" }).name) }
    else if (v === "log") { logOpen.running = true; say("log · open") }
  }
  function moveCursor(d) { if (actionable.length) cursor = ((cursor + d) % actionable.length + actionable.length) % actionable.length }
  function cursorRow() { return cursorAt >= 0 ? all[cursorAt] : null }

  // ---------------------------------------------------------------- the backend: one file in, verbs out
  FileView { path: root.stateDir + "/snapshot.json"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: root.take(text()) }
  Process { id: poll; command: [root.cli, "snapshot"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } } }
  Process { id: action; onExited: function(code) { if (root.queue.length) { var n = root.queue[0]; root.queue = root.queue.slice(1); root.lastVerb = n[0]; root.pending = true; pendingTimeout.restart(); action.command = [root.cli].concat(n); action.running = true; return } root.actionDone = true; if (root.lastVerb === "agent-dir") { if (code === 0) { root.editingFolder = false; root.focusContent() } else root.say("Folder not found · enter an existing path") } if (["load", "unload"].indexOf(root.lastVerb) < 0) root.pending = false; root.refresh() } }
  Process { id: agentLaunch; onExited: function(code) { root.refresh(); if (code === 0) root.close() } }
  Process { id: logOpen; command: ["omarchy-launch-tui", "--app-id=org.omarchy.local-ai-log", "less", "+G", root.stateDir + "/log"] }
  Timer { interval: root.pending ? 1000 : root.working ? 2000 : root.opened ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pending = false }
  Timer { interval: 1000; running: root.working; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
  Timer { id: toastTimer; interval: 3500; onTriggered: root.toast = "" }
  onOpenedChanged: { if (opened) { refresh(); if (!working) home() } }
  onToneChanged: cursor = 0
  onViewChanged: { cursor = 0; launchModelOpen = false; editingFolder = false; Qt.callLater(function() { scrollBy(-1e9) }) }

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
    contentHeight: panel.fittedContentHeight(root.expanded ? panel.availableCardHeight : content.implicitHeight)
    Rectangle { anchors.fill: parent; color: root.popupBg }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.editingFolder) return
        var k = event.key, r = root.cursorRow()
        if (k === Qt.Key_F11) root.expanded = !root.expanded
        else if (k === Qt.Key_Escape) { if (root.agentOpen || root.launchModelOpen) { root.agentOpen = false; root.launchModelOpen = false; root.cursor = 0 } else if (root.view === "home" && root.launcherOpen) { root.launcherOpen = false; root.cursor = 0 } else if (root.expanded) root.expanded = false; else if (root.view !== "home") root.back(); else root.close() }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
        else if (k === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) root.editFolder()
        else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) root.scrollBy((k === Qt.Key_PageDown ? 1 : -1) * flick.height * 0.85)
        else if (k === Qt.Key_Home || k === Qt.Key_End) root.scrollBy(k === Qt.Key_Home ? -1e9 : 1e9)
        else if (k === Qt.Key_Down || event.text === "j") root.moveCursor(1)
        else if (k === Qt.Key_Up || event.text === "k") root.moveCursor(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (r) root.activate(r.action) }
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && root.view === "card") { var g = Model.cardByHw(root.snap, root.hw), n = g ? g.keys.length : 1; root.count = Math.max(1, Math.min(n, root.count + (k === Qt.Key_Right ? 1 : -1))) }
        else if (k === Qt.Key_Backspace && root.view !== "home") root.back()
        else return
        event.accepted = true
      }
      Flickable {
        id: flick
        objectName: "local-ai-scroll"
        anchors.fill: parent
        contentWidth: width; contentHeight: content.implicitHeight
        clip: true; interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: root.scrollBy(0)
        onHeightChanged: root.scrollBy(0)
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
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
          PanelHero {
            width: parent.width
            height: implicitHeight + Style.space(24)
            title: root.ui.title
            meta: root.ui.eyebrow
            foreground: root.ink
            fontFamily: root.mono
            iconComponent: Component { Item { implicitWidth: Style.font.display; implicitHeight: width; Rectangle { anchors.centerIn: parent; width: Style.space(16); height: width; color: root.toneColor } } }
          }
          Item { // Breadcrumbs wrap on narrow screens; every destination is a link.
            visible: root.ui.path.length > 1; width: parent.width
            height: visible ? crumbFlow.implicitHeight + Style.space(12) : 0
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.hairline }
            Flow {
              id: crumbFlow
              x: Style.space(6); y: Style.space(6); width: parent.width - Style.space(12); spacing: Style.space(2)
              Repeater { model: root.ui.path
                Button {
                  required property var modelData; required property int index
                  objectName: "breadcrumb-" + index
                  text: (index ? "› " : "") + modelData.n
                  width: Math.min(implicitWidth, crumbFlow.width); clip: true; leftAlign: true
                  fontFamily: root.mono; fontSize: Style.font.caption
                  foreground: index === root.ui.path.length - 1 ? root.ink : root.dim
                  horizontalPadding: Style.space(6); verticalPadding: Style.space(4)
                  focusable: true; tooltipText: modelData.n
                  onClicked: root.navigateCrumb(modelData.action)
                }
              }
            }
          }
          Column {
            visible: root.editingFolder
            width: parent.width
            spacing: Style.space(6)
            Controls.TextField {
              id: folderInput
              width: parent.width
              color: root.ink; selectionColor: root.selectedFill; selectedTextColor: root.ink
              font.family: root.mono; font.pixelSize: Style.font.bodySmall
              placeholderText: "Project folder path"
              background: Rectangle { color: root.popupBg; border.color: root.dim; border.width: 1 }
              onAccepted: root.saveFolder()
              Keys.onEscapePressed: { root.editingFolder = false; root.focusContent() }
            }
            Row {
              spacing: Style.space(6)
              Button { text: "Save folder"; enabled: !root.pending && folderInput.text !== ""; bordered: true; foreground: root.ink; fontFamily: root.mono; onClicked: root.saveFolder() }
              Button { text: "Cancel"; bordered: true; foreground: root.ink; fontFamily: root.mono; onClicked: { root.editingFolder = false; root.focusContent() } }
            }
          }
          CardRow {
            visible: !root.editingFolder && !root.working && (root.view === "model" || (root.view === "home" && root.launcherOpen))
            height: visible ? implicitHeight : 0
            width: parent.width
            p: root
            r: ({ type: "row", compact: true, label: "Project folder", value: (root.snap.agents || {}).directory || Quickshell.env("HOME"), action: "choose-folder" })
          }
          Item { // Rows share the page viewport with headers, editors and bottom actions.
            id: rowsBody
            width: parent.width
            readonly property real inset: Style.space(12)
            height: list.implicitHeight + inset * 2
            Column {
              id: list
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: rowsBody.inset; spacing: Style.space(10)
              Repeater { id: rowsRep; model: root.ui.rows
                CardRow { required property var modelData; required property int index; objectName: "content-row-" + index; r: modelData; p: root; width: list.width; cursor: index === root.cursorAt } }
            }
          }
          Column { // Bottom actions remain reachable through the same scroll viewport.
            visible: root.ui.foot.length > 0; width: parent.width; spacing: 0
            Rectangle { width: parent.width; height: 1; color: root.hairline }
            Column { anchors.left: parent.left; anchors.right: parent.right; anchors.margins: rowsBody.inset; spacing: Style.space(10); topPadding: Style.space(12); bottomPadding: Style.space(12)
              Repeater { id: footRep; model: root.ui.foot
                CardRow { required property var modelData; required property int index; objectName: "footer-row-" + index; r: modelData; p: root; width: parent.width; cursor: root.ui.rows.length + index === root.cursorAt } } }
          }
          Rectangle { // a word that passes
            visible: root.toast !== ""; width: parent.width; height: visible ? Style.space(28) : 0; color: root.recessed
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(12); anchors.verticalCenter: parent.verticalCenter; text: root.toast; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
          }
        }
      }
    }
  }
}
