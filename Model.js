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

// the bar mark: failed, busy, ready or idle
function mark(s) {
  var d = (s && s.deployments) || []
  if (d.some(function(x) { return x.state === "error" })) return "failed"
  if (d.some(working)) return "busy"
  return d.some(function(x) { return x.state === "ready" }) ? "ready" : ""
}

// home: one panel per running model, one dashed line per free card kind, a bordered warning for busy ones
function homeView(s, ui) {
  if (!s.gpus) return { title: "LOCAL AI", right: "", rows: ui.problem ? [{ type: "error", label: ui.problem }] : [] }
  var rows = [], shown = {}
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
    if (kd.free.length) rows.push({ type: "free", label: kd.free.length + " × " + kd.name + " · free", model: r.name,
      family: r.family, more: "kind|" + kd.hw, action: "run|" + r.id + "|" + kd.free[0] })
    if (kd.taken.length) rows.push({ type: "busy", label: kd.taken.length + " × " + kd.name, note: "busy · another program is using it" })
  })
  ;(s.deployments || []).filter(function(d) { return !shown[d.id] }).forEach(panel)
  if (!(s.kinds || []).length && !(s.deployments || []).length) return soonView(s)
  ;(s.unsupported || []).forEach(function(u) { rows.push({ type: "busy", label: u.n + " × " + u.name, note: "no validated model yet" }) })
  return { title: "LOCAL AI", version: s.version, right: k(s.week) + " this week", rows: rows }
}

// nothing to run on: one line on what this machine has, and where the list of supported cards lives
function soonView(s) {
  var found = (s.gpus || []).map(function(g) { return g.name }).filter(function(n, i, a) { return a.indexOf(n) === i })
  return { title: "LOCAL AI", version: s.version, right: "", rows: [{ type: "soon",
    head: found.length ? "No tested model for " + found.join(", ") + " yet" : "No supported GPU on this machine",
    action: "url|https://github.com/0xSero/local-ai-registry/blob/main/supported/README.md" }] }
}

// a running model's page: its token line, six figures, its cards, what Open uses, where it answers
function runView(s, id, ui) {
  var d = find(s.deployments, "id", id)
  if (!d) return null
  var u = d.session || {}, all = u.all || {}, line = all.line || [], top = line.length ? line[line.length - 1] : 0
  var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 })
  var v = { back: true, title: "MORE", rows: [], hero: { name: d.name, family: d.family, line: line,
    top: k(top) + " tokens", mid: k(Math.round(top / 2)), since: all.since || "", now: "now",
    sub: [d.format, d.keys.length + " × " + (cards[0] ? cards[0].name : "GPU")].filter(Boolean).join(" · "),
    caps: caps(d.caps, d.ctx) } }
  v.rows.push({ type: "grid", cells: [
    { v: all.decode != null ? String(all.decode) : "–", u: "tok/s", k: "DECODE AVG" },
    { v: all.prefill != null ? k(all.prefill) : "–", u: "tok/s", k: "PREFILL AVG" },
    { v: all.ttft != null ? (all.ttft / 1000).toFixed(1) : "–", u: "s", k: "FIRST TOKEN" },
    { v: k(u.tokens), u: "", k: "SESSION" },
    { v: k(s.week), u: "", k: "WEEK" },
    { v: dur((Date.now() - Date.parse(d.startedAt)) / 1000), u: "", k: "UP" }] })
  v.rows.push({ type: "sec", label: "GPUS" })
  cards.forEach(function(g) { v.rows.push(gpuRow(g)) })
  v.rows.push({ type: "sec", label: "OPENS WITH" })
  pickers(s, v.rows, ui, d.agent, d.folder, id)
  weights(v.rows, d.weights)
  v.rows.push({ type: "sec", label: "REACH" })
  v.rows.push({ type: "field", label: "this machine", value: "127.0.0.1:" + d.port, plain: true })
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
      action: free ? "tick|" + key : "", status: kd.taken.indexOf(key) >= 0 ? "busy, another program" : g.busy ? "running a model" : "" })
  })
  var v = { back: true, title: kd.keys.length + " × " + kd.name.toUpperCase(), rows: [], hero: { name: pick.name,
    family: pick.family, gpus: gpus, caps: caps(pick.caps, 0),
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
