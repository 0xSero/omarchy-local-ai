// What the Local AI widget shows, as data: the backend's snapshot and the widget's ui state in, a view out.
// Panel.qml draws the view and turns its actions ("verb|arg|arg") into backend verbs. No Qt, no side effects.

function k(n) {
  n = n || 0
  return n >= 1e6 ? Math.round(n / 1e5) / 10 + "M" : n >= 1e3 ? Math.round(n / 100) / 10 + "K" : String(n)
}
function gb(n) { return (n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + " GB" }
function ctx(n) { return n >= 1024 ? Math.round(n / 1024) + "K" : String(n || 0) }
function dur(s) {
  s = Math.max(0, Math.round(s))
  return s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + ":" + ("0" + Math.floor(s % 3600 / 60)).slice(-2) + "h"
}
function home(dir) { return (dir || "").replace(/^\/home\/[^\/]+/, "~") }
function find(list, key, v) { return (list || []).filter(function(x) { return x[key] === v })[0] || null }
function working(d) { return d.state === "download" || d.state === "starting" || d.state === "stopping" }

function caps(c, n) {
  c = c || {}
  return [c.vision && "vision", c.tools && "tools", c.reasoning && "reasoning", n && ctx(n) + " context"].filter(Boolean)
}
function parse(text) { try { return JSON.parse(text) } catch (e) { return null } }

// APCA-W3 0.1.9 lightness contrast (Lc) of text on a background. Colors are {r, g, b} in 0..1, as Qt gives them.
// Every text and line color in the panel is picked by the Lc it must reach, so any theme stays readable.
function lum(c) { return 0.2126729 * Math.pow(c.r, 2.4) + 0.7151522 * Math.pow(c.g, 2.4) + 0.072175 * Math.pow(c.b, 2.4) }
function apca(text, bg) {
  var t = lum(text), b = lum(bg)
  if (t < 0.022) t += Math.pow(0.022 - t, 1.414)
  if (b < 0.022) b += Math.pow(0.022 - b, 1.414)
  if (Math.abs(b - t) < 0.0005) return 0
  var s = b > t ? (Math.pow(b, 0.56) - Math.pow(t, 0.57)) * 1.14 : (Math.pow(b, 0.65) - Math.pow(t, 0.62)) * 1.14
  return Math.abs(s) < 0.1 ? 0 : (s > 0 ? s - 0.027 : s + 0.027) * 100
}
function mix(a, b, t) { return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: 1 } }
// a translucent color as it lands on an opaque one
function over(c, bg) { var a = c.a === undefined ? 1 : c.a; return mix(bg, c, a) }
// the color closest to `from` on the way to `to` that reaches |Lc| >= target on bg; `to` when nothing does
function reach(from, to, bg, target) {
  if (Math.abs(apca(from, bg)) >= target) return mix(from, from, 0)
  if (Math.abs(apca(to, bg)) < target) return mix(to, to, 0)
  var lo = 0, hi = 1
  for (var i = 0; i < 24; i++) {
    var m = (lo + hi) / 2
    if (Math.abs(apca(mix(from, to, m), bg)) >= target) hi = m
    else lo = m
  }
  return mix(from, to, hi)
}
// The panel's tones, all measured on the card surface (the lighter of its two backgrounds, so the worst case):
// ink is for what matters now (a model's name, the primary action, a choice made), value for what a label
// names, label for every label, rule for lines and borders that are not text, alert for problems.
// A theme whose foreground is too soft to lead is pushed toward white (or black, on a light theme) until it does.
var LC = { ink: 90, value: 80, label: 60, rule: 15, alert: 60 }
function tones(ink, bg, surface, urgent) {
  var card = over(surface, bg), white = { r: 1, g: 1, b: 1 }, black = { r: 0, g: 0, b: 0 }
  var far = Math.abs(apca(white, card)) > Math.abs(apca(black, card)) ? white : black
  var top = reach(over(ink, bg), far, card, LC.ink)
  return { ink: top, value: reach(card, top, card, LC.value), label: reach(card, top, card, LC.label),
    rule: reach(card, top, card, LC.rule), alert: reach(urgent, top, card, LC.alert), alertRule: reach(urgent, top, card, LC.rule) }
}

// the bar mark: failed, busy, ready or idle
function mark(s) {
  var d = (s && s.deployments) || []
  if (d.some(function(x) { return x.state === "error" })) return "failed"
  if (d.some(working)) return "busy"
  return d.some(function(x) { return x.state === "ready" }) ? "ready" : ""
}

