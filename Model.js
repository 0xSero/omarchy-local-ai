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
// how long ago a unix time was, in the fewest words: now, 12m ago, 10h ago, 3d ago
function ago(t) {
  var s = Date.now() / 1000 - (t || 0)
  return s < 300 ? "now" : s < 3600 ? Math.round(s / 60) + "m ago" : s < 86400 ? Math.floor(s / 3600) + "h ago" : Math.floor(s / 86400) + "d ago"
}
function home(dir) { return (dir || "").replace(/^\/home\/[^\/]+/, "~") }
function find(list, key, v) { return (list || []).filter(function(x) { return x[key] === v })[0] || null }
function working(d) { return d.state === "download" || d.state === "starting" || d.state === "stopping" }

function caps(c, n) {
  c = c || {}
  return [c.vision && "vision", c.tools && "tools", c.reasoning && "reasoning", n && ctx(n) + " context"].filter(Boolean)
}
// what a model can do, as the names of the More page's icons: only vision, the one that changes what it takes
function icons(c) { return c && c.vision ? ["vision"] : [] }
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

// home: running models as cards (ready, then starting or stopping), then the available GPUs as rows: free ones,
// then crashed ones to run again or dismiss. A GPU already running a model is not listed again; cards another
// program holds or with no model are one "all GPUs" away. A row has one quick action on the right; clicking it
// opens a line under it with the rest, including running one model across several free cards of its kind.
function homeView(s, ui) {
  if (!s.gpus) return { title: "LOCAL AI", rows: ui.problem ? [{ type: "error", label: ui.problem }] : [] }
  var rows = [], slots = [], models = []
  if (ui.problem) rows.push({ type: "error", label: ui.problem })
  function panel(d) {
    var all = (d.session || {}).all || {}
    var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 })
    // a card that does not report its memory in use (Intel) shows only how much it has
    var known = cards.every(function(g) { return g.usedMiB != null })
    var used = cards.reduce(function(a, g) { return a + (g.usedMiB || 0) / 1024 }, 0)
    var total = cards.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0)
    var r = { type: "run", name: d.name, family: d.family, line: all.line || [], more: "more|" + d.id,
      gpu: (cards.length > 1 ? cards.length + " × " : "") + (cards[0] ? cards[0].name : "GPU")
        + (total && !working(d) ? " · " + (known ? Math.round(used) + " / " : "") + total + " GB" : ""),
    }
    if (d.state === "ready") {
      r.stats = (all.decode ? all.decode + " tok/s · " : "") + k(all.tokens) + " tokens"
      r.sub = []
      r.primary = { label: "Open " + d.agent, action: "open|" + d.id }
    } else {
      r.progress = d.percent > 0 && d.state !== "stopping" ? d.percent : -1
      r.sub = [(d.detail || d.state) + (r.progress >= 0 && d.state !== "download" ? " · " + d.percent + "%" : "")]
      r.primary = { label: "Stop", action: "stop|" + d.id, quiet: true }
    }
    models.push({ rank: d.state === "ready" ? 0 : 1, at: models.length, row: r })
  }
  ;(s.deployments || []).filter(function(d) { return d.state !== "error" }).forEach(panel)
  // one row per GPU, free ones first; a row opens in place to the rest of what can be done with that card
  ;(s.gpus || []).forEach(function(g, at) {
    var kd = find(s.kinds || [], "hw", g.hw), d = (s.deployments || []).filter(function(x) { return x.keys.indexOf(g.key) >= 0 })[0]
    var row = { type: "slot", label: g.name, toggle: "pick|gpu:" + g.key }, more = { type: "links", items: [] }
    if (!kd) {
      row.rank = 4
      row.note = "no validated model yet"
      more.items = [{ label: "See supported cards ›", action: "url|https://github.com/0xSero/local-ai-registry/blob/main/supported/README.md" }]
    } else if (d && d.state === "error") {
      row.rank = 2
      row.crashed = true
      row.hint = "crashed"
      row.run = { label: "run again ›", action: "again|" + d.id + "|" + d.keys.join(",") }
      more.note = d.error || "stopped"
      more.items = [{ label: "Run again ›", action: row.run.action, primary: true }, { label: "Log", action: "log" }, { label: "Dismiss", action: "stop|" + d.id, danger: true }]
    } else if (d) {
      row.rank = 1
      row.note = (d.state === "ready" ? "running " : d.state === "stopping" ? "stopping " : "starting ") + d.name
      more.items = (d.state === "ready" ? [{ label: "Open " + d.agent + " ›", action: "open|" + d.id, primary: true }] : [])
        .concat([{ label: "More", action: "more|" + d.id }, { label: "Stop", action: "stop|" + d.id, danger: true }])
    } else if (kd.taken.indexOf(g.key) >= 0) {
      row.rank = 3
      row.warn = true
      row.note = "in use by another program"
      more.note = g.usedMiB != null ? Math.round(g.usedMiB / 1024) + " of " + g.vramGb + " GB held by another program" : "held by another program"
    } else {
      var r = kd.recipe
      row.rank = 0
      row.run = { family: r.family, label: "run " + r.name + " ›", action: "run|" + r.id + "|" + g.key }
      more.note = [r.format, r.ctx ? ctx(r.ctx) + " context" : "", r.sizeGb ? gb(r.sizeGb) : ""].filter(Boolean).join(" · ")
      more.items = [{ label: "Run ›", action: row.run.action, primary: true }]
      // a group: one model across this card and other free ones of its kind, when enough are free
      var others = kd.free.filter(function(x) { return x !== g.key }), sizes = {}
      ;(kd.groups || []).forEach(function(gr) {
        if (sizes[gr.cards] || others.length + 1 < gr.cards) return
        sizes[gr.cards] = 1
        more.items.push({ label: (gr.name !== r.name ? "Run " + gr.name + " on " : "Run on ") + gr.cards + " cards",
          action: "run|" + gr.id + "|" + [g.key].concat(others.slice(0, gr.cards - 1)).join(",") })
      })
      more.items.push({ label: "Agent & folder", action: "kind|" + kd.hw + "|" + g.key })
    }
    row.open = ui.open === "gpu:" + g.key
    if (row.rank === 0 || row.rank === 2) slots.push({ rank: row.rank, at: at, rows: row.open ? [row, more] : [row] })
  })
  if (!(s.kinds || []).length && !(s.deployments || []).length) return soonView(s)
  models.sort(function(a, b) { return a.rank - b.rank || a.at - b.at }).forEach(function(m) { rows.push(m.row) })
  slots.sort(function(a, b) { return a.rank - b.rank || a.at - b.at })
  if (slots.length) rows = rows.concat([{ type: "sec", label: "AVAILABLE" }], [].concat.apply([], slots.map(function(x) { return x.rows })))
  if ((s.gpus || []).length > slots.length) rows.push({ type: "field", label: "all GPUs", value: String((s.gpus || []).length), action: "gpus" })
  return { title: "LOCAL AI", version: s.version, stat: k(s.total), statLabel: "all time", rows: rows }
}

