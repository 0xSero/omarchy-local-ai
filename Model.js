// The card's content, as data. build(c) turns a snapshot and the panel's state into a hero and rows;
// Panel.qml draws what comes back and turns row actions into backend verbs. No Qt here, so node tests it.
//
// c: { snap, view:"home"|"stats"|"open", pending, lastVerb, elapsed, localError }
// hero: { eyebrow, title, sub, right, rightAction, tone:"idle"|"work"|"ready"|"error" }
// row types: num2 {a:{v,k}, b:{v,k}}; bars {values, hi}; prog {left, right, pct}; text {text, lead};
//            gpu {idx, name, temp, pct, used, total, busy}; row {label, small, verb, action, dim, disabled};
//            h {label, right}; hbar {label, pct, right}; spark {values}; axis {labels}; opt {label, small, on, action}; field {value}

function gb(n) { return (n >= 100 ? Math.round(n) : Math.round(n * 10) / 10) + " GB" }
function k(n) { return n >= 1e6 ? (Math.round(n / 1e5) / 10) + "M" : n >= 1e3 ? (Math.round(n / 100) / 10) + "K" : String(n || 0) }
function mmss(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
function row(label, small, verb, action, o) { o = o || {}; o.type = "row"; o.label = label; o.small = small || ""; o.verb = verb || ""; o.action = action || ""; return o }
function models(snap) { return (snap.models || []).filter(function(m) { return m.state !== "stopped" }) }
function find(list, key, v) { list = list || []; for (var i = 0; i < list.length; i++) if (list[i][key] === v) return list[i]; return null }
function cardOf(snap, key) { var cs = snap.cards || []; for (var i = 0; i < cs.length; i++) if (cs[i].keys.indexOf(key) >= 0) return cs[i]; return null }
function holder(snap, key) { var ms = models(snap); for (var i = 0; i < ms.length; i++) if (ms[i].keys.indexOf(key) >= 0) return ms[i]; return null }
function where(snap, m) { var c = cardOf(snap, m.keys[0] || ""); return (m.keys.length > 1 ? m.keys.length + "× " : "") + (c ? c.name : "GPU") + (c && c.count > 1 ? " #" + m.keys.map(function(x) { return x.split(":")[1] }).join(" #") : "") }
function freeKeys(snap, card) { return card.keys.filter(function(x) { return !holder(snap, x) }) }
function freest(snap, keys) { return keys.slice().sort(function(a, b) { var ga = find(snap.gpus, "key", a) || {}, gb2 = find(snap.gpus, "key", b) || {}; return ((gb2.vramGb || 0) - (gb2.usedGb || 0)) - ((ga.vramGb || 0) - (ga.usedGb || 0)) })[0] }
var WORD = { download: "downloading", starting: "starting", unload: "stopping" }
function isWorking(c) { return WORD[c.snap.state] !== undefined || (c.pending && ["load", "unload"].indexOf(c.lastVerb) >= 0) }
function shortError(e) {
  var t = [[/out of memory|OOM|VRAM/i, "out of VRAM"], [/tok\/s|too slow/, "too slow"], [/stopped unexpectedly|crash/, "stopped"], [/acceptance failed/, "acceptance failed"], [/did not answer|not answering|no answer/, "no answer"],
    [/refused|dismissed/, "refused"], [/docker/i, "docker"], [/space|GB free/, "disk full"], [/checksum|Hub|download/, "download failed"], [/driver/, "driver"], [/port /, "port busy"], [/no supported GPU/, "no GPU"], [/no validated recipe/, "no recipe"]]
  for (var i = 0; i < t.length; i++) if (t[i][0].test(e)) return t[i][1]
  return "failed"
}

function gpuRows(snap, out) {
  (snap.gpus || []).forEach(function(g) {
    var c = cardOf(snap, g.key), m = holder(snap, g.key)
    out.push({ type: "gpu", idx: "#" + g.index, name: c ? c.name : g.product, temp: g.tempC == null ? "" : g.tempC + "°",
      pct: g.vramGb > 0 && g.usedGb != null ? Math.min(100, Math.round(g.usedGb / g.vramGb * 100)) : 0,
      used: g.usedGb == null ? "" : String(Math.round(g.usedGb)), total: g.vramGb == null ? "" : String(g.vramGb), busy: !!m, action: "" })
  })
}
function agentRow(snap) {
  var a = snap.agents || {}, m = models(snap).filter(function(x) { return x.state === "ready" })
  var name = a.default && a.installed && a.installed.indexOf(a.default) >= 0 ? a.default : (a.installed || [])[0] || ""
  if (!m.length || !name) return null
  var dir = (a.directory || "").replace(/^\/home\/[^\/]+/, "~")
  return row(name, dir, "open", "open-agent", { changeAction: "open" })
}
function modelRows(c, out) {
  var snap = c.snap, ms = models(snap), busy = isWorking(c), op = snap.operation || {}
  ms.forEach(function(m) {
    var working = busy && op.recipeId === m.recipeId
    out.push(row(m.name, where(snap, m) + (m.state === "error" ? " · " + shortError(m.note || "") : working ? " · " + (WORD[snap.state] || "working") : ""), working ? "" : m.state === "error" ? "run again" : "stop",
      working ? "" : m.state === "error" ? "run:" + m.recipeId : "stop:" + m.recipeId))
  })
  if (busy && !find(ms, "recipeId", op.recipeId)) { var r = find(snap.recipes, "id", op.recipeId); out.push(row(r ? r.name : "Local AI", WORD[snap.state] || "working", "stop", snap.state === "download" ? "stop-download" : "")) }
  ;(snap.cards || []).forEach(function(card) {
    var r = card.recipe; if (!r || !freeKeys(snap, card).length || busy) return
    if (r.gate) return out.push(row(r.name, card.name + " · " + r.gate, "", "", { dim: true, disabled: true }))
    var again = snap.state === "error" && snap.selected && snap.selected.recipeId === r.id
    out.push(row(r.name, card.name + (r.onDisk ? "" : " · " + gb(r.sizeGb)), again ? "run again" : r.onDisk ? "run" : r.partialBytes > 0 ? "resume" : "download & run", "run:" + r.id))
  })
}

function home(c, o) {
  var snap = c.snap, ms = models(snap), ready = ms.filter(function(m) { return m.state === "ready" }), st = snap.stats || {}, op = snap.operation || {}
  var gpus = (snap.gpus || []).length, working = isWorking(c), failed = !working && (c.localError || snap.state === "error" || (snap.reason && !gpus))
  o.hero.right = "stats"; o.hero.rightAction = "stats"
  if (working) {
    var w = WORD[snap.state] || (c.lastVerb === "unload" ? "stopping" : "starting"), r = find(snap.recipes, "id", op.recipeId) || { name: (snap.selected || {}).name || "Local AI", sizeGb: 0 }
    o.hero.tone = "work"; o.hero.eyebrow = w.toUpperCase(); o.hero.title = r.name; o.hero.sub = r.hardwareId ? ((find(snap.cards, "hardwareId", r.hardwareId) || {}).name || "") : ""
    var pct = op.percent > 0 ? op.percent : (op.expectedSeconds > 0 && c.elapsed > 0 ? Math.min(95, Math.round(c.elapsed * 100 / op.expectedSeconds)) : 0)
    var left = w === "downloading" && op.percent > 0 && r.sizeGb ? gb(op.percent / 100 * r.sizeGb) + " of " + gb(r.sizeGb) : (op.detail || w)
    o.rows.push({ type: "prog", left: left, right: c.elapsed > 0 ? mmss(c.elapsed) : "", pct: pct })
  } else if (failed) {
    var e = c.localError ? "the plugin did not answer" : snap.error || snap.reason || ""
    o.hero.tone = "error"; o.hero.eyebrow = "FAILED"; o.hero.title = snap.selected ? snap.selected.name : "Local AI"; o.hero.sub = shortError(e)
    o.rows.push({ type: "text", lead: snap.helpText && snap.helpText !== e ? snap.helpText : "", text: e })
  } else if (ready.length) {
    o.hero.tone = "ready"; o.hero.eyebrow = "READY"; o.hero.title = ready.length === 1 ? ready[0].name : ready.length + " models"; o.hero.sub = ready.map(function(m) { return where(snap, m) }).join(" · ")
    o.rows.push({ type: "num2", a: { v: st.decode != null ? String(st.decode) : "–", k: "DECODE tok/s" }, b: { v: k(st.today || 0), k: "TOKENS TODAY" } })
    o.rows.push({ type: "bars", values: st.days || [0, 0, 0, 0, 0, 0, 0], hi: 6 })
  } else {
    o.hero.tone = "idle"; o.hero.eyebrow = "IDLE"; o.hero.title = "Local AI"; o.hero.sub = gpus ? gpus + (gpus === 1 ? " GPU" : " GPUs") : "no supported GPU"
    if (snap.statusText) o.rows.push({ type: "text", lead: snap.statusText, text: snap.helpText || "" })
    else if ((st.days || []).some(function(n) { return n > 0 })) { o.rows.push({ type: "num2", a: { v: k((st.days || []).reduce(function(a, b) { return a + b }, 0)), k: "TOKENS · 7 DAYS" }, b: { v: "", k: "" } }); o.rows.push({ type: "bars", values: st.days, hi: 6 }) }
  }
  gpuRows(snap, o.rows)
  var acts = []
  var ag = agentRow(snap); if (ag && !working) acts.push(ag)
  modelRows(c, acts)
  if (failed) acts.push(row("log", "", "open", "log", { dim: true }))
  if (acts.length) { o.rows.push({ type: "gap" }); o.rows = o.rows.concat(acts) }
}
function stats(c, o) {
  var snap = c.snap, st = snap.stats || {}, days = st.days || [0, 0, 0, 0, 0, 0, 0], total = days.reduce(function(a, b) { return a + b }, 0)
  var ready = models(snap).filter(function(m) { return m.state === "ready" })
  o.hero.tone = ready.length ? "ready" : "idle"; o.hero.eyebrow = "STATS"; o.hero.title = ready.length === 1 ? ready[0].name : "Local AI"; o.hero.sub = "7 days"; o.hero.right = "back"; o.hero.rightAction = "back"
  var names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], d = new Date().getDay(), labels = []
  for (var i = 6; i >= 0; i--) labels.push(i === 0 ? "today" : names[((d - i) % 7 + 6) % 7])
  o.rows.push({ type: "h", label: "TOKENS BY DAY", right: k(total) })
  o.rows.push({ type: "bars", values: days, hi: 6, big: true }); o.rows.push({ type: "axis", labels: labels })
  var bm = st.byModel || [], peak = bm.length ? bm[0].tokens : 1
  if (bm.length) { o.rows.push({ type: "h", label: "BY MODEL", right: "" }); bm.slice(0, 4).forEach(function(x) { o.rows.push({ type: "hbar", label: x.model, pct: Math.round(x.tokens / peak * 100), right: k(x.tokens) }) }) }
  var hours = st.hours || []
  if (hours.some(function(v) { return v != null })) {
    o.rows.push({ type: "h", label: "DECODE · 24 H", right: st.decode != null ? st.decode + " tok/s now" : "" })
    o.rows.push({ type: "spark", values: hours }); o.rows.push({ type: "axis", labels: ["yesterday", "", "", "now"] })
  }
  if (!total && !hours.length) o.rows.push({ type: "text", lead: "", text: "nothing served yet · tokens and speed appear here once an agent has used a model" })
}
function open(c, o) {
  var snap = c.snap, a = snap.agents || {}, ready = models(snap).filter(function(m) { return m.state === "ready" }), m = ready[0]
  var pick = a.default && (a.installed || []).indexOf(a.default) >= 0 ? a.default : (a.installed || [])[0] || ""
  o.hero.tone = "ready"; o.hero.eyebrow = "OPEN"; o.hero.title = m ? m.name : "Local AI"; o.hero.sub = m ? where(snap, m) : ""; o.hero.right = "back"; o.hero.rightAction = "back"
  o.rows.push({ type: "h", label: "AGENT", right: "" })
  ;(a.installed || []).forEach(function(x) { var ok = !m || (m.launchable || []).indexOf(x) >= 0; o.rows.push({ type: "opt", label: x, small: ok ? "" : "cannot use this model", on: x === pick, action: ok ? "agent:" + x : "", disabled: !ok }) })
  if (!(a.installed || []).length) o.rows.push({ type: "text", lead: "", text: "no coding agent is installed · install claude, codex, pi, opencode or another one first" })
  o.rows.push({ type: "h", label: "PROJECT", right: "" })
  o.rows.push({ type: "field", value: a.directory || "" })
  if (m && pick) { o.rows.push({ type: "gap" }); o.rows.push(row("open " + pick, (a.directory || "").replace(/^\/home\/[^\/]+/, "~"), "open", "open-agent")) }
}
function build(c) {
  var o = { hero: { eyebrow: "", title: "", sub: "", right: "", rightAction: "", tone: "idle" }, rows: [] }
  var v = c.view === "open" && !models(c.snap).some(function(m) { return m.state === "ready" }) ? "home" : c.view
  if (v === "stats") stats(c, o); else if (v === "open") open(c, o); else home(c, o)
  return o
}
function loadKeys(snap, id) { // the GPU a load takes: the freest free card of the recipe's type
  var r = find(snap.recipes, "id", id); if (!r) return []
  var card = find(snap.cards, "hardwareId", r.hardwareId); if (!card) return []
  var free = freeKeys(snap, card); return free.length ? [freest(snap, free)] : []
}

if (typeof module !== "undefined") module.exports = { gb: gb, k: k, mmss: mmss, models: models, where: where, isWorking: isWorking, shortError: shortError, build: build, loadKeys: loadKeys }
