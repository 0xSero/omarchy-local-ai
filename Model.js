// The card's content, as data. build(c) turns a snapshot plus the panel's navigation state into
// the header, the path, the rows and the footer; Panel.qml only draws what comes back and turns
// row actions into controller verbs. Nothing here touches Qt, so node can test it (test/shell.d/local-ai-model-test.sh).
//
// c: { snap, view:"home"|"card"|"model", hw, count, slotSel, launcherOpen, agentPick, agentOpen, pending, lastVerb, elapsed, localError }
// row: { type:"row"|"sec"|"stat"|"bar"|"status"|"text", label, value, action, kind:""|"primary"|"danger"|"dd",
//        selected, disabled, urgent, detail, compact, expanded, cells:[{text,mark}], chips:[{text,off}], tabs:[{text,on,action}], stat:[{k,v,u}] }

function gb(n) { return n >= 100 ? Math.round(n) + " GB" : (Math.round(n * 10) / 10) + " GB" }
function kb(n) { return Math.round(n / 1024) + "K" }
function mmss(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
function row(label, value, action, o) { o = o || {}; o.type = o.type || "row"; o.label = label; o.value = value || ""; o.action = action || ""; o.kind = o.kind || ""; return o }
function sec(t) { return { type: "sec", label: t, value: "", action: "", kind: "" } }
var CAPS = ["chat", "vision", "video", "tools", "reasoning"]
function capabilities(caps) { caps = caps || {}; return row("can", "", "", { chips: CAPS.map(function(x) { return { text: x + (caps[x] == null ? " ?" : ""), off: caps[x] !== true } }) }) }
function capabilityWords(caps) { caps = caps || {}; return CAPS.filter(function(x) { return caps[x] !== false }).map(function(x) { return " · " + x + (caps[x] == null ? "?" : "") }).join("") }
var WORD = { download: "downloading", starting: "starting", unload: "stopping" }   // the eyebrow for what the controller is doing

function models(snap) { return (snap.models || []).filter(function(m) { return m.state !== "stopped" }) }
function find(list, key, v) { list = list || []; for (var i = 0; i < list.length; i++) if (list[i][key] === v) return list[i]; return null }
function holder(snap, key) { var ms = models(snap); for (var i = 0; i < ms.length; i++) if (ms[i].keys.indexOf(key) >= 0) return ms[i]; return null }
function modelById(snap, id) { return find(models(snap), "recipeId", id) }
function recipeById(snap, id) { return find(snap.recipes, "id", id) }
function cardByHw(snap, hw) { return find(snap.cards, "hardwareId", hw) }
function cardOfKeys(snap, keys) { var cs = snap.cards || []; for (var i = 0; i < cs.length; i++) if (keys.length && cs[i].keys.indexOf(keys[0]) >= 0) return cs[i]; return null }
function freeKeys(snap, c) { return c.keys.filter(function(k) { return !holder(snap, k) }) }
function freest(snap, keys) { return keys.slice().sort(function(a, b) { var ga = find(snap.gpus, "key", a) || {}, gb = find(snap.gpus, "key", b) || {}; return ((gb.vramGb || 0) - (gb.usedGb || 0)) - ((ga.vramGb || 0) - (ga.usedGb || 0)) })[0] || "" }   // the display card carries the desktop: start elsewhere when there is an elsewhere
// The cards a load of this recipe takes, free ones first, so the row can name what it replaces. The
// controller makes the same choice from the keys the card sends.
function loadPlan(snap, recipe, group) {
  var chosen = freest(snap, freeKeys(snap, group)) || group.keys[0], n = recipe.cards || 1
  var pool = group.keys.slice().sort(function(a, b) { return (a === chosen ? 0 : 1) - (b === chosen ? 0 : 1) || (holder(snap, a) ? 1 : 0) - (holder(snap, b) ? 1 : 0) })
  var keys = pool.slice(0, n)
  return { gpu: chosen, keys: keys, replaces: models(snap).filter(function(m) { return m.keys.some(function(k) { return keys.indexOf(k) >= 0 }) }) }
}
function fits(snap, c, n) { return (snap.recipes || []).filter(function(r) { return r.hardwareId === c.hardwareId && (r.cards || 1) === n }) }
function where(snap, m) { var c = cardOfKeys(snap, m.keys); return (m.cards > 1 ? m.cards + "× " : "") + (c ? c.name : "card") + (c && c.count > 1 ? " · #" + m.keys.map(function(k) { return k.split(":")[1] }).join(", #") : "") }
function workKeys(snap) { // the cards a running op touches: the model it stops, or the claim of the recipe it starts
  var id = (snap.operation || {}).recipeId || "", m = modelById(snap, id)
  return m ? m.keys : snap.selected && snap.selected.recipeId === id ? (snap.selected.keys || []) : []
}
function shortError(c) {
  var e = c.localError || c.snap.error || c.snap.reason || ""
  if (c.localError) return "no answer"
  if (c.snap.reason && !c.snap.error) return /^no supported GPU/.test(e) ? "no card" : /^no validated recipe/.test(e) ? "no recipe" : /^port /.test(e) ? "port busy" : /driver/.test(e) ? "driver" : "refused"
  var table = [[/out of memory|OOM|VRAM/i, "out of VRAM"], [/tok\/s/, "too slow"], [/stopped unexpectedly|crash/, "stopped"], [/acceptance failed/, "acceptance failed"], [/did not answer|not answering/, "no answer"],
    [/refused|dismissed/, "refused"], [/docker/i, "docker"], [/space|GB free/, "disk full"], [/checksum|Hub|download/, "download"]]
  for (var i = 0; i < table.length; i++) if (table[i][0].test(e)) return table[i][1]
  return "error"
}

// one cell per physical card of a group: what holds it
function cells(snap, group, work) {
  var keys = work ? workKeys(snap) : [], word = work ? WORD[snap.state] : ""
  return group.keys.map(function(k) {
    var m = holder(snap, k)
    if (work && keys.indexOf(k) >= 0) return word === "stopping" ? { text: "freeing", mark: "freeing" } : { text: "claimed", mark: "claimed" }
    if (m) return m.state === "error" ? { text: "crashed", mark: "crashed" } : { text: "#" + k.split(":")[1] + " ready", mark: "used" }
    return { text: "free", mark: "free" }
  })
}
function groupModels(snap, group) { return models(snap).filter(function(m) { return m.keys.some(function(k) { return group.keys.indexOf(k) >= 0 }) }) }
function cardRows(snap, work) {
  var out = [sec(work ? "gpus" : "deployments")], cs = snap.cards || []
  cs.forEach(function(g) {
    var ms = groupModels(snap, g), free = freeKeys(snap, g).length
    var failed = ms.some(function(m) { return m.state === "error" })
    var busy = work && g.keys.some(function(k) { return workKeys(snap).indexOf(k) >= 0 })
    var status = busy ? WORD[snap.state] : failed ? "error" : ms.length ? (free ? free + " available" : "running") : "available"
    var detail = (failed ? "Needs attention" : ms.length ? "Running" : "Available") + " · "
      + (ms.length === 1 ? ms[0].name : ms.length ? ms.length + " models" : "no model loaded") + (ms.length && free ? " · " + free + " free" : "")
    out.push(row(g.count + "× " + g.name, work ? status : "Models ›", work ? "" : "gpu:" + g.hardwareId,
      { status: status, detail: work ? "" : detail, urgent: failed, compact: !work, cells: work ? cells(snap, g, work) : undefined }))
  })
  if (!cs.length) out.push(row("GPU", "none detected", "", { urgent: true }))
  return out
}

function launchModel(snap) { // the model agents open on: the last one started, else any that is ready
  var ready = models(snap).filter(function(m) { return m.state === "ready" })
  return find(ready, "recipeId", (snap.running || {}).recipeId) || ready[0]
}
function launchRows(c, m) {
  if (!m) return [row("open agent", "load a model first", "", { disabled: true })]
  var snap = c.snap, agents = m.launchable || [], dflt = (snap.agents || {}).default
  var a = agents.indexOf(c.agentPick) >= 0 ? c.agentPick : agents.indexOf(dflt) >= 0 ? dflt : agents[0] || ""
  if (!a) return [row("agent", "none can use this model", "", { disabled: true })]
  var rows = [row("agent", a, "agent-toggle", { expanded: !!c.agentOpen })]
  if (c.agentOpen) agents.forEach(function(x) { rows.push(row(x, x === dflt ? "default" : "", "agent:" + x, { kind: "dd", selected: x === a })) })
  rows.push(row("open " + a, "terminal ›", "open-agent:" + a + ":" + m.recipeId, { kind: "primary", compact: true }))
  return rows
}
function isWorking(c) { return WORD[c.snap.state] !== undefined || (c.pending && ["load", "unload"].indexOf(c.lastVerb) >= 0) }

function build(c) {
  var snap = c.snap, ms = models(snap), op = snap.operation || {}, o = { path: [{ n: "local ai", v: "home", action: "home" }], rows: [], foot: [] }
  var crashed = ms.filter(function(m) { return m.state === "error" })
  // ---- work: the card shows the operation and nothing else until it ends
  if (isWorking(c)) {
    var w = WORD[snap.state] || (c.lastVerb === "unload" ? "stopping" : snap.selected && !snap.selected.onDisk ? "downloading" : "starting")
    var r = recipeById(snap, op.recipeId) || { sizeGb: 0 }, who = r.name || (modelById(snap, op.recipeId) || snap.selected || { name: "Local AI" }).name
    o.tone = "work"; o.eyebrow = w; o.title = who
    o.sub = w === "downloading" && op.percent > 0 && r.sizeGb ? "weights · " + gb(op.percent / 100 * r.sizeGb) + " of " + gb(r.sizeGb) : (op.detail || { downloading: "weights", starting: "engine warming", stopping: "containers coming down" }[w])
    var hw = r.hardwareId ? cardByHw(snap, r.hardwareId) : null, wm = w === "stopping" ? modelById(snap, op.recipeId) : null
    if (wm) o.path.push({ n: wm.name.toLowerCase(), v: "model", action: "model:" + wm.recipeId })
    else if (hw) o.path.push({ n: hw.name.toLowerCase(), v: "card", action: "card:" + hw.hardwareId })
    o.path.push({ n: w, v: "work", action: "work" })
    var pct = op.percent > 0 ? op.percent : (op.expectedSeconds > 0 && c.elapsed > 0 ? Math.min(95, Math.round(c.elapsed * 100 / op.expectedSeconds)) : 0)
    o.rows.push(row(w, (pct > 0 ? pct + "%" : "") + (c.elapsed > 0 ? (pct > 0 ? " · " : "") + mmss(c.elapsed) : pct > 0 ? "" : "…"), "", { type: "status" }))
    o.rows.push({ type: "bar", percent: pct, label: "", value: "", action: "", kind: "" })
    if (w !== "downloading") o.rows = o.rows.concat(cardRows(snap, true).filter(function(x) { return x.type === "sec" || (x.cells && x.cells.some(function(k) { return k.mark === "claimed" || k.mark === "freeing" })) }))
    if (w === "downloading" && !c.pending) o.foot.push(row("stop", "keeps weights", "stop-download", { kind: "danger" }))
    return o
  }
  // ---- error: the last verb failed
  if (c.view === "home" && (c.localError !== "" || snap.state === "error" || (snap.reason || "") !== "")) {
    o.tone = "error"; o.eyebrow = "error"; o.title = shortError(c); o.sub = snap.selected ? snap.selected.name : ""
    var why = c.localError ? "the plugin did not answer" : snap.error || snap.reason || ""
    o.rows.push(row(c.localError ? "plugin" : snap.error ? "engine" : "recipe", why, "", { urgent: true, type: "text" }))
    if (snap.helpText && snap.helpText !== why) o.rows.push(row("do", snap.helpText, "", { type: "text" }))
    o.rows.push(row("run again", snap.selected ? snap.selected.name : "", c.localError ? "refresh" : "run-again", { kind: "primary", disabled: !snap.selected && !c.localError }))
    o.rows.push(row("log", "open ›", "log"))
    o.rows = o.rows.concat(cardRows(snap, false))
    return o
  }
  var total = (snap.cards || []).reduce(function(a, g) { return a + g.count }, 0)
  var view = c.view === "model" && !modelById(snap, c.slotSel) ? "home" : c.view === "card" && !cardByHw(snap, c.hw) ? "home" : c.view   // a place that is gone falls back to home
  // ---- model: one running model, its numbers first
  if (view === "model") {
    var m = modelById(snap, c.slotSel), cg = cardOfKeys(snap, m.keys)
    o.tone = m.state === "error" ? "error" : "ready"; o.eyebrow = m.state === "error" ? "crashed" : m.state; o.title = m.name; o.sub = where(snap, m) + " · :" + m.port
    if (cg) o.path.push({ n: cg.name.toLowerCase(), v: "card", action: "card:" + cg.hardwareId })
    o.path.push({ n: m.name.toLowerCase(), v: "model", action: "model:" + m.recipeId })
    o.foot.push(row("stop", m.name, "stop:" + m.recipeId, { kind: "danger" }))
    if (m.state !== "ready") {
      o.rows.push(row("engine", m.note || "stopped unexpectedly", "", { urgent: true, type: "text" }))
      o.rows.push(row("run again", m.name, "run:" + m.recipeId + ":" + (m.cards || 1), { kind: "primary" })); o.rows.push(row("log", "open ›", "log"))
      return o
    }
    o.rows = o.rows.concat(launchRows(c, m))
    o.rows.push({ type: "stat", stat: [{ k: "context", v: m.ctxTokens > 0 ? kb(m.ctxTokens) : "n/a", u: m.ctxTokens > 0 ? "tokens" : "" }, { k: "kv cache", v: m.kvTokens > 0 ? kb(m.kvTokens) : "n/a", u: m.kvTokens > 0 ? "tokens" : "" }], label: "", value: "", action: "", kind: "" })
    o.rows.push(row(where(snap, m), "http://127.0.0.1:" + m.port + "/v1", ""))
    o.rows.push(capabilities(m.caps))
    if (m.acceptedAt) o.rows.push(row("accepted", m.acceptedAt.replace("T", " ").replace(/Z$/, " UTC") + " · " + (m.apis || []).join(", "), ""))
    return o
  }
  // ---- card: one card type, how many, which recipe. One row per model, and that row is the action.
  if (view === "card") {
    var g = cardByHw(snap, c.hw), free = freeKeys(snap, g), n = Math.max(1, Math.min(c.count || 1, g.keys.length))
    var marks = cells(snap, g, false).map(function(x, i) { return "#" + g.keys[i].split(":")[1] + " " + x.text }).join(" · ")
    o.tone = "idle"; o.eyebrow = "models"; o.title = g.name; o.sub = free.length + " of " + g.keys.length + " free · " + g.vramGb + " GB each" + (marks ? " · " + marks : "")
    o.path.push({ n: g.name.toLowerCase(), v: "card", action: "card:" + g.hardwareId }); if (n > 1) o.path.push({ n: n + " cards", v: "card", action: "count:" + n })
    var running = groupModels(snap, g)
    if (running.length) {
      o.rows.push(sec("running models"))
      running.forEach(function(m) { o.rows.push(row(m.name, "Open ›", "model:" + m.recipeId, { detail: (m.state === "ready" ? "Ready" : m.state) + " · " + where(snap, m), compact: true })) })
    }
    if (g.keys.length > 1) { var tabs = []; for (var k = 1; k <= g.keys.length; k++) tabs.push({ text: k + "×", on: k === n, action: "count:" + k }); o.rows.push(row("GPUs to use", "", "", { tabs: tabs })) }
    var list = fits(snap, g, n), dup = {}
    o.rows.push(sec("load a model · " + n + (n > 1 ? " GPUs" : " GPU") + " · " + list.length))
    if (!list.length) o.rows.push(row("models", "no models for " + n + " GPU" + (n > 1 ? "s" : "")))
    list.forEach(function(r) { dup[r.name] = (dup[r.name] || 0) + 1 })   // two recipes of one model: say which
    list.forEach(function(r) {
      var plan = loadPlan(snap, r, g), swap = plan.replaces.length > 0, running = !!modelById(snap, r.id)
      var verb = r.gate ? "Unavailable" : swap ? (running ? "Reload" : r.onDisk ? "Swap" : "Download & swap") : r.onDisk ? "Load" : r.partialBytes > 0 ? "Resume & load" : "Download & run"
      var detail = r.gate ? r.gate : (r.ctxTokens > 0 ? kb(r.ctxTokens) + " ctx" : "context unknown") + capabilityWords(r.caps) + (swap && !running ? " · replaces " + plan.replaces.map(function(m) { return m.name }).join(", ") : "")
      o.rows.push(row(dup[r.name] > 1 ? r.name + " · " + r.engine : r.name, verb + (r.sizeGb > 0 ? " · " + gb(r.sizeGb) : ""), r.gate ? "" : "run:" + r.id + ":" + n, { detail: detail, disabled: !!r.gate }))
    })
    return o
  }
  // ---- home: what you have and what runs on it
  var any = (snap.cards || []).length > 0
  if (!ms.length) { o.tone = any ? "idle" : "error"; o.eyebrow = any ? "idle" : "no card"; o.title = "Local AI"; o.sub = any ? total + " cards free · nothing running" : "no supported GPU" }
  else { o.tone = crashed.length ? "error" : "ready"; o.eyebrow = crashed.length ? "crashed" : "ready"; o.title = ms.length === 1 ? ms[0].name : ms.length + " models"; o.sub = "on " + ms.reduce(function(a, m) { return a + m.cards }, 0) + " of " + total + " cards" }
  if (snap.statusText) o.rows.push(row(snap.statusText.toLowerCase(), snap.helpText || "", "", { type: "text", urgent: snap.statusText !== "Unsupported GPU" }))
  var launch = launchModel(snap), deployments = cardRows(snap, false)
  if (launch) {   // agents only exist once a model runs; until then the card rows are the one thing to click
    o.rows.push(row("launch agent", where(snap, launch) + " · " + launch.name, "launcher-toggle", { expanded: !!c.launcherOpen }))
    o.rows = o.rows.concat(c.launcherOpen ? launchRows(c, launch) : launchRows(c, launch).slice(-1))
  } else if (any) { o.rows.push(row("no model running", "pick a card below, then a model to load", "", { type: "text" })); deployments.forEach(function(r) { if (r.action) r.kind = "primary" }) }
  o.rows = o.rows.concat(deployments)
  return o
}

if (typeof module !== "undefined") module.exports = { gb: gb, kb: kb, mmss: mmss, models: models, modelById: modelById, recipeById: recipeById, cardByHw: cardByHw, cardOfKeys: cardOfKeys, freeKeys: freeKeys, loadPlan: loadPlan, fits: fits, where: where, shortError: shortError, cells: cells, cardRows: cardRows, launchRows: launchRows, isWorking: isWorking, build: build }