// every GPU on the machine: memory, temperature and what it is doing; a row opens what runs on it
function gpusView(s) {
  var rows = [{ type: "sec", label: "GPUS" }]
  ;(s.gpus || []).forEach(function(g) {
    var kd = find(s.kinds || [], "hw", g.hw), d = (s.deployments || []).filter(function(x) { return x.keys.indexOf(g.key) >= 0 })[0]
    var status = !kd ? "no validated model yet" : d ? (d.state === "error" ? "crashed" : "running " + d.name)
      : kd.taken.indexOf(g.key) >= 0 ? "in use by another program" : "free"
    rows.push(Object.assign(gpuRow(g), { status: status, action: d ? "more|" + d.id : kd && status === "free" ? "kind|" + kd.hw + "|" + g.key : "" }))
  })
  return { back: true, rows: rows }
}

// nothing to run on: one line on what this machine has, and where the list of supported cards lives
function soonView(s) {
  var found = (s.gpus || []).map(function(g) { return g.name }).filter(function(n, i, a) { return a.indexOf(n) === i })
  return { title: "LOCAL AI", version: s.version, rows: [{ type: "soon",
    head: found.length ? "No tested model for " + found.join(", ") + " yet" : "No supported GPU on this machine",
    action: "url|https://github.com/0xSero/local-ai-registry/blob/main/supported/README.md" }] }
}

