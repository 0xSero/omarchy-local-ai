import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui.js" as Ui
// Shared model controls, shown either in their own popup or inside the native Agents panel.
// ui.js derives rows and actions; this component owns controller and navigation state.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  manageIpc: false
  property bool editingFolder: false
  function editFolder() { folderInput.text = (snap.agents || {}).directory || Quickshell.env("HOME"); editingFolder = true; Qt.callLater(function() { folderInput.forceActiveFocus(); folderInput.selectAll() }) }
  function saveFolder() { var path = folderInput.text; if (path === "~" || path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.slice(1); act(["agent-dir", path]) }
  property bool embedded: false
  property bool embeddedActive: false
  property alias contentFocus: keys
  property Item overlayHost: null
  property string copyUrl: ""
  property string copyError: ""
  signal dismissRequested()
  signal switchRequested(int direction)
  signal revealRequested(real y, real rowHeight)
  readonly property bool panelActive: embedded ? embeddedActive : opened
  implicitWidth: button.implicitWidth
  implicitHeight: embedded ? content.implicitHeight : button.implicitHeight
  function dismiss() { if (embedded) dismissRequested(); else close() }
  function focusContent() { if (linkOverlay.visible) urlText.forceActiveFocus(); else keys.forceActiveFocus() }
  onPanelActiveChanged: if (!panelActive) linkOverlay.close()
  onEmbeddedActiveChanged: if (embeddedActive) { refresh(); Qt.callLater(focusContent) }

  readonly property string sourceDir: String(Qt.resolvedUrl("..")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: sourceDir + "/bin/omarchy-local-ai"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/local-ai"

  // ---------------------------------------------------------------- native theme, fills and sharp corners
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
  property var snap: ({ state: "uninitialized", operation: {}, models: [], cards: [], recipes: [], gpus: [], share: {}, agents: {}, reason: "", error: "" })
  property var path: ["home"]           // home › card › model
  readonly property string view: path[path.length - 1]
  property string hw: ""                // the card type open
  property int count: 1                 // how many of it
  property string pick: ""              // the recipe picked
  property string slotSel: ""           // the running model open
  property bool launcherOpen: false
  property string launchPick: ""
  property bool launchModelOpen: false
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
  readonly property var ui: Ui.build({ snap: snap, view: view, hw: hw, count: count, pick: pick, slotSel: slotSel, launcherOpen: launcherOpen, launchPick: launchPick, launchModelOpen: launchModelOpen, agentPick: agentPick, agentOpen: agentOpen, copied: copied, pending: pending, lastVerb: lastVerb, elapsed: elapsed, localError: localError })
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
    if (v === "choose-folder") root.editFolder()
    else if (v === "expand") expanded = !expanded
    else if (v === "home") home()
    else if (v === "back") back()
    else if (v === "gpu") { var group = Ui.cardByHw(snap, s[1]), running = group ? Ui.groupModels(snap, group) : []; hw = s[1]; count = 1; pick = ""; home(); go("card"); if (running.length === 1) { slotSel = running[0].recipeId; go("model") } }
    else if (v === "card") { hw = s[1]; count = 1; pick = ""; home(); go("card") }
    else if (v === "count") { count = parseInt(s[1], 10) || 1; pick = "" }
    else if (v === "pick") pick = s[1]
    else if (v === "model") { slotSel = s[1]; var model = Ui.modelById(snap, slotSel), group = model ? Ui.cardOfKeys(snap, model.keys) : null; home(); if (group) { hw = group.hardwareId; go("card") } go("model") }
    else if (v === "run") { if (working) return; var g = Ui.cardByHw(snap, hw), free = g ? Ui.freeKeys(snap, g) : []; home(); act(["run", s[1], Ui.freest(snap, free) || (g ? g.keys[0] : "")].filter(function(x) { return x !== "" })) }
    else if (v === "run-again") { if (working) return; home(); act(["load"]) }
    else if (v === "refresh") { localError = ""; refresh() }
    else if (v === "stop") { if (working) return; home(); act(["unload", s[1]]) }
    else if (v === "stop-download") { if (action.running) return; lastVerb = "unload"; actionDone = false; action.command = [cli, "unload"]; action.running = true }
    else if (v === "launcher-toggle") { launcherOpen = !launcherOpen; launchModelOpen = false; agentOpen = false; cursor = 0 }
    else if (v === "launch-model-toggle") { launchModelOpen = !launchModelOpen; agentOpen = false }
    else if (v === "launch-model") { launchPick = s.slice(1).join(":"); launchModelOpen = false; cursor = 0 }
    else if (v === "agent-toggle") { agentOpen = !agentOpen; launchModelOpen = false }
    else if (v === "agent") { agentPick = s[1]; agentOpen = false; cursor = root.view === "home" ? 3 : 1 }
    else if (v === "open-agent") { if (agentLaunch.running) return; agentLaunch.command = [cli, "open-agent", s[1], s[2]]; agentLaunch.running = true; say(s[1] + " · " + (Ui.modelById(snap, s[2]) || { name: "" }).name) }
    else if (v === "share") { if (working) return; act(["share"]) }
    else if (v === "update") { if (working) return; act(["update"]) }
    else if (v === "update-check") { if (working) return; act(["update", "--check"]) }
    else if (v === "copy") { var m = Ui.modelById(snap, s[1]); if (copy.running || !m || !m.shareUrl) return; copyUrl = m.shareUrl; copyError = ""; linkOverlay.open() }
    else if (v === "log") { logOpen.running = true; say("log · open") }
  }
  function copyLink() {
    if (copy.running || !copyUrl) return
    copyError = ""
    copy.command = ["bash", "-c", "command -v wl-copy >/dev/null 2>&1 || exit 127; printf %s \"$1\" | wl-copy", "_", copyUrl]
    copy.running = true
  }
  function moveCursor(d) { if (actionable.length) cursor = ((cursor + d) % actionable.length + actionable.length) % actionable.length }
  function cursorRow() { return cursorAt >= 0 ? all[cursorAt] : null }

  // ---------------------------------------------------------------- the controller
  FileView { path: root.stateDir + "/snapshot.json"; watchChanges: true; onFileChanged: reload(); onLoaded: root.take(text()) }
  Process { id: poll; command: [root.cli, "snapshot"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } } }
  Process { id: action; onExited: function(code) { if (root.queue.length) { var n = root.queue[0]; root.queue = root.queue.slice(1); root.lastVerb = n[0]; root.pending = true; pendingTimeout.restart(); action.command = [root.cli].concat(n); action.running = true; return } root.actionDone = true; if (root.lastVerb === "agent-dir") { if (code === 0) { root.editingFolder = false; root.focusContent() } else root.say("Folder not found · enter an existing path") } if (["run", "load", "unload", "share"].indexOf(root.lastVerb) < 0) root.pending = false; if (code !== 0 && root.lastVerb === "update") root.say("update failed · log"); root.refresh() } }
  Process { id: agentLaunch; onExited: function(code) { root.refresh(); if (code === 0) root.dismiss() } }
  Process { id: copy; onExited: function(code) { if (code === 0) { root.copied = true; copiedTimer.restart(); linkOverlay.close(); root.say("link copied") } else root.copyError = code === 127 ? "wl-copy is missing. Select the URL to copy it manually." : "Copy failed. Try again or select the URL." } }
  Process { id: logOpen; command: ["omarchy-launch-tui", "--app-id=org.omarchy.local-ai-log", "less", "+G", root.stateDir + "/log"] }
  Timer { interval: root.pending ? 1000 : root.working ? 2000 : root.panelActive ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pending = false }
  Timer { interval: 1000; running: root.working; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
  Timer { id: toastTimer; interval: 3500; onTriggered: root.toast = "" }
  Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = false }
  // Sharing opens a fixed overlay; copying is an explicit action.
  onSnapChanged: { if (lastVerb === "share" && slotSel !== "" && view === "model" && !working) { var m = Ui.modelById(snap, slotSel); if (m && m.shareUrl) { lastVerb = ""; activate("copy:" + slotSel) } } }
  onOpenedChanged: { if (opened) { refresh(); if (!working) home() } }
  onToneChanged: { if (tone === "error" || (tone === "work" && lastVerb !== "share")) home(); cursor = 0 }
  onViewChanged: { cursor = 0; launchModelOpen = false; editingFolder = false; if (body) body.contentY = 0 }

  Controls.Popup {
    id: linkOverlay
    parent: root.embedded ? root.overlayHost : popupContent
    x: 0; y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    padding: Style.space(16)
    modal: true
    dim: false
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape
    background: Rectangle { color: root.popupBg }
    onOpened: { urlText.forceActiveFocus(); urlText.selectAll() }
    onClosed: { root.copyUrl = ""; root.copyError = ""; root.focusContent() }
    contentItem: Item {
      Column {
        id: linkHeading
        width: parent.width
        spacing: Style.space(8)
        PanelSectionHeader { width: parent.width; text: "Share model"; foreground: root.ink; fontFamily: root.mono }
        Text { width: parent.width; text: "Copy this URL to use the model on your tailnet."; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
      }
      Controls.ScrollView {
        anchors { top: linkHeading.bottom; bottom: linkActions.top; left: parent.left; right: parent.right; topMargin: Style.space(16); bottomMargin: Style.space(16) }
        clip: true
        Controls.TextArea {
          id: urlText
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier))) { root.copyLink(); event.accepted = true }
          }
          text: root.copyUrl
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.WrapAnywhere
          color: root.ink
          selectionColor: root.selectedFill
          selectedTextColor: root.ink
          font.family: root.mono
          font.pixelSize: Style.font.body
          background: Rectangle { color: root.recessed }
        }
      }
      Column {
        id: linkActions
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: Style.space(12)
        Text { visible: root.copyError !== ""; width: parent.width; text: root.copyError; color: root.urgent; font.family: root.mono; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
        Row {
          spacing: Style.space(8)
          Button { text: copy.running ? "Copying…" : "Copy URL"; enabled: !copy.running; bordered: true; foreground: root.ink; fontFamily: root.mono; onClicked: root.copyLink() }
          Button { text: "Close"; bordered: true; foreground: root.ink; fontFamily: root.mono; onClicked: linkOverlay.close() }
        }
      }
    }
  }

  IpcHandler {
    enabled: !root.embedded
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
    visible: !root.embedded
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
    anchorItem: root.embedded ? null : button
    owner: root
    bar: root.bar
    open: !root.embedded && root.opened
    focusTarget: keys
    padding: 0
    borderSpec: Border.flat(root.popupLine, 1)
    contentWidth: root.expanded ? panel.availableCardWidth : panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    readonly property real ceiling: panel.fittedContentHeight(root.expanded ? panel.availableCardHeight : Style.space(720)) - panel.verticalContentInset
    // Fit the scrolling body to the screen as well as the compact panel cap.
    Rectangle { anchors.fill: parent; color: root.popupBg }
    Item { id: popupContent; anchors.fill: parent }
    Item {
      id: keys
      parent: root.embedded ? root : popupContent
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.editingFolder) return
        var k = event.key, r = root.cursorRow()
        if (k === Qt.Key_F11 && !root.embedded) root.expanded = !root.expanded
        else if (k === Qt.Key_Escape) { if (root.editingFolder) { root.editingFolder = false; root.focusContent() } else if (root.agentOpen || root.launchModelOpen) { root.agentOpen = false; root.launchModelOpen = false; root.cursor = 0 } else if (root.view === "home" && root.launcherOpen) { root.launcherOpen = false; root.cursor = 0 } else if (root.expanded) root.expanded = false; else if (root.view !== "home") root.back(); else root.dismiss() }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { var direction = (event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1; if (root.embedded) root.switchRequested(direction); else root.switchPanel(direction) }
        else if (k === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) root.editFolder()
        else if (k === Qt.Key_Down || event.text === "j") root.moveCursor(1)
        else if (k === Qt.Key_Up || event.text === "k") root.moveCursor(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (r) root.activate(r.action) }
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && root.view === "card") { var g = Ui.cardByHw(root.snap, root.hw), n = g ? g.keys.length : 1; root.count = Math.max(1, Math.min(n, root.count + (k === Qt.Key_Right ? 1 : -1))); root.pick = "" }
        else if (k === Qt.Key_Backspace && root.view !== "home") root.back()
        else return
        event.accepted = true
      }
      Column {
        id: content
        anchors.left: parent.left; anchors.right: parent.right
        spacing: root.embedded ? Style.space(10) : 0
        Item {
          id: sizeControl
          visible: !root.embedded
          width: parent.width; height: visible ? Style.space(32) : 0
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
          id: slab
          visible: !root.embedded
          width: parent.width
          height: visible ? implicitHeight + Style.space(24) : 0
          title: root.ui.title
          meta: root.ui.eyebrow
          foreground: root.ink
          fontFamily: root.mono
          iconComponent: Component {
            Item {
              implicitWidth: Style.font.display; implicitHeight: width
              Rectangle { anchors.centerIn: parent; width: Style.space(16); height: width; color: root.toneColor }
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
        Column {
          id: folderEditor
          visible: root.editingFolder
          width: parent.width
          spacing: Style.space(6)
          Controls.TextField {
            id: folderInput
            width: parent.width
            color: root.ink
            selectionColor: root.selectedFill
            selectedTextColor: root.ink
            font.family: root.mono
            font.pixelSize: Style.font.bodySmall
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
          id: folderRow
          visible: !root.editingFolder && !root.working && (root.view === "model" || (root.view === "home" && root.launcherOpen))
          height: visible ? implicitHeight : 0
          width: parent.width
          p: root
          r: ({ type: "row", compact: true, label: "Project folder", value: (root.snap.agents || {}).directory || Quickshell.env("HOME"), action: "choose-folder" })
        }
        Flickable { // ---- the rows: the one part that scrolls
          id: body
          width: parent.width
          readonly property real room: panel.ceiling - sizeControl.height - slab.height - crumb.height - foot.height - toastBox.height - (folderRow.visible ? folderRow.height : folderEditor.visible ? folderEditor.height : 0)
          readonly property real inset: root.embedded ? 0 : Style.space(12)
          height: root.embedded ? contentHeight : Math.max(0, root.expanded ? room : Math.min(contentHeight, room))
          contentHeight: list.implicitHeight + inset * 2; clip: !root.embedded; interactive: !root.embedded; boundsBehavior: Flickable.StopAtBounds
          Column {
            id: list
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: body.inset; spacing: Style.space(10)
            Repeater { id: rowsRep; model: root.ui.rows
              CardRow { required property var modelData; required property int index; r: modelData; p: root; x: r.child ? Style.space(18) : 0; width: list.width - x; cursor: index === root.cursorAt } }
          }
          function reveal(i) { // keep the cursor row in view
            var it = i < root.ui.rows.length ? rowsRep.itemAt(i) : footRep.itemAt(i - root.ui.rows.length); if (!it) return
            if (root.embedded) { root.revealRequested(it.mapToItem(root, 0, 0).y, it.height); return }
            if (i >= root.ui.rows.length) return
            var y = it.y + Style.space(12), h = it.height
            if (y < contentY) contentY = Math.max(0, y - Style.space(12)); else if (y + h > contentY + height) contentY = Math.min(contentHeight - height, y + h - height + Style.space(12))
          }
          Connections { target: root; function onCursorAtChanged() { if (root.cursorAt >= 0) Qt.callLater(function() { body.reveal(root.cursorAt) }) } }
        }
        Column { // ---- the footer: the verbs, pinned
          id: foot
          visible: root.ui.foot.length > 0; width: parent.width; spacing: 0
          Rectangle { width: parent.width; height: 1; color: root.hairline; visible: body.contentHeight > body.height }
          Column { anchors.left: parent.left; anchors.right: parent.right; anchors.margins: body.inset; spacing: Style.space(10); topPadding: Style.space(12); bottomPadding: Style.space(12)
            Repeater { id: footRep; model: root.ui.foot
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
