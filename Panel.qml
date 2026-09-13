import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
// The command stack: one recessed state slab (state, title, orb) over one raised body of rows.
// Every row is a noun and a datum; drill-down is a path stack; the orb never stops moving.
// Renders purely from the snapshot file the controller writes; nothing here knows a model name,
// a flag, or a docker word.
Panel {
  id: root
  moduleName: "sero.local-ai"
  ipcTarget: "sero.local-ai"
  manageIpc: false
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string sourceDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string cli: sourceDir + "/bin/omarchy-local-ai"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/local-ai"

  // ---------------------------------------------------------------- the locked palette
  // The panel is matte black on purpose: fills, not borders, sharp corners, one accent for work
  // and one urgent for refusals. The bar icon follows the theme; the card follows the design.
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

  // ---------------------------------------------------------------- snapshot
  property var snap: ({ state: "uninitialized", operation: {}, model: null, reason: "", share: {}, agents: {}, error: "", cards: [], recipes: [], stats: {}, port: {} })
  readonly property string state: snap.state || "uninitialized"
  readonly property var model: snap.model || null
  readonly property var operation: snap.operation || ({})
  readonly property var share: snap.share || ({})
  readonly property var agentList: (snap.agents && snap.agents.launchable) || []
  readonly property var cards: snap.cards || []
  readonly property var recipes: snap.recipes || []
  readonly property var selected: snap.selected || null
  readonly property var running: snap.running || null
  readonly property var stats: snap.stats || ({})
  readonly property int port: (snap.port && snap.port.number) || 12434
  readonly property var registryList: snap.registryList || []
  readonly property int cardCount: cards.reduce(function(n, c) { return n + (c.count || 0) }, 0)
  // pending: a verb was just issued and no snapshot has confirmed the worker yet. The panel treats
  // it as busy so the click has an immediate effect instead of a dead second while the worker starts.
  property bool pending: false
  readonly property bool working: ["download", "starting", "unload", "share"].indexOf(state) >= 0
  readonly property bool busy: working || pending
  property int elapsed: 0
  readonly property int expected: operation.expectedSeconds || 0
  readonly property int progress: operation.percent > 0 ? operation.percent
    : (expected > 0 && elapsed > 0 ? Math.min(95, Math.round(elapsed * 100 / expected)) : 0)
  readonly property bool loaded: state === "ready"
  readonly property bool hasRunning: !!running
  readonly property bool older: hasRunning && !!running.older
  readonly property bool swap: loaded && !!selected && !!running && !older && running.recipeId !== selected.recipeId
  readonly property bool blocked: !loaded && !busy && (snap.reason || "") !== ""
  readonly property string defaultAgent: (snap.agents && snap.agents.default) || ""
  property string agentPick: ""
  readonly property string agentSel: agentPick !== "" && agentList.indexOf(agentPick) >= 0 ? agentPick
    : (agentList.indexOf(defaultAgent) >= 0 ? defaultAgent : (agentList.length > 0 ? agentList[0] : ""))
  property string localError: ""
  // the four states the card can be in; every overlay (shared, older, swap, blocked) rides on one of them
  readonly property string ui: localError !== "" ? "error" : busy ? "working" : loaded ? "ready" : (state === "error" || blocked) ? "error" : "idle"
  readonly property color stateColor: ui === "working" ? accent : ui === "error" ? urgent : ui === "ready" ? ink : dim
  readonly property string homeDir: Quickshell.env("HOME") || ""
  function tilde(p) { return homeDir && p.indexOf(homeDir) === 0 ? "~" + p.slice(homeDir.length) : p }

  function refresh() { if (!poll.running) poll.running = true }
  // load and unload hand off to a worker, so pending lasts until a snapshot shows it (or the
  // timeout); every other verb finishes when its process exits, and the card must not stay dead
  // for 20 seconds after a card pick or an agent launch.
  property string lastVerb: ""
  property bool actionDone: false
  function act(args) { if (busy || action.running) return; lastVerb = args[0]; actionDone = false; pending = true; pendingTimeout.restart(); action.command = [cli].concat(args); action.running = true }
  function take(json) {
    try { snap = JSON.parse(json); localError = ""; if (working || snap.error || (actionDone && lastVerb !== "load" && lastVerb !== "unload")) pending = false; tick() }
    catch (e) { if (json.trim() === "") { localError = "no answer"; pending = false } }
  }
  function tick() {
    var t = Date.parse(operation.startedAt || "")
    elapsed = working && !isNaN(t) ? Math.max(0, Math.round((Date.now() - t) / 1000)) : 0
  }
  function mmss(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
  function gb(n) { return n >= 100 ? Math.round(n) + " GB" : (Math.round(n * 10) / 10) + " GB" }
  function kmg(n) { return n >= 1e6 ? (Math.round(n / 1e5) / 10) + "M" : n >= 1e3 ? (Math.round(n / 100) / 10) + "K" : String(n) }
  // The launch is its own process: the panel closes only when the terminal actually opened, and a
  // refusal (no model, wedged launcher) stays on screen instead of vanishing with the panel.
  function openAgent() {
    if (!loaded || agentSel === "" || busy || action.running || agentLaunch.running) return
    agentLaunch.command = [cli, "open-agent", agentSel]; agentLaunch.running = true; toastSay(agentSel + " · open")
  }

  // ---------------------------------------------------------------- navigation: a path stack
  property var path: ["main"]
  readonly property string view: path[path.length - 1]
  property string cardSel: ""          // the card group whose recipes are open
  property string query: ""            // registry search
  property int cursor: 0
  property string tokenWindow: "today"
  property bool copied: false
  property string toast: ""
  function enterView(v) { if (view !== v) { var p = path.slice(); p.push(v); path = p } cursor = 0 }
  function leaveView() { if (path.length > 1) { var p = path.slice(); p.pop(); path = p } query = ""; cursor = 0 }
  function resetPath() { path = ["main"]; query = ""; cursor = 0 }
  function trail() { var names = { main: "local ai", share: "share" }; return path.map(function(v) { return names[v] || v }).join(" / ") }
  function toastSay(t) { toast = t; toastTimer.restart() }

  // ---------------------------------------------------------------- rows
  // One grammar for every surface: {label, value, action, kind, selected, disabled, type}.
  // kind: row (info or navigation), action, primary, danger. type: row, status, search, tabs, stat, text.
  function row(label, value, action, o) { o = o || {}; return { label: label, value: value || "", action: action || "", kind: o.kind || "row", selected: !!o.selected, disabled: !!o.disabled, type: o.type || "row", urgent: !!o.urgent, extra: o.extra || null } }
  function cardLabel(c) { return (c.count > 1 ? c.count + "× " : "") + c.name }
  function chosenCard() { for (var i = 0; i < cards.length; i++) if (cards[i].chosen) return cards[i]; return cards.length ? cards[0] : null }
  function cardByHw(hw) { for (var i = 0; i < cards.length; i++) if (cards[i].hardwareId === hw) return cards[i]; return null }
  function shortError() {
    var e = localError || snap.error || snap.reason || ""
    if (localError) return "no answer"
    if (snap.reason && !snap.error) {
      if (/^no supported GPU/.test(e)) return "no card"
      if (/^no validated recipe/.test(e)) return "no recipe"
      if (/^port /.test(e)) return "port busy"
      if (/driver/.test(e)) return "driver"
      if (/^recipe needs/.test(e)) return "cards short"
      return "refused"
    }
    if (/out of memory|OOM|VRAM/i.test(e)) return "out of VRAM"
    if (/below the .* floor/.test(e)) return "too slow"
    if (/stopped unexpectedly/.test(e)) return "stopped"
    if (/acceptance failed/.test(e)) return "acceptance failed"
    if (/did not answer|not answering/.test(e)) return "no answer"
    if (/Docker|docker/.test(e)) return "docker"
    if (/space/.test(e)) return "disk full"
    if (/refused|dismissed/.test(e)) return "refused"
    if (/network|route|registry/.test(e)) return "no route"
    return "error"
  }
  function reasonRow() {
    var e = snap.reason || ""
    if (/^no supported GPU/.test(e)) return row("card", "none", "", { urgent: true })
    if (/^no validated recipe/.test(e)) { var c = chosenCard(); return row("recipe", "none · " + (c ? c.name : "card"), "", { urgent: true }) }
    if (/^port /.test(e)) return row("port", port + " · busy", "", { urgent: true })
    if (/driver ([0-9.]+)/.test(e)) return row("driver", "needs " + e.match(/driver ([0-9.]+)/)[1], "", { urgent: true })
    if (/^recipe needs/.test(e)) return row("cards", e.replace(/^recipe needs /, ""), "", { urgent: true })
    return row("recipe", "refused", "", { urgent: true })
  }
  function recoveryCount() { return 2 + (cards.length > 1 ? 1 : 0) }
  function stateCopy() { // [eyebrow, title, subtitle]
    var name = selected ? selected.name : (model ? model.name : "")
    var runName = running ? running.name : name
    var n = selected ? selected.cards : 1
    if (ui === "working") {
      if (pending && !working) return ["working", name || "Local AI", ""]
      var verb = { download: "download", starting: "starting", unload: "stop", share: "share" }[state] || state
      return ["working", state === "unload" ? (runName || "Local AI") : (name || verb), verb]
    }
    if (ui === "ready") return ["ready", runName || "Local AI", "running on " + n + " card" + (n === 1 ? "" : "s") + (share.active ? " · share on" : "") + (older ? " · older" : "")]
    if (ui === "error") return ["error", shortError(), ""]
    return ["idle", selected && selected.onDisk ? selected.name : "Local AI", selected ? "cards · " + n : ""]
  }
  function mainRows() {
    var r = []
    if (localError) { r.push(row("plugin", "no answer", "", { urgent: true })); r.push(row("run again", "return", "run-again", { kind: "primary" })); return r }
    if (ui === "working") {
      var verb = { download: "download", starting: "starting", unload: "stop", share: "share" }[state] || "starting"
      var v = progress > 0 ? progress + "%" : (elapsed > 0 ? mmss(elapsed) + (expected > 0 ? " · " + mmss(expected) : "") : "…")
      r.push(row(verb, v, "", { type: "status" }))
      if (operation.detail && operation.detail !== "starting") r.push(row("step", operation.detail, ""))
      return r
    }
    if (ui === "ready") {
      if (older) r.push(row("update + restart", selected ? selected.name : "recipe", "update-restart", { kind: "primary" }))
      else if (swap) r.push(row("run", "swap · " + selected.name, "swap", { kind: "primary" }))
      else if (agentSel !== "") r.push(row("open agent", agentSel, "open-agent", { kind: "primary" }))
      else r.push(row("agent", "none installed", "", { urgent: true }))
      r.push(row("runtime", "3 · stats live ›", "runtime"))
      r.push(row("stop", share.active ? "run + share" : "run", "stop", { kind: "danger" }))
      return r
    }
    if (ui === "error") {
      if (blocked && !snap.error) r.push(reasonRow())
      else r.push(row("run again", "return", "run-again", { kind: "primary" }))
      r.push(row("recovery", recoveryCount() + " ›", "recovery"))
      return r
    }
    // idle: state, the claimed card or card group, the next action, the options count
    var c = chosenCard(); var claimed = selected ? selected.cards : 1
    r.push(row(claimed > 1 ? "cards" : "card", (claimed > 1 ? claimed + " claimed" : (c ? cardLabel(c) : "none")) + " ›", "cards"))
    if (selected) r.push(row(selected.onDisk ? "run" : "download + run", selected.onDisk ? "on disk" : gb(selected.sizeGb), "run", { kind: "primary" }))
    else r.push(row("run", "unavailable", "", { disabled: true }))
    r.push(row("options", "3 ›", "options"))
    return r
  }
  function pickerRows() {
    var r = [], i
    if (view === "cards") {
      for (i = 0; i < cards.length; i++) {
        var c = cards[i], v
        if (!c.recipe) v = c.totalGb + " GB · no recipe"
        else if (c.claimed > 0 && c.count > 1) v = c.totalGb + " GB · " + c.claimed + " claimed" + (c.idle ? " · " + c.idle + " idle" : "")
        else v = c.totalGb + " GB" + (c.count > 1 ? " total" : "") + " ›"
        r.push(row(cardLabel(c), v, c.recipe ? "recipes:" + c.hardwareId : "pick-card:" + c.keys[0], { selected: c.chosen }))
      }
      if (!cards.length) r.push(row("card", "none"))
      if (snap.gpuPinned) r.push(row("auto", "largest card with a recipe", "pick-card:auto"))
    } else if (view === "recipes") {
      var card = cardByHw(cardSel); var list = card && card.recipe ? [card.recipe] : []
      for (i = 0; i < list.length; i++) r.push(row(list[i].name, gb(list[i].sizeGb) + " · " + (list[i].onDisk ? "on disk" : "download") + " · cards: " + list[i].cards, "pick-recipe:" + list[i].hardwareId, { selected: !!selected && selected.recipeId === list[i].id }))
      if (!list.length) r.push(row("recipe", "none"))
    } else if (view === "options") {
      var cc = chosenCard()
      r.push(row("recipe", (selected ? selected.name : "none") + " ›", cc && cc.recipe ? "recipes:" + cc.hardwareId : "cards"))
      r.push(row("port", String(port)))
      r.push(row("registry", registryList.length + " ›", "registry"))
    } else if (view === "registry") {
      r.push(row("search", "", "", { type: "search" }))
      var q = query.trim().toLowerCase(), n = 0, shown = 0
      for (i = 0; i < registryList.length; i++) {
        var e = registryList[i]
        if (q && (e.model + " " + e.card + " " + e.hardwareId).toLowerCase().indexOf(q) < 0) continue
        n++; if (shown < 8) { shown++; r.push(row(e.model, e.card + " · " + gb(e.sizeGb))) }
      }
      if (!n) r.push(row("recipe", "no match"))
      else if (n > shown) r.push(row("more", (n - shown) + " · type to filter"))
    } else if (view === "runtime") {
      r.push(agentList.length ? row("agent", agentSel + " ›", "agents") : row("agent", "none installed", "", { urgent: true }))
      r.push(row("stats", "live ›", "stats"))
      r.push(row("share", (share.active ? "on" : "off") + " ›", "share"))
    } else if (view === "agents") {
      for (i = 0; i < agentList.length; i++) r.push(row(agentList[i], agentList[i] === agentSel ? "selected" : "", "pick-agent:" + agentList[i], { selected: agentList[i] === agentSel }))
      if (!agentList.length) r.push(row("agent", "none"))
    } else if (view === "stats") {
      r.push(row("window", tokenWindow, "window", { type: "tabs" }))
      var d = stats.decodeTps || 0, p = stats.prefillTps || 0
      r.push(row(d > 0 ? "avg decode" : "decode · validated", (d > 0 ? d : (stats.validatedTps || 0)) + " tok/s", "", { type: "stat", extra: { label2: "avg prefill", value2: p > 0 ? p + " tok/s" : "n/a" } }))
      r.push(row("tokens served · " + tokenWindow, kmg((stats.tokens || {})[tokenWindow] || 0), "", { type: "stat", extra: { label2: "vram in use", value2: stats.vramUsedGb !== null && stats.vramUsedGb !== undefined ? stats.vramUsedGb + " / " + stats.vramTotalGb + " GB" : "n/a" } }))
    } else if (view === "share") {
      if (!share.available) r.push(row("share", "no tailscale", "", { disabled: true }))
      else if (!share.active) r.push(row("share", "off · return", "share-toggle", { kind: "primary" }))
      else { r.push(row("share", "on", "share-toggle")); r.push(row("endpoint", (share.url || "").replace(/^https?:\/\//, "") + " · " + (copied ? "copied" : "copy"), "copy")) }
      if (share.active) r.push(row("key", tilde(share.keyFile || "")))
      if (share.error) r.push(row("share", share.error, "", { urgent: true, type: "text" }))
    } else if (view === "recovery") {
      r.push(row("run again", "return", "run-again", { kind: "primary" }))
      if (cards.length > 1) r.push(row("card", "choose ›", "cards"))
      r.push(row("log", "open ›", "log"))
      var why = localError ? "the plugin did not answer (see " + tilde(stateDir) + "/log)" : (snap.error || snap.reason || "")
      if (why) r.push(row("reason", why, "", { type: "text" }))
    }
    return r
  }
  readonly property var rows: view === "main" ? mainRows() : pickerRows()
  readonly property var actionable: rows.map(function(r, i) { return r.action && !r.disabled ? i : -1 }).filter(function(i) { return i >= 0 }).concat(view === "main" ? [] : [-2])   // -2: the back row
  function pickerCount() {
    if (view === "cards") return cardCount + " · " + cards.length + (cards.length === 1 ? " type" : " types")
    if (view === "recipes") { var c = cardByHw(cardSel); return c && c.recipe ? "1" : "0" }
    if (view === "options") return "3"
    if (view === "registry") return String(registryList.length)
    if (view === "runtime") return "3"
    if (view === "agents") return String(agentList.length)
    if (view === "stats") return "4"
    if (view === "share") return "tailnet"
    if (view === "recovery") return String(recoveryCount())
    return ""
  }
  function moveCursor(d) { if (!actionable.length) return; cursor = ((cursor + d) % actionable.length + actionable.length) % actionable.length }
  function cursorRow() { if (!actionable.length) return null; var i = actionable[Math.min(cursor, actionable.length - 1)]; return i === -2 ? { action: "back", type: "row" } : rows[i] }
  function activateCursor() { var r = cursorRow(); if (r) activate(r.action) }
  function cycleWindow(d) { var w = ["hour", "today", "week"]; tokenWindow = w[((w.indexOf(tokenWindow) + d) % 3 + 3) % 3] }
  function activate(a) {
    var parts = a.split(":"), verb = parts[0]
    if (verb === "cards" || verb === "options" || verb === "registry" || verb === "runtime" || verb === "agents" || verb === "stats" || verb === "share" || verb === "recovery") enterView(verb)
    else if (verb === "recipes") { cardSel = parts[1]; enterView("recipes") }
    else if (verb === "pick-card") { act(["gpu", parts[1]]); leaveView() }
    else if (verb === "pick-recipe") { var c = cardByHw(parts[1]); if (c && !c.chosen) act(["gpu", c.keys[0]]); leaveView() }
    else if (verb === "pick-agent") { agentPick = parts[1]; leaveView() }
    else if (verb === "run" || verb === "run-again" || verb === "swap" || verb === "update-restart") { if (localError) { refresh(); return } resetPath(); act(["load"]) }
    else if (verb === "stop") { resetPath(); act(["unload"]) }
    else if (verb === "share-toggle") act(["share"])
    else if (verb === "copy") { copy.command = ["wl-copy", "--", (share.url || "")]; copy.running = true; copied = true; copiedTimer.restart() }
    else if (verb === "open-agent") openAgent()
    else if (verb === "window") cycleWindow(1)
    else if (verb === "log") { logOpen.running = true; toastSay("log · open") }
    else if (verb === "back") leaveView()
  }

  // The controller rewrites the snapshot after every step; watching the file is what makes
  // progress live. The timer catches reality changing outside an operation.
  FileView {
    id: snapshotFile
    path: root.stateDir + "/snapshot.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.take(text())
  }
  Process {
    id: poll
    command: [root.cli, "snapshot"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { if (text.length <= 262144) root.take(text) } }
  }
  Process { id: action; onExited: { root.actionDone = true; root.refresh() } }
  Process { id: agentLaunch; onExited: function(code) { root.refresh(); if (code === 0) root.close() } }
  Process { id: copy }
  Process { id: logOpen; command: ["omarchy-launch-tui", "--app-id=org.omarchy.local-ai-log", "less", "+G", root.stateDir + "/log"] }
  // Poll fast while something runs, whether or not the panel is open, so the bar icon starts and
  // stops moving with the operation; slow when idle. The file watch above makes this a backstop.
  Timer { interval: root.pending ? 1000 : root.working ? 2000 : root.opened ? 10000 : 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { id: pendingTimeout; interval: 20000; onTriggered: root.pending = false }
  Timer { interval: 1000; running: root.working; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
  Timer { id: toastTimer; interval: 1800; onTriggered: root.toast = "" }
  Timer { id: copiedTimer; interval: 1400; onTriggered: root.copied = false }

  onOpenedChanged: { if (opened) { refresh(); if (!loaded && !busy) resetPath() } }
  // a state change under an open drill (download finished, model stopped) lands on the main surface
  onUiChanged: { if (view !== "main" && (ui === "working" || ui === "error")) resetPath(); cursor = 0 }
  onViewChanged: cursor = 0

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function load(): string { root.act(["load"]); return "ok" }
    function unload(): string { root.act(["unload"]); return "ok" }
    function agent(): string { root.openAgent(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        // The bar mark: one square. Faint idle, ink ready, accent blinking while working, urgent on error.
        Rectangle {
          anchors.centerIn: parent; width: Style.space(8); height: width; radius: 0
          color: root.ui === "ready" ? (root.bar ? root.bar.foreground : root.ink) : root.ui === "working" ? root.accent : root.ui === "error" ? (root.bar ? root.bar.urgent : root.urgent) : Util.alpha(root.bar ? root.bar.foreground : root.ink, 0.4)
          SequentialAnimation on opacity {
            running: root.ui === "working"; loops: Animation.Infinite; alwaysRunToEnd: true
            NumberAnimation { to: 0.3; duration: 500 } NumberAnimation { to: 1; duration: 500 }
          }
        }
      }
    }
    tooltipText: "Local AI · " + root.stateCopy()[1]
    onPressed: function(code) { if (code === Qt.RightButton && root.loaded) root.openAgent(); else root.toggle() }
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)
    Rectangle { anchors.fill: parent; color: root.popupBg }
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var k = event.key
        if (k === Qt.Key_Escape) { if (root.view !== "main") root.leaveView(); else root.close(); event.accepted = true; return }
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { root.switchPanel((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1); event.accepted = true; return }
        if (k === Qt.Key_Down) { root.moveCursor(1); event.accepted = true; return }
        if (k === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true; return }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { root.activateCursor(); event.accepted = true; return }
        var r = root.cursorRow()
        if ((k === Qt.Key_Left || k === Qt.Key_Right) && r && r.type === "tabs") { root.cycleWindow(k === Qt.Key_Right ? 1 : -1); event.accepted = true; return }
        if (root.view === "registry") { // the search field: typing filters, arrows still navigate
          if (k === Qt.Key_Backspace) { root.query = root.query.slice(0, -1); event.accepted = true; return }
          if (event.text && event.text.length === 1 && !(event.modifiers & Qt.ControlModifier) && event.text >= " ") { root.query += event.text; event.accepted = true; return }
        } else {
          if (event.text === "j") { root.moveCursor(1); event.accepted = true; return }
          if (event.text === "k") { root.moveCursor(-1); event.accepted = true; return }
        }
      }
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0
        // ---------------------------------------------------------------- the state slab
        Rectangle {
          width: parent.width; color: root.recessed
          implicitHeight: Math.max(Style.space(104), slabRow.implicitHeight + Style.space(32))
          Row {
            id: slabRow
            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(16); anchors.rightMargin: Style.space(16)
            spacing: Style.space(14)
            Orb { id: orb; anchors.verticalCenter: parent.verticalCenter }
            Column {
              width: parent.width - orb.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)
              Text { text: root.stateCopy()[0]; color: root.stateColor; font.family: root.mono; font.pixelSize: Style.fontPx(0.75); font.bold: true; font.letterSpacing: Style.fontPx(0.75) * 0.14; font.capitalization: Font.AllUppercase; textFormat: Text.PlainText }
              Text { width: parent.width; text: root.stateCopy()[1]; color: root.ink; font.family: root.mono; font.pixelSize: Style.fontPx(1.583); font.bold: true; font.letterSpacing: -Style.fontPx(1.583) * 0.03; elide: Text.ElideRight; maximumLineCount: 1; textFormat: Text.PlainText }
              Text { width: parent.width; visible: text !== ""; text: root.stateCopy()[2]; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; elide: Text.ElideRight; textFormat: Text.PlainText }
            }
          }
        }
        // ---------------------------------------------------------------- the picker head: the trail and a count
        Rectangle {
          visible: root.view !== "main"
          width: parent.width; height: visible ? Style.space(44) : 0; color: root.recessed
          Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.hairline }
          Text {
            anchors.left: parent.left; anchors.leftMargin: Style.space(14); anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(28) - count.width - Style.space(10)
            text: root.trail(); color: root.faint; font.family: root.mono; font.pixelSize: Style.font.caption; elide: Text.ElideLeft; textFormat: Text.PlainText
          }
          Text { id: count; anchors.right: parent.right; anchors.rightMargin: Style.space(14); anchors.verticalCenter: parent.verticalCenter; text: root.pickerCount(); color: root.faint; font.family: root.mono; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
        }
        // ---------------------------------------------------------------- the body: rows
        Item {
          width: parent.width
          implicitHeight: body.implicitHeight + Style.space(28)
          Column {
            id: body
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(14)
            spacing: Style.space(5)
            Repeater {
              model: root.rows
              delegate: RowItem { required property var modelData; required property int index; r: modelData; idx: index; width: body.width }
            }
            Rectangle { visible: root.view !== "main"; width: parent.width; height: 1; color: root.hairline }
            Item { visible: root.view !== "main"; width: parent.width; height: Style.space(5) }
            RowItem { visible: root.view !== "main"; width: body.width; r: root.row("back", "esc", "back"); idx: -2 }
            Rectangle {
              visible: root.toast !== ""; width: parent.width; height: Style.space(28); color: root.recessed
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; text: root.toast; color: root.dim; font.family: root.mono; font.pixelSize: Style.font.caption; textFormat: Text.PlainText }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the orb
  // A 15×15 field of rounded pixels, solid, circularly clipped, with a circle of light inside that
  // falls off quadratically from the centre. It never stops: every state breathes at its own pace,
  // and a download grows the lit radius with progress. One Canvas, repainted while the card is open.
  component Orb: Canvas {
    id: orbCanvas
    width: Style.space(66); height: width
    readonly property int cells: 15
    readonly property real fullRadius: cells / 2 * 0.86
    readonly property real litRadius: root.ui === "working" && root.state === "download" ? 1.2 + fullRadius * Math.max(0, root.progress) / 100 : fullRadius
    readonly property int period: root.ui === "working" ? 1800 : root.ui === "ready" ? 4400 : root.ui === "error" ? 3200 : 5800
    readonly property color light: root.stateColor
    property real phase: 0
    NumberAnimation on phase { running: root.opened; loops: Animation.Infinite; from: 0; to: 1; duration: orbCanvas.period }
    onPhaseChanged: requestPaint()
    onLitRadiusChanged: requestPaint()
    onLightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
      var px = width / cells, gap = px / 3, side = px - gap, corner = side / 3, c = cells / 2
      for (var row = 0; row < cells; row++) for (var col = 0; col < cells; col++) {
        var dx = col + 0.5 - c, dy = row + 0.5 - c, d = Math.sqrt(dx * dx + dy * dy)
        if (d > c) continue                                                          // the circular clip
        var x = col * px + gap / 2, y = row * px + gap / 2
        ctx.fillStyle = root.orbField
        ctx.beginPath(); ctx.roundedRect(x, y, side, side, corner, corner); ctx.fill()  // the solid field
        var l = 0
        if (d <= litRadius + 0.5) {
          l = 0.92 * (1 - Math.pow(d / (litRadius + 0.5), 2) * 0.55)
          if (d > litRadius - 0.5) l *= 0.5 + 0.5 * (litRadius + 0.5 - d)
        }
        if (l <= 0) continue
        var delay = ((row * 3 + col * 2) % 15) / 15                                  // the shimmer runs across the field
        var shimmer = 0.91 + 0.09 * Math.sin((phase + delay) * 2 * Math.PI)
        ctx.fillStyle = Qt.rgba(light.r, light.g, light.b, l * shimmer)
        ctx.beginPath(); ctx.roundedRect(x, y, side, side, corner, corner); ctx.fill()
      }
    }
  }

  // ---------------------------------------------------------------- one row
  component RowItem: Item {
    id: item
    property var r: ({})
    property int idx: 0
    readonly property bool actionable: !!r.action && !r.disabled
    readonly property bool hasCursor: actionable && root.actionable.length > 0 && root.actionable[Math.min(root.cursor, root.actionable.length - 1)] === idx
    readonly property bool primary: r.kind === "primary"
    readonly property color labelColor: r.disabled ? root.faint : primary ? root.popupBg : r.kind === "danger" ? root.urgent : r.urgent ? root.urgent : r.selected ? root.ink : root.fg
    readonly property color valueColor: r.disabled ? root.faint : primary ? root.popupBg : r.urgent ? root.urgent : r.selected ? root.fg : root.dim
    implicitHeight: r.type === "status" ? Style.space(48) : r.type === "search" ? Style.space(34) : r.type === "tabs" ? Style.space(24) : r.type === "stat" ? Style.space(52) : r.type === "text" ? textBlock.implicitHeight + Style.space(16) : Style.space(38)
    Rectangle {
      anchors.fill: parent
      visible: r.type !== "stat" && r.type !== "tabs"
      color: r.type === "status" || r.type === "text" ? root.recessed : primary ? (hasCursor || mouse.containsMouse ? root.fg : root.ink) : r.selected ? root.selectedFill : (hasCursor || (mouse.containsMouse && actionable) || r.type === "search") ? root.hoverFill : root.restFill
    }
    // the plain row: noun left, datum right
    Text {
      visible: r.type === "row" || r.type === "status"
      anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(20) - value.width - Style.space(12)
      text: r.label || ""; color: labelColor; font.family: root.mono; font.pixelSize: Style.font.body; elide: Text.ElideRight; textFormat: Text.PlainText
    }
    Text {
      id: value
      visible: r.type === "row" || r.type === "status"
      anchors.right: parent.right; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
      text: r.value || ""; color: r.type === "status" ? root.ink : valueColor
      font.family: root.mono; font.pixelSize: r.type === "status" ? Style.fontPx(1.25) : Style.font.caption; textFormat: Text.PlainText
    }
    // a wrapped datum: the one place a whole reason is shown
    Text {
      id: textBlock
      visible: r.type === "text"
      anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(10); anchors.verticalCenter: parent.verticalCenter
      text: (r.label ? r.label + " · " : "") + (r.value || ""); color: r.urgent ? root.urgent : root.dim
      font.family: root.mono; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAtWordBoundaryOrAnywhere; textFormat: Text.PlainText
    }
    // the search field of the registry: what was typed, or the placeholder
    Text {
      visible: r.type === "search"
      anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
      text: root.query !== "" ? root.query + "▏" : "search " + root.registryList.length + " recipes"
      color: root.query !== "" ? root.ink : root.faint; font.family: root.mono; font.pixelSize: Style.font.body; textFormat: Text.PlainText
    }
    // the window tabs of the stats view: one cursor item, ←→ or return cycle it, a click picks
    Row {
      visible: r.type === "tabs"; anchors.fill: parent; spacing: Style.space(3)
      Repeater {
        model: ["hour", "today", "week"]
        Rectangle {
          required property string modelData
          width: (parent.width - Style.space(6)) / 3; height: parent.height
          color: root.tokenWindow === modelData ? root.selectedFill : (hasCursor ? root.hoverFill : root.restFill)
          Text { anchors.centerIn: parent; text: modelData; color: root.tokenWindow === modelData ? root.ink : root.faint; font.family: root.mono; font.pixelSize: Style.fontPx(0.75); font.capitalization: Font.AllUppercase; textFormat: Text.PlainText }
          MouseArea { anchors.fill: parent; onClicked: root.tokenWindow = parent.modelData }
        }
      }
    }
    // two labelled cells: numbers live here and nowhere else
    Row {
      visible: r.type === "stat"; anchors.fill: parent; spacing: Style.space(3)
      Repeater {
        model: r.type === "stat" ? [{ l: r.label, v: r.value }, { l: r.extra.label2, v: r.extra.value2 }] : []
        Rectangle {
          required property var modelData
          width: (parent.width - Style.space(3)) / 2; height: parent.height; color: root.restFill
          Column {
            anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
            Text { text: modelData.l; color: root.faint; font.family: root.mono; font.pixelSize: Style.fontPx(0.75); font.capitalization: Font.AllUppercase; font.letterSpacing: Style.fontPx(0.75) * 0.08; textFormat: Text.PlainText }
            Text { text: modelData.v; color: root.ink; font.family: root.mono; font.pixelSize: Style.fontPx(1.25); textFormat: Text.PlainText }
          }
        }
      }
    }
    MouseArea {
      id: mouse
      anchors.fill: parent; hoverEnabled: true; enabled: actionable && r.type !== "tabs"
      cursorShape: actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.activate(r.action)
    }
  }
}
