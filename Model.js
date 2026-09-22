// The card's content, as data. build(c) turns a snapshot plus the panel's navigation state into
// the header, the path, the rows and the footer; Panel.qml only draws what comes back and turns
// row actions into controller verbs. Nothing here touches Qt, so node can test it (test/shell.d/local-ai-model-test.sh).
//
// c: { snap, view:"home"|"card"|"model", hw, count, slotSel, launcherOpen, launchPick, launchModelOpen,
//      agentPick, agentOpen, pending, lastVerb, elapsed, localError, browseWhileWorking }
// row: { type:"row"|"sec"|"stat"|"bar"|"status"|"text", label, value, action, kind:""|"primary"|"danger"|"dd",
//        selected, disabled, urgent, detail, compact, expanded, cells:[{text,mark}], chips:[{text,off}], tabs:[{text,on,action}], stat:[{k,v,u}] }

function gb(n) { return n >= 100 ? Math.round(n) + " GB" : (Math.round(n * 10) / 10) + " GB" }
function kb(n) { return Math.round(n / 1024) + "K" }
function mmss(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
function row(label, value, action, o) { o = o || {}; o.type = o.type || "row"; o.label = label; o.value = value || ""; o.action = action || ""; o.kind = o.kind || ""; return o }
function sec(t) { return { type: "sec", label: t, value: "", action: "", kind: "" } }
function capabilities(caps) {
  caps = caps || {}
  return row("can", "", "", { chips: ["chat", "vision", "video", "tools", "reasoning"].map(function(x) {
    return { text: x + (caps[x] == null ? " ?" : ""), off: caps[x] !== true }
  }) })
}
// A model's capabilities on one line: what it passed, and "?" for what the recipe does not say.
function capabilityWords(caps) {
  caps = caps || {}
  return ["chat", "vision", "video", "tools", "reasoning"].filter(function(x) { return caps[x] !== false })
    .map(function(x) { return " · " + x + (caps[x] == null ? "?" : "") }).join("")
}

// the eyebrow word for what the controller is doing, and which load step that is
function opWord(snap) {
  var st = snap.state, d = (snap.operation || {}).detail || ""
  if (st === "download") return /GB|listing|file|copy/i.test(d) ? "downloading" : /pull/i.test(d) ? "pulling" : "starting"
  if (st === "unload") return "stopping"
  if (/pull/i.test(d)) return "pulling"
  if (/loading|starting|setting aside|password|docker|rolling/i.test(d) || d === "") return "starting"
  return "checking"
}
function opStep(word) { return { downloading: 0, pulling: 1, starting: 2, checking: 3 }[word] }

function models(snap) { return (snap.models || []).filter(function(m) { return m.state !== "stopped" }) }
function holder(snap, key) { var ms = models(snap); for (var i = 0; i < ms.length; i++) if (ms[i].keys.indexOf(key) >= 0) return ms[i]; return null }
function modelById(snap, id) { var ms = models(snap); for (var i = 0; i < ms.length; i++) if (ms[i].recipeId === id) return ms[i]; return null }
function recipeById(snap, id) { var rs = snap.recipes || []; for (var i = 0; i < rs.length; i++) if (rs[i].id === id) return rs[i]; return null }
function cardByHw(snap, hw) { var cs = snap.cards || []; for (var i = 0; i < cs.length; i++) if (cs[i].hardwareId === hw) return cs[i]; return null }
function cardOfKeys(snap, keys) { var cs = snap.cards || []; for (var i = 0; i < cs.length; i++) if (keys.length && cs[i].keys.indexOf(keys[0]) >= 0) return cs[i]; return null }
function gpu(snap, key) { var gs = snap.gpus || []; for (var i = 0; i < gs.length; i++) if (gs[i].key === key) return gs[i]; return null }
function freeKeys(snap, c) { return c.keys.filter(function(k) { return !holder(snap, k) }) }
function freest(snap, keys) { return keys.slice().sort(function(a, b) { var ga = gpu(snap, a) || {}, gb = gpu(snap, b) || {}; return ((gb.vramGb || 0) - (gb.usedGb || 0)) - ((ga.vramGb || 0) - (ga.usedGb || 0)) })[0] || "" }   // the display card carries the desktop: start elsewhere when there is an elsewhere
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
  if (m) return m.keys
  return snap.selected && snap.selected.recipeId === id ? (snap.selected.keys || []) : []
}
function shortError(c) {
  var e = c.localError || c.snap.error || c.snap.reason || ""
  if (c.localError) return "no answer"
  if (c.snap.reason && !c.snap.error) return /^no supported GPU/.test(e) ? "no card" : /^no validated recipe/.test(e) ? "no recipe" : /^port /.test(e) ? "port busy" : /driver/.test(e) ? "driver" : "refused"
  if (/out of memory|OOM|VRAM/i.test(e)) return "out of VRAM"
  if (/tok\/s/.test(e)) return "too slow"
  if (/stopped unexpectedly|crash/.test(e)) return "stopped"
  if (/acceptance failed/.test(e)) return "acceptance failed"
  if (/did not answer|not answering/.test(e)) return "no answer"
  if (/refused|dismissed/.test(e)) return "refused"
  if (/docker/i.test(e)) return "docker"
  if (/space|GB free/.test(e)) return "disk full"
  if (/checksum|Hub|download/.test(e)) return "download"
  return "error"
}