// home: one panel per running model, then one list of the other cards: free ones to run on, busy or
// unsupported ones and why
function homeView(s, ui) {
  if (!s.gpus) return { title: "LOCAL AI", rows: ui.problem ? [{ type: "error", label: ui.problem }] : [] }
  var rows = [], cards = [], shown = {}
  if (ui.problem) rows.push({ type: "error", label: ui.problem })
  function panel(d) {
    shown[d.id] = 1
    var all = (d.session || {}).all || {}
    var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 })
    // a card that does not report its memory in use (Intel) shows only how much it has
    var known = cards.every(function(g) { return g.usedMiB != null })
    var used = cards.reduce(function(a, g) { return a + (g.usedMiB || 0) / 1024 }, 0)
    var total = cards.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0)
    var r = { type: "run", name: d.name, family: d.family, line: all.line || [], more: "more|" + d.id,
      gpu: (cards.length > 1 ? cards.length + " × " : "") + (cards[0] ? cards[0].name : "GPU")
        + (total && !working(d) ? " · " + (known ? Math.round(used) + " / " : "") + total + " GB" : "")
        + (d.caps && d.caps.vision ? " · vision" : "") }
    if (d.state === "ready") {
      r.sub = [all.decode ? all.decode + " tok/s avg" : "no requests yet", k(all.tokens) + " tokens all time"]
      r.primary = { label: "Open " + d.agent, action: "open|" + d.id }
    } else if (working(d)) {
      r.progress = d.percent > 0 && d.state !== "stopping" ? d.percent : -1
      r.sub = [(d.detail || d.state) + (r.progress >= 0 && d.state !== "download" ? " · " + d.percent + "%" : "")]
      r.primary = { label: "Stop", action: "stop|" + d.id, quiet: true }
    } else {
      r.sub = [d.error || "stopped"]
      r.error = true
      r.primary = { label: "Run again", action: "again|" + d.id + "|" + d.keys.join(",") }
    }
    rows.push(r)
  }
  ;(s.kinds || []).forEach(function(kd) {
    ;(s.deployments || []).filter(function(d) {
      return d.keys.some(function(x) { return kd.keys.indexOf(x) >= 0 })
    }).forEach(panel)
    var r = kd.recipe
    if (kd.free.length) cards.push({ type: "free", label: kd.free.length + " × " + kd.name, model: r.name,
      family: r.family, more: "kind|" + kd.hw, action: "run|" + r.id + "|" + kd.free[0] })
    if (kd.taken.length) cards.push({ type: "busy", label: kd.taken.length + " × " + kd.name, note: "in use by another program", warn: true })
  })
  ;(s.deployments || []).filter(function(d) { return !shown[d.id] }).forEach(panel)
  if (!(s.kinds || []).length && !(s.deployments || []).length) return soonView(s)
  ;(s.unsupported || []).forEach(function(u) { cards.push({ type: "busy", label: u.n + " × " + u.name, note: "no validated model yet" }) })
  if (cards.length) rows = rows.concat([{ type: "sec", label: "GPUS" }], cards)
  return { title: "LOCAL AI", version: s.version, stat: k(s.week), statLabel: "this week", rows: rows }
}

// nothing to run on: one line on what this machine has, and where the list of supported cards lives
function soonView(s) {
  var found = (s.gpus || []).map(function(g) { return g.name }).filter(function(n, i, a) { return a.indexOf(n) === i })
  return { title: "LOCAL AI", version: s.version, rows: [{ type: "soon",
    head: found.length ? "No tested model for " + found.join(", ") + " yet" : "No supported GPU on this machine",
    action: "url|https://github.com/0xSero/local-ai-registry/blob/main/supported/README.md" }] }
}

// a running model's page: its token line, six figures, its cards, what Open uses, where it answers
function runView(s, id, ui) {
  var d = find(s.deployments, "id", id)
  if (!d) return null
  var u = d.session || {}, all = u.all || {}, line = all.line || [], top = line.length ? line[line.length - 1] : 0
  var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 })
  var v = { back: true, rows: [], hero: { name: d.name, family: d.family, line: line,
    top: k(top) + " tokens", mid: k(Math.round(top / 2)), since: all.since || "", now: "now",
    sub: [d.format, d.keys.length + " × " + (cards[0] ? cards[0].name : "GPU")].filter(Boolean).join(" · "),
    caps: caps(d.caps, d.ctx).join(" · ") } }
  v.rows.push({ type: "grid", cells: [
    { v: all.decode != null ? String(all.decode) : "–", u: "tok/s", k: "decode avg" },
    { v: all.prefill != null ? k(all.prefill) : "–", u: "tok/s", k: "prefill avg" },
    { v: all.ttft != null ? (all.ttft / 1000).toFixed(1) : "–", u: "s", k: "first token" },
    { v: k(u.tokens), u: "", k: "session" },
    { v: k(s.week), u: "", k: "week" },
    { v: dur((Date.now() - Date.parse(d.startedAt)) / 1000), u: "", k: "up" }] })
  v.rows.push({ type: "sec", label: "GPUS" })
  cards.forEach(function(g) { v.rows.push(gpuRow(g)) })
  v.rows.push({ type: "sec", label: "OPENS WITH" })
  pickers(s, v.rows, ui, d.agent, d.folder, id)
  weights(v.rows, d.weights)
  v.rows.push({ type: "sec", label: "REACH" })
  v.rows.push({ type: "field", label: "this machine", value: "127.0.0.1:" + d.port })
  if (s.tailnet) v.rows.push(d.shared
    ? { type: "field", label: "tailnet", value: d.shared, secret: true, action: "copy|" + d.shared }
    : { type: "field", label: "tailnet", value: "share", action: "share|" + id })
  if (d.error) v.rows.push({ type: "error", label: d.error })
  v.rows.push({ type: "acts", items: [{ label: "Log", action: "log" }, { label: "Stop", action: "stop|" + id, danger: true }] })
  return v
}