// A model's page, the same for a running model and a free card kind: its name and what it is, its token line and
// figures when it runs, its cards (ticked to choose which a free one runs on), what Open uses, its weights, where it
// answers when it runs, and Run or Log and Stop.
function page(s, ui, m) {
  var run = m.d, u = run ? run.session || {} : {}, all = u.all || {}, line = all.line || [], top = line.length ? line[line.length - 1] : 0
  var v = { back: true, rows: [], hero: { name: m.name, family: m.family, icons: icons(m.caps),
    sub: [m.format, m.cards.length + " × " + (m.cards[0] ? m.cards[0].name : "GPU"), m.sizeGb && !run ? gb(m.sizeGb) : ""].filter(Boolean).join(" · "),
    caps: m.ctx ? ctx(m.ctx) + " context" : "" } }
  if (run) {
    Object.assign(v.hero, { line: line, top: k(top) + " tokens", mid: k(Math.round(top / 2)), since: all.since || "", now: all.last ? ago(all.last) : "now" })
    v.rows.push({ type: "grid", cells: [
      { v: all.decode != null ? String(all.decode) : "–", u: "tok/s", k: "decode avg" },
      { v: all.prefill != null ? k(all.prefill) : "–", u: "tok/s", k: "prefill avg" },
      { v: all.ttft != null ? (all.ttft / 1000).toFixed(1) : "–", u: "s", k: "first token" },
      { v: k(u.tokens), u: "", k: "session" },
      { v: k(s.week), u: "", k: "week" },
      { v: dur((Date.now() - Date.parse(run.startedAt)) / 1000), u: "", k: "up" }] })
  }
  v.rows.push({ type: "sec", label: "GPUS" })
  m.cards.forEach(function(g) { v.rows.push(g) })
  v.rows.push({ type: "sec", label: "OPENS WITH" })
  pickers(s, v.rows, ui, run ? run.agent : s.defaults.agent, run ? run.folder : s.defaults.folder, run ? run.id : "")
  weights(v.rows, m.weights)
  if (run) {
    v.rows.push({ type: "sec", label: "REACH" })
    v.rows.push({ type: "field", label: "this machine", value: "127.0.0.1:" + run.port })
    if (s.tailnet) v.rows.push(run.shared
      ? { type: "field", label: "tailnet", value: run.shared, secret: true, action: "copy|" + run.shared }
      : { type: "field", label: "tailnet", value: "share", action: "share|" + run.id })
    if (run.error) v.rows.push({ type: "error", label: run.error })
    v.rows.push({ type: "acts", items: [{ label: "Log", action: "log" }, { label: "Stop", action: "stop|" + run.id, danger: true }] })
  } else {
    v.rows.push({ type: "acts", items: [{ label: "Run ›", action: m.action, primary: true }] })
  }
  return v
}

function runView(s, id, ui) {
  var d = find(s.deployments, "id", id)
  if (!d) return null
  return page(s, ui, { d: d, name: d.name, family: d.family, format: d.format, caps: d.caps, ctx: d.ctx, weights: d.weights,
    cards: (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 }).map(gpuRow) })
}

// a free card kind: its card to run on, ticked (the one the row was opened from, else the first free one)
function kindView(s, hw, ui) {
  var kd = find(s.kinds, "hw", hw), pick = kd && kd.recipe
  if (!pick) return null
  var chosen = kd.free.indexOf(ui.key) >= 0 ? ui.key : kd.free[0]
  return page(s, ui, { name: pick.name, family: pick.family, format: pick.format, caps: pick.caps, ctx: pick.ctx, sizeGb: pick.sizeGb,
    weights: pick.weights, action: chosen ? "run|" + pick.id + "|" + chosen : "",
    cards: kd.keys.map(function(key) {
      var g = find(s.gpus, "key", key), free = kd.free.indexOf(key) >= 0
      return Object.assign(gpuRow(g), { check: kd.keys.length > 1 ? key === chosen : undefined, disabled: !free,
        action: free ? "tick|" + key : "", status: kd.taken.indexOf(key) >= 0 ? "in use by another program" : g.busy ? "running a model" : "" })
    }) })
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
  var v = (ui.view === "run" ? runView(s, ui.id, ui) : ui.view === "kind" ? kindView(s, ui.id, ui) : ui.view === "gpus" ? gpusView(s) : null) || homeView(s, ui)
  return Object.assign(v, { mark: mark(s) })
}

if (typeof module !== "undefined") module.exports = { build: build, parse: parse, apca: apca, reach: reach, tones: tones, over: over, LC: LC }
