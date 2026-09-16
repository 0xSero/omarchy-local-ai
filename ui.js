.pragma library
// The card's content, as data. build(c) turns a snapshot plus the panel's navigation state into
// the header, the path, the rows and the pinned footer; Panel.qml only draws what comes back and
// turns row actions into controller verbs. Nothing here touches Qt.
//
// c: { snap, view:"home"|"card"|"model", hw, count, pick, slotSel, agentPick, agentOpen, copied,
//      pending, lastVerb, elapsed, localError }
// row: { type:"row"|"sec"|"stat"|"bar"|"status", label, value, action, kind:""|"primary"|"danger"|"dd",
//        selected, disabled, urgent, cells:[{text,mark}], chips:[{text,off}], tabs:[{text,on,action}], stat:[{k,v,u}] }

function gb(n) { return n >= 100 ? Math.round(n) + " GB" : (Math.round(n * 10) / 10) + " GB" }
function kb(n) { return Math.round(n / 1024) + "K" }
function kmg(n) { return n >= 1e6 ? (Math.round(n / 1e5) / 10) + "M" : n >= 1e3 ? (Math.round(n / 100) / 10) + "K" : String(n) }
function mmss(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
function row(label, value, action, o) { o = o || {}; o.type = o.type || "row"; o.label = label; o.value = value || ""; o.action = action || ""; o.kind = o.kind || ""; return o }
function sec(t) { return { type: "sec", label: t, value: "", action: "", kind: "" } }
function capabilities(caps) {
  caps = caps || {}
  return row("can", "", "", { chips: ["chat", "vision", "video", "tools", "reasoning"].map(function(x) {
    return { text: x + (caps[x] == null ? " ?" : ""), off: caps[x] !== true }
  }) })
}

// the eyebrow word for what the controller is doing, and which load step that is
var STEP = { weights: 0, image: 1, engine: 2, check: 3 }
function opWord(snap) {
  var st = snap.state, d = snap.operation.detail || ""
  if (st === "download") return /weights|download|GB|copy/i.test(d) ? "downloading" : /pull/i.test(d) ? "pulling" : "starting"   // the controller's "download" op also covers the checks before a start
  if (st === "unload") return "stopping"
  if (st === "share") return "sharing"
  if (/pulling/.test(d)) return "pulling"
  if (/loading|starting/.test(d) || d === "") return "starting"
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
function fits(snap, c, n) { return (snap.recipes || []).filter(function(r) { return r.hardwareId === c.hardwareId && r.cards === n }) }
function where(snap, m) { var c = cardOfKeys(snap, m.keys); return (m.cards > 1 ? m.cards + "× " : "") + (c ? c.name : "card") }
function workKeys(snap) { // the cards a running op touches: the model it stops, or the claim of the recipe it starts
  var id = snap.operation.recipeId || "", m = modelById(snap, id)
  if (m) return m.keys
  return snap.selected && snap.selected.recipeId === id ? (snap.selected.keys || []) : []
}
function shortError(c) {
  var e = c.localError || c.snap.error || c.snap.reason || ""
  if (c.localError) return "no answer"
  if (c.snap.reason && !c.snap.error) return /^no supported GPU/.test(e) ? "no card" : /^no validated recipe/.test(e) ? "no recipe" : /^port /.test(e) ? "port busy" : /driver/.test(e) ? "driver" : "refused"
  if (/out of memory|OOM|VRAM/i.test(e)) return "out of VRAM"
  if (/below the .* floor/.test(e)) return "too slow"
  if (/stopped unexpectedly|crash/.test(e)) return "stopped"
  if (/acceptance failed/.test(e)) return "acceptance failed"
  if (/did not answer|not answering/.test(e)) return "no answer"
  if (/refused|dismissed/.test(e)) return "refused"
  if (/docker/i.test(e)) return "docker"
  if (/space/.test(e)) return "disk full"
  return "error"
}

// one cell per physical card of a group: what holds it, or its temperature
function cells(c, group, work) {
  var snap = c.snap, keys = work ? workKeys(snap) : [], word = work ? opWord(snap) : ""
  return group.keys.map(function(k) {
    var m = holder(snap, k), g = gpu(snap, k)
    if (work && keys.indexOf(k) >= 0 && word === "stopping") return { text: "freeing", mark: "freeing" }
    if (work && keys.indexOf(k) >= 0 && word !== "sharing") return { text: "claimed", mark: "claimed" }
    if (m && m.state === "error") return { text: "crashed", mark: "crashed" }
    if (m) return { text: "#" + k.split(":")[1] + " locked", mark: "used" }
    return { text: "free" + (g && g.tempC !== null && g.tempC !== undefined ? " · " + g.tempC + "°" : ""), mark: "free" }
  })
}
function cardRows(c, work, nested) {
  var snap = c.snap, out = [sec("gpus")], cs = snap.cards || []
  for (var i = 0; i < cs.length; i++) { var g = cs[i], free = freeKeys(snap, g).length, held = g.keys.length - free
    var n = fits(snap, g, 1).length + fits(snap, g, 2).length, can = !work && free > 0 && held === 0 && n > 0   // a type with a model on it is reached through that model
    out.push(row(g.count + "× " + g.name, work ? g.totalGb + " GB" : can ? n + (n === 1 ? " recipe ›" : " recipes ›") : held ? held + " locked" : n ? "" : "no recipe",
      can ? "card:" + g.hardwareId : "", { cells: cells(c, g, work), disabled: !work && !can && held === 0 }))
    if (nested) models(snap).filter(function(m) { return m.keys.some(function(k) { return g.keys.indexOf(k) >= 0 }) }).forEach(function(m) {
      out.push(row(m.name, m.state === "error" ? "crashed ›" : m.state !== "ready" ? m.state + " ›" : (m.decodeTps || 0) + " tok/s ›", "model:" + m.recipeId,
        { child: true, urgent: m.state !== "ready", cells: [{ text: ":" + m.port + (m.shareUrl ? " · shared" : ""), mark: "" }] }))
    })
  }
  if (!cs.length) out.push(row("card", "none", "", { urgent: true }))
  return out
}

function build(c) {
  var snap = c.snap, ms = models(snap), op = snap.operation || {}, o = { steps: -1, path: [{ n: "local ai", v: "home" }], rows: [], foot: [] }
  var working = ["download", "starting", "unload", "share"].indexOf(snap.state) >= 0 || (c.pending && ["run", "load", "unload", "share"].indexOf(c.lastVerb) >= 0)
  var error = !working && c.view === "home" && (c.localError !== "" || snap.state === "error" || (snap.reason || "") !== "")
  var crashed = ms.filter(function(m) { return m.state === "error" })
  // ---- work: the card is busy; nothing else is clickable
  if (working) {
    var w = snap.state === "download" || snap.state === "starting" || snap.state === "unload" || snap.state === "share" ? opWord(snap) : (c.lastVerb === "unload" ? "stopping" : c.lastVerb === "share" ? "sharing" : snap.selected && !snap.selected.onDisk ? "downloading" : "starting")
    var who = recipeById(snap, op.recipeId) || modelById(snap, op.recipeId) || (snap.selected ? { name: snap.selected.name } : { name: "Local AI" })
    var r = recipeById(snap, op.recipeId) || { sizeGb: 0 }
    o.tone = "work"; o.eyebrow = w; o.title = who.name
    o.sub = w === "downloading" && op.percent > 0 && r.sizeGb ? "weights · " + gb(op.percent / 100 * r.sizeGb) + " of " + gb(r.sizeGb) : (op.detail || { downloading: "weights", pulling: "engine image", starting: "engine warming", checking: "acceptance", stopping: "containers coming down", sharing: "gateway restarting on the tailnet" }[w])
    if (w !== "stopping" && w !== "sharing") { o.steps = opStep(w); var hw = r.hardwareId ? cardByHw(snap, r.hardwareId) : null; if (hw) o.path.push({ n: hw.name.toLowerCase(), v: "card" }) }
    else { var wm = modelById(snap, op.recipeId); o.path.push({ n: (wm ? wm.name : who.name).toLowerCase(), v: "model" }) }
    o.path.push({ n: w, v: "work" })
    var late = op.expectedSeconds > 0 && c.elapsed > op.expectedSeconds * 1.5
    var pct = op.percent > 0 ? op.percent : (op.expectedSeconds > 0 && c.elapsed > 0 ? Math.min(95, Math.round(c.elapsed * 100 / op.expectedSeconds)) : 0)
    o.rows.push(row(w, late ? mmss(c.elapsed) + " · longer than usual" : pct > 0 ? pct + "%" + (c.elapsed > 0 ? " · " + mmss(c.elapsed) : "") : c.elapsed > 0 ? mmss(c.elapsed) : "…", "", { type: "status" }))
    o.rows.push({ type: "bar", percent: pct, label: "", value: "", action: "", kind: "" })
    if (w !== "downloading" && w !== "sharing") o.rows = o.rows.concat(cardRows(c, true).filter(function(x) { return x.type === "sec" || (x.cells && x.cells.some(function(k) { return k.mark === "claimed" || k.mark === "freeing" })) }))
    if (w === "downloading" && !c.pending) o.foot.push(row("stop", "keeps weights", "stop-download", { kind: "danger" }))
    return o
  }
  // ---- error: the last verb failed
  if (error) {
    o.tone = "error"; o.eyebrow = "error"; o.title = shortError(c); o.sub = snap.selected ? snap.selected.name : ""
    var why = c.localError ? "the plugin did not answer" : snap.error || snap.reason || ""
    o.rows.push(row(c.localError ? "plugin" : snap.error ? "engine" : "recipe", why, "", { urgent: true, type: "text" }))
    o.rows.push(row("run again", snap.selected ? snap.selected.name : "", c.localError ? "refresh" : "run-again", { kind: "primary", disabled: !snap.selected && !c.localError }))
    o.rows.push(row("log", "open ›", "log"))
    o.rows = o.rows.concat(cardRows(c, false))
    return o
  }
  var total = (snap.cards || []).reduce(function(a, g) { return a + g.count }, 0)
  var view = c.view === "model" && !modelById(snap, c.slotSel) ? "home" : c.view === "card" && !cardByHw(snap, c.hw) ? "home" : c.view   // a place that is gone falls back to home
  // ---- model: one running model, its numbers first
  if (view === "model") {
    var m = modelById(snap, c.slotSel)
    {
      var cg = cardOfKeys(snap, m.keys)
      o.tone = m.state === "error" ? "error" : "ready"; o.eyebrow = m.state === "error" ? "crashed" : m.state === "ready" ? "ready" : m.state; o.title = m.name
      o.sub = where(snap, m) + " · :" + m.port + (m.shareUrl ? " · shared" : "")
      o.path.push({ n: m.name.toLowerCase(), v: "model" })
      if (m.state !== "ready") {
        o.rows.push(row("engine", m.note || "stopped unexpectedly", "", { urgent: true, type: "text" }))
        o.rows.push(row("run again", m.name, "run-again", { kind: "primary" })); o.rows.push(row("log", "open ›", "log"))
        o.foot.push(row("stop", m.name, "stop:" + m.recipeId, { kind: "danger" })); return o
      }
      o.rows.push({ type: "stat", stat: [{ k: "decode", v: String(m.decodeTps || 0), u: "tok/s" }, { k: "prefill", v: m.prefillTps > 0 ? String(m.prefillTps) : "n/a", u: m.prefillTps > 0 ? "tok/s" : "" }], label: "", value: "", action: "", kind: "" })
      o.rows.push({ type: "stat", stat: [{ k: "tokens today", v: kmg(m.tokensToday || 0), u: "" }, { k: "kv cache", v: m.kvTokens > 0 ? kb(m.kvTokens) : "n/a", u: m.ctxTokens > 0 ? kb(m.ctxTokens) + " ctx" : "" }], label: "", value: "", action: "", kind: "" })
      o.rows.push(row(where(snap, m), ":" + m.port, "", { cells: m.keys.map(function(k) { var g = gpu(snap, k) || {}; var t = []
        if (g.tempC !== null && g.tempC !== undefined) t.push(g.tempC + "°"); if (g.utilPct !== null && g.utilPct !== undefined) t.push(g.utilPct + "%"); if (g.usedGb !== null && g.usedGb !== undefined) t.push(Math.round(g.usedGb) + "/" + g.vramGb + "G")
        return { text: "#" + k.split(":")[1] + (t.length ? " " + t.join(" ") : ""), mark: "used" } }) }))
      o.rows.push(capabilities(m.caps))
      var agents = m.launchable || [], a = agents.indexOf(c.agentPick) >= 0 ? c.agentPick : (agents.indexOf((snap.agents || {}).default) >= 0 ? snap.agents.default : agents[0] || "")
      if (agents.length) {
        o.rows.push(row("agent", a + (c.agentOpen ? " ▴" : " ▾"), "agent-toggle"))
        if (c.agentOpen) agents.forEach(function(x) { o.rows.push(row(x, x === (snap.agents || {}).default ? "default" : "", "agent:" + x, { kind: "dd", selected: x === a })) })
      } else o.rows.push(row("agent", "none can use it", "", { urgent: true }))
      var sh = snap.share || {}
      if (!sh.available) o.rows.push(row("share", "no tailscale", "", { disabled: true }))
      else if (!m.shareUrl) o.rows.push(row("share", "off · tailnet ›", "share"))
      else o.rows.push(row("share", "on", "share", { chips: [{ text: m.shareUrl.replace(/^https?:\/\//, ""), off: false }, { text: c.copied ? "copied" : "copy", off: false, action: "copy:" + m.recipeId }] }))
      if (a !== "") o.foot.push(row("open " + a, m.name, "open-agent:" + a + ":" + m.recipeId, { kind: "primary" }))
      o.foot.push(row("stop", m.name, "stop:" + m.recipeId, { kind: "danger" }))
      return o
    }
  }
  // ---- card: one card type, how many, which recipe
  if (view === "card") {
    var g = cardByHw(snap, c.hw)
    {
      var free = freeKeys(snap, g), n = Math.max(1, Math.min(c.count || 1, free.length))
      o.tone = "idle"; o.eyebrow = "idle"; o.title = g.name; o.sub = free.length + " of " + g.keys.length + " free · " + g.vramGb + " GB each"
      o.path.push({ n: g.name.toLowerCase(), v: "card" }); if (n > 1) o.path.push({ n: n + " cards", v: "card" })
      if (free.length > 1) { var tabs = []; for (var k = 1; k <= free.length; k++) tabs.push({ text: k + "× · " + k * g.vramGb + " GB", on: k === n, action: "count:" + k }); o.rows.push(row("use", "", "", { tabs: tabs })) }
      var list = fits(snap, g, n)
      o.rows.push(sec("recipes for " + n + (n > 1 ? " cards" : " card") + " · " + list.length))
      if (!list.length) o.rows.push(row("recipe", "none uses " + n + " cards"))
      var dup = {}; list.forEach(function(r) { dup[r.name] = (dup[r.name] || 0) + 1 })   // two recipes of one model: say which
      list.forEach(function(r) { o.rows.push(row(dup[r.name] > 1 && r.precision ? r.name + " · " + r.precision : r.name, r.running ? "running" : r.onDisk ? gb(r.sizeGb) + " · on disk" : r.partialBytes > 0 ? gb(r.partialBytes / 1073741824) + " of " + gb(r.sizeGb) + " · resume" : gb(r.sizeGb) + " · download", "pick:" + r.id, { selected: c.pick === r.id })) })
      var p = recipeById(snap, c.pick)
      if (p && p.hardwareId === g.hardwareId && p.cards === n) {
        o.rows.push(row("context", p.ctxTokens > 0 ? kb(p.ctxTokens) + " per request" : "unknown"))
        o.rows.push(capabilities(p.caps))
      }
      if (p && p.running) o.foot.push(row("open", p.name, "model:" + p.id, { kind: "primary" }))
      else if (p && p.hardwareId === g.hardwareId && p.cards === n) o.foot.push(row(p.onDisk ? "run" : p.partialBytes > 0 ? "resume + run" : "download " + gb(p.sizeGb) + " + run", p.name, "run:" + p.id + ":" + n, { kind: "primary" }))
      else o.foot.push(row("run", "pick a recipe", "", { disabled: true }))
      return o
    }
  }
  // ---- home: what you have and what runs on it
  if (!ms.length) { o.tone = (snap.cards || []).length ? "idle" : "error"; o.eyebrow = (snap.cards || []).length ? "idle" : "no card"; o.title = "Local AI"; o.sub = (snap.cards || []).length ? total + " cards free · nothing running" : "no supported GPU" }
  else { var used = ms.reduce(function(a, m) { return a + m.cards }, 0)
    o.tone = crashed.length ? "error" : "ready"; o.eyebrow = crashed.length ? "crashed" : "ready"; o.title = ms.length === 1 ? ms[0].name : ms.length + " models"
    o.sub = "on " + used + " of " + total + " cards" + (ms.some(function(m) { return m.shareUrl }) ? " · shared" : "") }
  o.rows = cardRows(c, false, true)
  return o
}