// one cell per physical card of a group: what holds it
function cells(c, group, work) {
  var snap = c.snap, keys = work ? workKeys(snap) : [], word = work ? opWord(snap) : ""
  return group.keys.map(function(k) {
    var m = holder(snap, k)
    if (work && keys.indexOf(k) >= 0 && word === "stopping") return { text: "freeing", mark: "freeing" }
    if (work && keys.indexOf(k) >= 0) return { text: "claimed", mark: "claimed" }
    if (m && m.state === "error") return { text: "crashed", mark: "crashed" }
    if (m) return { text: "#" + k.split(":")[1] + " ready", mark: "used" }
    return { text: "free", mark: "free" }
  })
}
function groupModels(snap, group) {
  return models(snap).filter(function(m) { return m.keys.some(function(k) { return group.keys.indexOf(k) >= 0 }) })
}
function cardRows(c, work) {
  var snap = c.snap, out = [sec(work ? "gpus" : "deployments")], cs = snap.cards || []
  cs.forEach(function(g) {
    var ms = groupModels(snap, g), free = freeKeys(snap, g).length
    var failed = ms.some(function(m) { return m.state === "error" })
    var busy = work && g.keys.some(function(k) { return workKeys(snap).indexOf(k) >= 0 })
    var status = busy ? opWord(snap) : failed ? "error" : ms.length ? (free ? free + " available" : "running") : "available"
    var detail = (failed ? "Needs attention" : ms.length ? "Running" : "Available") + " · "
      + (ms.length === 1 ? ms[0].name : ms.length ? ms.length + " models" : "no model loaded")
      + (ms.length && free ? " · " + free + " free" : "")
    out.push(row(g.count + "× " + g.name, work ? status : "Models ›", work ? "" : "gpu:" + g.hardwareId,
      { status: status, detail: work ? "" : detail, urgent: failed, compact: !work, cells: work ? cells(c, g, work) : undefined }))
  })
  if (!cs.length) out.push(row("GPU", "none detected", "", { urgent: true }))
  return out
}

function launchModel(c) {
  var ready = models(c.snap).filter(function(m) { return m.state === "ready" })
  return ready.filter(function(m) { return m.recipeId === c.launchPick })[0]
    || ready.filter(function(m) { return m.recipeId === (c.snap.running || {}).recipeId })[0] || ready[0]
}
function launchRows(c, m) {
  if (!m) return [row("open agent", "load a model first", "", { disabled: true })]
  var snap = c.snap, agents = m.launchable || [], a = agents.indexOf(c.agentPick) >= 0 ? c.agentPick
    : agents.indexOf((snap.agents || {}).default) >= 0 ? snap.agents.default : agents[0] || ""
  if (!a) return [row("agent", "none can use this model", "", { disabled: true })]
  var rows = [row("agent", a, "agent-toggle", { expanded: !!c.agentOpen })]
  if (c.agentOpen) agents.forEach(function(x) { rows.push(row(x, x === (snap.agents || {}).default ? "default" : "", "agent:" + x, { kind: "dd", selected: x === a })) })
  rows.push(row("open " + a, "terminal ›", "open-agent:" + a + ":" + m.recipeId, { kind: "primary", compact: true }))
  return rows
}