// a free card kind's page: the same look, with its cards in the lit panel where a running model has its line;
// each card kind has one validated model, which runs on one card
function kindView(s, hw, ui) {
  var kd = find(s.kinds, "hw", hw), pick = kd && kd.recipe
  if (!pick) return null
  var chosen = kd.free.indexOf(ui.key) >= 0 ? ui.key : kd.free[0]
  var gpus = kd.keys.map(function(key) {
    var g = find(s.gpus, "key", key), free = kd.free.indexOf(key) >= 0
    return Object.assign(gpuRow(g), { check: kd.keys.length > 1 ? key === chosen : undefined, disabled: !free,
      action: free ? "tick|" + key : "", status: kd.taken.indexOf(key) >= 0 ? "in use by another program" : g.busy ? "running a model" : "" })
  })
  var v = { back: true, rows: [], hero: { name: pick.name,
    family: pick.family, gpus: gpus, caps: caps(pick.caps, 0).join(" · "),
    sub: [pick.format, ctx(pick.ctx) + " context", gb(pick.sizeGb)].filter(Boolean).join(" · ") } }
  v.rows.push({ type: "sec", label: "OPENS WITH" })
  pickers(s, v.rows, ui, s.defaults.agent, s.defaults.folder, "")
  weights(v.rows, pick.weights)
  v.rows.push({ type: "acts", items: [{ label: "Run ›", action: chosen ? "run|" + pick.id + "|" + chosen : "", primary: true }] })
  return v
}

function gpuRow(g) {
  var used = g.usedMiB != null ? g.usedMiB / 1024 : null
  return { type: "gpu", name: g.name, bar: used != null, pct: used != null && g.vramGb ? Math.min(100, Math.round(used / g.vramGb * 100)) : 0,
    mem: (used != null ? Math.round(used * 10) / 10 + " / " : "") + g.vramGb + " GB",
    temp: g.tempC != null ? g.tempC + "°" : "" }
}

function weights(rows, list) {
  if (!(list || []).length) return
  rows.push({ type: "sec", label: "WEIGHTS" })
  list.forEach(function(w) {
    rows.push({ type: "field", label: "hugging face", value: w.repository,
      action: "url|https://huggingface.co/" + w.repository + "/tree/" + w.revision })
  })
}

// the agent and folder rows, and their choices when open; a choice on a running model also becomes the default
function pickers(s, rows, ui, agent, folder, id) {
  rows.push({ type: "field", label: "agent", value: agent, action: "pick|agent" })
  if (ui.open === "agent") (s.agents || []).forEach(function(a) {
    rows.push({ type: "opt", label: a, on: a === agent, action: "set|agent|" + a + "|" + id })
  })
  rows.push({ type: "field", label: "folder", value: home(folder), action: "pick|folder" })
  if (ui.open === "folder") {
    ;[folder].concat(s.folders || []).filter(function(f, i, a) { return f && a.indexOf(f) === i }).forEach(function(f) {
      rows.push({ type: "opt", label: home(f), on: f === folder, action: "set|folder|" + f + "|" + id })
    })
    rows.push({ type: "path", id: id })
  }
}

function build(s, ui) {
  s = s || {}
  var v = (ui.view === "run" ? runView(s, ui.id, ui) : ui.view === "kind" ? kindView(s, ui.id, ui) : null) || homeView(s, ui)
  return Object.assign(v, { mark: mark(s) })
}

if (typeof module !== "undefined") module.exports = { build: build, parse: parse, apca: apca, reach: reach, tones: tones, over: over, LC: LC }