function isWorking(c) {
  return ["download", "starting", "unload"].indexOf(c.snap.state) >= 0 || (c.pending && ["load", "unload"].indexOf(c.lastVerb) >= 0)
}
function changesDeployment(action) { return ["run", "run-again", "stop"].indexOf((action || "").split(":")[0]) >= 0 }
function build(c) {
  var out = buildView(c)
  if (isWorking(c) && c.browseWhileWorking) {
    out.rows.unshift(row("Deployment in progress", "View progress ›", "work", { compact: true }))
    out.rows.concat(out.foot).forEach(function(r) { if (changesDeployment(r.action)) r.disabled = true })
  }
  return out
}

function buildView(c) {
  var snap = c.snap, ms = models(snap), op = snap.operation || {}, o = { steps: -1, path: [{ n: "local ai", v: "home", action: "home" }], rows: [], foot: [] }
  var working = isWorking(c)
  var error = !working && c.view === "home" && (c.localError !== "" || snap.state === "error" || (snap.reason || "") !== "")
  var crashed = ms.filter(function(m) { return m.state === "error" })
  // ---- work: progress is the default; navigation may inspect other views safely.
  if (working && !c.browseWhileWorking) {
    var w = snap.state === "download" || snap.state === "starting" || snap.state === "unload" ? opWord(snap) : (c.lastVerb === "unload" ? "stopping" : snap.selected && !snap.selected.onDisk ? "downloading" : "starting")
    var who = recipeById(snap, op.recipeId) || modelById(snap, op.recipeId) || (snap.selected ? { name: snap.selected.name } : { name: "Local AI" })
    var r = recipeById(snap, op.recipeId) || { sizeGb: 0 }
    o.tone = "work"; o.eyebrow = w; o.title = who.name
    o.sub = w === "downloading" && op.percent > 0 && r.sizeGb ? "weights · " + gb(op.percent / 100 * r.sizeGb) + " of " + gb(r.sizeGb) : (op.detail || { downloading: "weights", pulling: "engine image", starting: "engine warming", checking: "acceptance", stopping: "containers coming down" }[w])
    if (w !== "stopping") { o.steps = opStep(w); var hw = r.hardwareId ? cardByHw(snap, r.hardwareId) : null; if (hw) o.path.push({ n: hw.name.toLowerCase(), v: "card", action: "card:" + hw.hardwareId }) }
    else { var wm = modelById(snap, op.recipeId); o.path.push({ n: (wm ? wm.name : who.name).toLowerCase(), v: "model", action: wm ? "model:" + wm.recipeId : "home" }) }
    o.path.push({ n: w, v: "work", action: "work" })
    var late = op.expectedSeconds > 0 && c.elapsed > op.expectedSeconds * 1.5
    var pct = op.percent > 0 ? op.percent : (op.expectedSeconds > 0 && c.elapsed > 0 ? Math.min(95, Math.round(c.elapsed * 100 / op.expectedSeconds)) : 0)
    o.rows.push(row(w, late ? mmss(c.elapsed) + " · longer than usual" : pct > 0 ? pct + "%" + (c.elapsed > 0 ? " · " + mmss(c.elapsed) : "") : c.elapsed > 0 ? mmss(c.elapsed) : "…", "", { type: "status" }))
    o.rows.push({ type: "bar", percent: pct, label: "", value: "", action: "", kind: "" })
    if (w !== "downloading") o.rows = o.rows.concat(cardRows(c, true).filter(function(x) { return x.type === "sec" || (x.cells && x.cells.some(function(k) { return k.mark === "claimed" || k.mark === "freeing" })) }))
    if (w === "downloading" && !c.pending) o.foot.push(row("stop", "keeps weights", "stop-download", { kind: "danger" }))
    return o
  }
  // ---- error: the last verb failed
  if (error) {
    o.tone = "error"; o.eyebrow = "error"; o.title = shortError(c); o.sub = snap.selected ? snap.selected.name : ""
    var why = c.localError ? "the plugin did not answer" : snap.error || snap.reason || ""
    o.rows.push(row(c.localError ? "plugin" : snap.error ? "engine" : "recipe", why, "", { urgent: true, type: "text" }))
    if (snap.helpText && snap.helpText !== why) o.rows.push(row("do", snap.helpText, "", { type: "text" }))
    o.rows.push(row("run again", snap.selected ? snap.selected.name : "", c.localError ? "refresh" : "run-again", { kind: "primary", disabled: !snap.selected && !c.localError }))
    o.rows.push(row("log", "open ›", "log"))
    o.rows = o.rows.concat(cardRows(c, false))
    return o
  }
  var total = (snap.cards || []).reduce(function(a, g) { return a + g.count }, 0)
  var view = c.view === "model" && !modelById(snap, c.slotSel) ? "home" : c.view === "card" && !cardByHw(snap, c.hw) ? "home" : c.view   // a place that is gone falls back to home
  // ---- model: one running model, its numbers first
  if (view === "model") {
    var m = modelById(snap, c.slotSel), cg = cardOfKeys(snap, m.keys)
    o.tone = m.state === "error" ? "error" : "ready"; o.eyebrow = m.state === "error" ? "crashed" : m.state === "ready" ? "ready" : m.state; o.title = m.name
    o.sub = where(snap, m) + " · :" + m.port
    if (cg) o.path.push({ n: cg.name.toLowerCase(), v: "card", action: "card:" + cg.hardwareId })
    o.path.push({ n: m.name.toLowerCase(), v: "model", action: "model:" + m.recipeId })
    if (m.state !== "ready") {
      o.rows.push(row("engine", m.note || "stopped unexpectedly", "", { urgent: true, type: "text" }))
      o.rows.push(row("run again", m.name, "run:" + m.recipeId + ":" + (m.cards || 1), { kind: "primary" })); o.rows.push(row("log", "open ›", "log"))
      o.foot.push(row("stop", m.name, "stop:" + m.recipeId, { kind: "danger" })); return o
    }
    o.rows = o.rows.concat(launchRows(c, m))
    o.rows.push({ type: "stat", stat: [{ k: "context", v: m.ctxTokens > 0 ? kb(m.ctxTokens) : "n/a", u: m.ctxTokens > 0 ? "tokens" : "" }, { k: "kv cache", v: m.kvTokens > 0 ? kb(m.kvTokens) : "n/a", u: m.kvTokens > 0 ? "tokens" : "" }], label: "", value: "", action: "", kind: "" })
    o.rows.push(row(where(snap, m), "http://127.0.0.1:" + m.port + "/v1", ""))
    o.rows.push(capabilities(m.caps))
    if (m.acceptedAt) o.rows.push(row("accepted", m.acceptedAt.replace("T", " ").replace(/Z$/, " UTC") + " · " + (m.apis || []).join(", "), ""))
    o.foot.push(row("stop", m.name, "stop:" + m.recipeId, { kind: "danger" }))
    return o
  }
  // ---- card: one card type, how many, which recipe. The title and the breadcrumb already name
  // the card, so no row repeats it; the per-card state moves into the subtitle. One row per
  // model, and that row is the action.
  if (view === "card") {
    var g = cardByHw(snap, c.hw)
    var free = freeKeys(snap, g), n = Math.max(1, Math.min(c.count || 1, g.keys.length))
    var marks = cells(c, g, false).map(function(x, i) { return "#" + g.keys[i].split(":")[1] + " " + x.text }).join(" · ")
    o.tone = "idle"; o.eyebrow = "models"; o.title = g.name; o.sub = free.length + " of " + g.keys.length + " free · " + g.vramGb + " GB each" + (marks ? " · " + marks : "")
    o.path.push({ n: g.name.toLowerCase(), v: "card", action: "card:" + g.hardwareId }); if (n > 1) o.path.push({ n: n + " cards", v: "card", action: "count:" + n })
    var running = groupModels(snap, g)
    if (running.length) {
      o.rows.push(sec("running models"))
      running.forEach(function(m) { o.rows.push(row(m.name, "Open ›", "model:" + m.recipeId, { detail: (m.state === "ready" ? "Ready" : m.state) + " · " + where(snap, m), compact: true })) })
    }
    if (g.keys.length > 1) { var tabs = []; for (var k = 1; k <= g.keys.length; k++) tabs.push({ text: k + "×", on: k === n, action: "count:" + k }); o.rows.push(row("GPUs to use", "", "", { tabs: tabs })) }
    var list = fits(snap, g, n)
    o.rows.push(sec("load a model · " + n + (n > 1 ? " GPUs" : " GPU") + " · " + list.length))
    if (!list.length) o.rows.push(row("models", "no models for " + n + " GPU" + (n > 1 ? "s" : "")))
    var dup = {}; list.forEach(function(r) { dup[r.name] = (dup[r.name] || 0) + 1 })   // two recipes of one model: say which
    list.forEach(function(r) {
      var plan = loadPlan(snap, r, g), swap = plan.replaces.length > 0, running = !!modelById(snap, r.id)
      var verb = r.gate ? "Unavailable" : swap ? (running ? "Reload" : r.onDisk ? "Swap" : "Download & swap")
        : r.onDisk ? "Load" : r.partialBytes > 0 ? "Resume & load" : "Download & run"
      var detail = r.gate ? r.gate : (r.ctxTokens > 0 ? kb(r.ctxTokens) + " ctx" : "context unknown") + capabilityWords(r.caps)
        + (swap && !running ? " · replaces " + plan.replaces.map(function(m) { return m.name }).join(", ") : "")
      o.rows.push(row(dup[r.name] > 1 ? r.name + " · " + r.engine : r.name,
        verb + (r.sizeGb > 0 ? " · " + gb(r.sizeGb) : ""), r.gate ? "" : "run:" + r.id + ":" + n, { detail: detail, disabled: !!r.gate }))
    })
    return o
  }
  // ---- home: what you have and what runs on it
  if (!ms.length) { o.tone = (snap.cards || []).length ? "idle" : "error"; o.eyebrow = (snap.cards || []).length ? "idle" : "no card"; o.title = "Local AI"; o.sub = (snap.cards || []).length ? total + " cards free · nothing running" : "no supported GPU" }
  else { var used = ms.reduce(function(a, m) { return a + m.cards }, 0)
    o.tone = crashed.length ? "error" : "ready"; o.eyebrow = crashed.length ? "crashed" : "ready"; o.title = ms.length === 1 ? ms[0].name : ms.length + " models"
    o.sub = "on " + used + " of " + total + " cards" }
  if (snap.statusText) o.rows.push(row(snap.statusText.toLowerCase(), snap.helpText || "", "", { type: "text", urgent: snap.statusText !== "Unsupported GPU" }))
  var launch = launchModel(c)
  o.rows.push(row("launch agent", launch ? where(snap, launch) + " · " + launch.name : "load a model first", "launcher-toggle", { expanded: !!c.launcherOpen }))
  if (c.launcherOpen && launch) {
    o.rows.push(row("model", where(snap, launch) + " · " + launch.name, "launch-model-toggle", { expanded: !!c.launchModelOpen }))
    if (c.launchModelOpen) ms.filter(function(m) { return m.state === "ready" }).forEach(function(m) {
      o.rows.push(row(where(snap, m), m.name, "launch-model:" + m.recipeId, { kind: "dd", selected: m.recipeId === launch.recipeId }))
    })
  }
  o.rows = o.rows.concat(c.launcherOpen ? launchRows(c, launch) : launchRows(c, launch).slice(-1))
  o.rows = o.rows.concat(cardRows(c, false))
  return o
}

if (typeof module !== "undefined") module.exports = { gb: gb, kb: kb, mmss: mmss, opWord: opWord, models: models, modelById: modelById, recipeById: recipeById, cardByHw: cardByHw, cardOfKeys: cardOfKeys, freeKeys: freeKeys, loadPlan: loadPlan, fits: fits, where: where, shortError: shortError, cells: cells, cardRows: cardRows, launchRows: launchRows, isWorking: isWorking, changesDeployment: changesDeployment, build: build, buildView: buildView }
