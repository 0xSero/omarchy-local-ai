// What the Local AI widget shows, as data: the backend's snapshot and the widget's ui state in, a view out.
// Panel.qml draws the view and turns its actions ("verb|arg|arg") into backend verbs. No Qt, no side effects.

// rounded before the unit is picked, so 999,950 is 1M, not 1000K, and a few MB are <0.1 GB, not 0 GB
function k(n) {
  n = n || 0
  var t = Math.round(n / 100) / 10
  return t >= 1000 ? Math.round(n / 1e5) / 10 + "M" : n >= 1e3 ? t + "K" : String(n)
}
function gb(n) { return (n >= 9.95 ? Math.round(n) : n > 0 && n < 0.05 ? "<0.1" : Math.round(n * 10) / 10) + " GB" }
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
// a recipe this machine can run: one whose `needs` (RAM, disk, an NVMe drive) the backend found met; the best of a
// list is the first of those, the registry's order otherwise kept
function fits(r) { return !r.unfit }
function best(list) { return (list || []).filter(fits)[0] || null }
// downloading, starting, stopping, or a state this panel does not know yet: not settled either way
function working(d) { return d.state !== "ready" && d.state !== "error" }
// Stop, but nothing while it is already stopping
function stop(d) { return d.state === "stopping" ? "" : "stop|" + d.id }

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

// a recipe's facts as chips (an icon name and a short text): its format, context, download size and the RAM it
// takes besides the card; a format's detail in parentheses is left to the registry
function fmt(f) { return (f || "").replace(/ · /g, " ").replace(/ \(.*\)$/, "") }
function ram(r) { return r.needs && r.needs.host_ram_gb ? Math.ceil(r.needs.host_ram_gb) + " GB RAM" : "" }
function spec(r) {
  return [r.format ? { text: fmt(r.format) } : null, r.ctx ? { icon: "context", text: ctx(r.ctx) } : null, r.sizeGb ? { icon: "weights", text: gb(r.sizeGb) } : null,
    ram(r) ? { icon: "memory", text: ram(r) } : null].filter(Boolean)
}
var SUPPORTED = "url|https://local.sybilsolutions.ai/hardware/"

// A model that stopped by itself: its row, framed, with run again (while its cards are still here) and dismiss, its
// reason under it, and, opened, its log and its page. Dismissing clears the failed mark it raises.
function stopped(s, ui) {
  return [].concat.apply([], (s.deployments || []).filter(function(d) { return d.state === "error" }).map(function(d) {
    var here = d.keys.every(function(k) { return find(s.gpus || [], "key", k) })
    var row = { type: "slot", label: d.name, toggle: "pick|lost:" + d.id, open: ui.open === "lost:" + d.id, crashed: true, hint: "stopped",
      run: here ? { label: "run again ›", action: "again|" + d.id + "|" + d.keys.join(",") } : null, dismiss: "stop|" + d.id }
    var rows = [row, { type: "error", label: d.error || "stopped" }]
    if (row.open) rows.push({ type: "links", note: "", items: [{ label: "View logs", action: "log" }, { label: "Details ›", action: "more|" + d.id }] })
    return rows
  }))
}

// What the panel says and offers for each readiness state the backend reports (lib/access.sh). A state with no button
// clears by itself and says so; a state this table has never heard of does the same, so none is a dead end.
var READINESS = {
  "needs-setup": { note: "Once per machine: Docker access for your account (Omarchy's Sudoless Docker) and, on NVIDIA, the container toolkit. A terminal opens; Omarchy asks for your password.",
    action: "setup" },
  "docker-down": { note: "Docker is not ready. Local AI checks again by itself." },
  unsupported: { note: "This Omarchy is too old for Local AI. It checks again by itself once Omarchy is updated." }
}
function notReadyView(s, ui) {
  var r = s.readiness, t = READINESS[r.state] || { note: "Local AI is not ready. It checks again by itself." }
  var rows = [activity(s, ui), { type: "sec", label: "SETUP" }, { type: "links", note: t.note, items: [] }]
  if (r.message) rows.push({ type: "links", note: r.message, items: [] })
  if (t.action) rows.push({ type: "acts", items: [{ label: "Set up Local AI", action: t.action, primary: true }] })
  return { title: "LOCAL AI", version: s.version, rows: rows }
}

// home: your lifetime (once there is one), running models as cards (ready, then starting or stopping), then the
// available GPUs as rows: free ones, then groups of free cards, then crashed ones to run again or dismiss (a crash on
// a card no row shows is a row of its own). A GPU already running a model is not listed again; the rest are one
// "all GPUs" away.
function homeView(s, ui) {
  if (!s.gpus) return { title: "LOCAL AI", rows: [] }
  if (((s.readiness || {}).state || "ready") !== "ready") {
    // setup first, but a model that is already running stays reachable to open, stop or dismiss
    var nr = notReadyView(s, ui)
    ;(s.deployments || []).forEach(function(d) { nr.rows.push(card(s, d)) })
    return nr
  }
  if (!(s.kinds || []).length && !(s.deployments || []).length) return soonView(s, ui)
  if (ui.view === "models") return { title: "LOCAL AI", version: s.version, rows: [tabs(ui)].concat(modelsTab(s, ui)) }
  var rows = [tabs(ui), activity(s, ui)]
  ;(s.deployments || []).filter(function(d) { return d.state === "ready" })
    .concat((s.deployments || []).filter(function(d) { return working(d) })).forEach(function(d) { rows.push(card(s, d)) })
  // a model that stopped, to run again or dismiss
  rows = rows.concat(stopped(s, ui))
  rows = rows.concat(pinned(s, ui))
  rows.push({ type: "sec", label: "THIS MACHINE" })
  rows.push({ type: "field", icon: "gpu", label: "hardware", value: String(s.gpus.length), action: "gpus" })
  if (s.host && s.host.ramGb) rows.push({ type: "field", icon: "memory", label: "RAM", value: Math.floor(s.host.freeRamGb) + " / " + Math.floor(s.host.ramGb) + " GB free" })
  rows.push({ type: "field", icon: "agent", label: "Agents", value: String((s.agents || []).length), action: "agents" })
  // a stale NVIDIA device list (a card taken out, a driver update) stops starts on NVIDIA cards: setup rewrites it
  if (s.cdi && s.gpus.some(function(g) { return g.backend === "nvidia" }))
    rows.push({ type: "banner", alert: true, text: "NVIDIA device list is out of date (" + s.cdi.why + ")", action: "setup", actionLabel: "Fix" })
  return { title: "LOCAL AI", version: s.version, rows: rows }
}

// Two tabs: home (your activity, what runs, your pinned models) and models (every model, to find, download, pin)
function tabs(ui) {
  return { type: "tabs", items: [{ label: "home", on: ui.view !== "models", action: "home" }, { label: "models", on: ui.view === "models", action: "models" }] }
}

// a card's name short enough for a table cell: RTX 3090, B70, CPU
function short(name) {
  return /cpu/i.test(name) ? "CPU" : (name || "").replace(/^(NVIDIA |GeForce |Intel |AMD |Arc Pro |Arc |Radeon Pro |Radeon )+/, "")
}
// a format short enough for a table cell: EXL3 3 bpw
function brief(f) { return fmt(f).split(",")[0] }

// Every model this machine can run, whatever card it lands on: one entry per recipe of each kind of hardware here,
// on one card or across a group of them (when the machine has that many). Each says where it runs, whether it runs
// now, whether it fits the machine (RAM, disk, NVMe), whether its cards are free, and whether it is pinned.
function catalog(s) {
  var out = [], pins = s.pins || []
  // two recipes that would read the same (a model, its format, its card) are told apart by what differs: the
  // detail their format carries, e.g. "55 GB RAM" against "experts in RAM"
  ;(s.kinds || []).forEach(function(kd, at) {
    var g = find(s.gpus || [], "key", kd.keys[0]), hw = g ? g.name : kd.hw
    var rec = {}, first = best(kd.models)
    if (first) rec[first.id] = 1
    ;(kd.groups || []).forEach(function(gr) { if (fits(gr) && kd.keys.length >= gr.cards && !rec["n" + gr.cards]) rec["n" + gr.cards] = rec[gr.id] = 1 })
    kd.models.concat(kd.groups || []).forEach(function(r, i) {
      var n = r.cards || 1, short_ = kd.keys.length < n
      var d = (s.deployments || []).filter(function(x) { return x.id === r.id || x.id.indexOf(r.id + "--") === 0 })[0]
      // a setup across more cards than the machine has is listed as too big, saying how many it takes
      out.push({ id: r.id, name: r.name, family: r.family, format: r.format, engine: r.engine || "", ctx: r.ctx, size: r.sizeGb, needs: r.needs || {}, hw: hw, n: n, d: d || null,
        fits: fits(r) && !short_, unfit: short_ ? "needs " + n + " × " + hw + ", this machine has " + kd.keys.length : r.unfit || "",
        downloaded: !!r.downloaded, dl: find(s.downloads || [], "id", r.id), reported: !!r.reported, aa: r.aa != null ? r.aa : null,
        free: kd.free.length >= n, pin: pins.indexOf(r.id), rec: !!rec[r.id], at: at * 1000 + i,
        on: (n > 1 ? n + "× " : "") + short(hw),
        run: kd.free.length >= n && !short_ ? "run|" + r.id + "|" + kd.free.slice(0, n).join(",") : "",
        action: d ? "more|" + d.id : short_ ? "" : n > 1 ? "group|" + kd.hw + "|" + n + "|" + r.id : "kind|" + kd.hw + "|" + (kd.free[0] || kd.keys[0]) + "|" + r.id })
    })
  })
  out.forEach(function(c) {
    var twin = out.some(function(o) { return o !== c && o.name === c.name && o.on === c.on && brief(o.format) === brief(c.format) })
    var detail = ((c.format || "").match(/\(([^,)]+)/) || [])[1]
    if (twin) c.variant = detail || (c.needs.host_ram_gb ? Math.ceil(c.needs.host_ram_gb) + " GB RAM" : brief(c.format))
  })
  return out
}
function matches(c, q) {
  var hay = [c.name, c.family, brief(c.format), c.on, c.hw].join(" ").toLowerCase()
  return q.split(/\s+/).every(function(w) { return hay.indexOf(w) >= 0 })
}
// one model as a table row: a dot when it runs, its name, format and hardware; dim when it cannot start now. Full
// screen adds its engine, context, download and the RAM and NVMe it needs besides its cards.
function trow(c, wide) {
  // the Artificial Analysis index, whole: a rank to compare, not a measurement to read
  var aa = c.aa != null ? String(Math.round(c.aa)) : "–"
  var cells = [c.name, aa, c.variant || brief(c.format), c.on]
  if (wide) cells = [c.name, aa, c.variant || brief(c.format), c.engine || "–", c.on, c.ctx ? ctx(c.ctx) : "–", c.size ? gb(c.size) : "–",
    c.needs.host_ram_gb ? Math.ceil(c.needs.host_ram_gb) + " GB" : "–", c.needs.fast_storage === "nvme" ? "yes" : "–"]
  // the mark before the name: running, downloading, downloaded
  var mark = c.d ? "●" : c.dl && c.dl.state === "download" ? "↓" : ""
  return { type: "trow", family: c.family || "", live: !!c.d, mark: mark, dim: !c.d && (!c.fits || !c.free), cells: cells, action: c.action }
}
// a table of models; on the models tab each row opens in place to manage it
function table(list, wide, ui) {
  var rows = [{ type: "thead", cells: wide ? ["MODEL", "AA", "FORMAT", "ENGINE", "ON", "CONTEXT", "DOWNLOAD", "RAM", "NVMe"] : ["MODEL", "AA", "FORMAT", "ON"] }]
  list.forEach(function(c) {
    var r = trow(c, wide)
    if (ui) {
      r.action = "pick|m:" + c.id
      r.open = ui.open === "m:" + c.id
      r.drop = true
    } else r.go = !!r.action
    rows.push(r)
    if (r.open) rows.push(manage(c))
  })
  return rows
}
// what a model is doing, in one line
function state(c) {
  if (c.d) return c.d.state === "ready" ? "running on " + c.on : c.d.state === "error" ? "stopped: " + (c.d.error || "the engine stopped") : (c.d.detail || c.d.state)
  if (c.dl) return c.dl.state === "error" ? "download failed: " + (c.dl.error || "try again") : "downloading · " + (c.dl.detail || "") + (c.dl.percent > 0 ? " · " + c.dl.percent + "%" : "")
  if (!c.fits) return c.unfit
  return (c.downloaded ? "downloaded" : "not downloaded · " + (c.size ? gb(c.size) : "")) + (c.free ? "" : " · its card is in use")
    + (c.reported ? " · reported by its publisher, not yet run by the lab" : "")
}
// a model's row opened on the models tab: its state, then Start or Open and Stop, Download, Cancel or Remove, Pin
function manage(c) {
  var items = []
  if (c.d && c.d.state === "ready") items.push({ label: "Open ›", action: "open|" + c.d.id, primary: true }, { label: "Stop", action: stop(c.d), danger: true })
  else if (c.d) items.push({ label: "Stop", action: stop(c.d), danger: true })
  else if (c.fits && c.free && c.run) items.push({ label: "Start ›", action: c.run, primary: true })
  if (!c.d) {
    if (c.dl && c.dl.state === "download") items.push({ label: "Cancel download", action: "download|" + c.id + "|off" })
    else if (c.downloaded) items.push({ label: "Remove download", action: "forget|" + c.id, danger: true })
    else if (c.fits) items.push({ label: c.dl ? "Download again" : "Download", action: "download|" + c.id })
  }
  // a model on this machine is on home already; one that is not can be pinned there to try later
  if (!c.d && !c.dl && !c.downloaded) items.push({ label: c.pin >= 0 ? "Unpin" : "Pin to home", action: "pin|" + c.id + (c.pin >= 0 ? "|off" : "") })
  items.push({ label: "Details ›", action: c.action })
  return { type: "links", note: state(c), items: items.filter(function(x) { return x.action !== undefined }) }
}
// home's models: the ones you pinned (running or downloading one pins it), else the recommended ones
function pinned(s, ui) {
  // your models: what is on this machine (running, downloading, downloaded), then those you pinned to try; until
  // there are any, the recommended ones
  var all = catalog(s), here = function(c) { return c.d || c.dl || c.downloaded }
  var mine = all.filter(here).sort(function(a, b) { return (!!b.d - !!a.d) || ((b.aa || 0) - (a.aa || 0)) || a.at - b.at })
    .concat(all.filter(function(c) { return !here(c) && c.pin >= 0 }).sort(function(a, b) { return a.pin - b.pin }))
  var top = mine.length ? mine : all.filter(function(c) { return c.rec && c.fits })
  return [{ type: "sec", label: mine.length ? "YOUR MODELS" : "RECOMMENDED" }].concat(top.length ? table(top, ui.wide)
    : [{ type: "links", note: "Nothing fits this machine yet; the models tab says what each one needs.", items: [{ label: "Models ›", action: "models" }] }])
}
// the models tab: a search line (type anywhere), then the matches, or what you have downloaded, every other model
// that fits, and those this machine is too small for; each row opens in place to start, download, remove or pin it
function modelsTab(s, ui) {
  var all = catalog(s), q = (ui.query || "").trim().toLowerCase(), ok = all.filter(function(c) { return c.fits })
  var rows = [{ type: "search", query: ui.query || "", hint: "type to search " + all.length + (all.length === 1 ? " model" : " models") }]
  if (q) {
    var hit = all.filter(function(c) { return matches(c, q) }).sort(function(a, b) { return (b.fits - a.fits) || a.at - b.at })
    rows.push({ type: "sec", label: "MATCHES" })
    return rows.concat(hit.length ? table(hit, ui.wide, ui) : [{ type: "links", note: "No model here matches \u201c" + ui.query.trim() + "\u201d. New ones arrive by themselves.", items: [] }])
  }
  // the smartest first, by the Artificial Analysis Intelligence Index; models AA does not list after, in registry order
  var byAA = function(a, b) { return ((b.aa != null) - (a.aa != null)) || (b.aa || 0) - (a.aa || 0) || a.at - b.at }
  var have = all.filter(function(c) { return c.d || c.dl || c.downloaded }).sort(byAA), rest = ok.filter(function(c) { return have.indexOf(c) < 0 }).sort(byAA)
  var big = all.filter(function(c) { return !c.fits && have.indexOf(c) < 0 })
  if (have.length) rows = rows.concat([{ type: "sec", label: "ON THIS MACHINE" }], table(have, ui.wide, ui))
  if (rest.length) rows = rows.concat([{ type: "sec", label: have.length ? "MORE THAT FIT" : "FITS THIS MACHINE" }], table(rest, ui.wide, ui))
  if (big.length) {
    rows.push({ type: "field", label: "too big for this machine", value: String(big.length), drop: true, open: ui.big, action: "big" })
    if (ui.big) rows = rows.concat(table(big, ui.wide, ui))
  }
  if (s.catalog && s.catalog.commit) rows.push({ type: "banner", text: "models from the registry at " + s.catalog.commit.slice(0, 8) + (s.catalog.at ? " · checked " + ago(Date.parse(s.catalog.at) / 1000) : "") })
  return rows
}

// Your lifetime as an activity grid: a column a week, a row a weekday, each day shaded in four steps by its tokens
// against your busiest day (days still to come are blank), the months under their first week, the totals above.
// Every home screen has it, empty before the first request: at least WEEKS weeks, ending this week.
var WEEKS = 20
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
function activity(s, ui) {
  var life = s.life || {}, days = (life.days || []).slice(0, Math.max(0, (life.today || 0) + 1)), months = [], last = -1, first
  if (life.start && days.length) first = new Date(life.start * 1000)
  else {
    // nothing used yet: this week, Sunday to today
    var now = new Date()
    first = new Date(now.getFullYear(), now.getMonth(), now.getDate() - now.getDay())
    days = []
    for (var i = 0; i <= now.getDay(); i++) days.push(0)
  }
  // fewer weeks than the grid holds: empty weeks before the first
  // full screen has room for a year
  var pad = Math.max(0, ((ui || {}).wide ? 53 : WEEKS) - Math.ceil(days.length / 7)) * 7
  first.setDate(first.getDate() - pad)
  for (var p = 0; p < pad; p++) days.unshift(0)
  var top = Math.max.apply(null, days.concat([1]))
  // a week on the calendar, not 7 × 86400 s: the week a daylight-saving change ends is an hour longer
  for (var c = 0; c * 7 < days.length; c++) {
    var w = new Date(first.getTime())
    w.setDate(w.getDate() + c * 7)
    var m = w.getMonth()
    if (m !== last) months.push({ col: c, label: MONTHS[m] })
    last = m
  }
  // the first, partial month keeps its name unless the next one would crowd it
  if (months.length > 1 && months[1].col < 3) months.shift()
  return { type: "life", tokens: k(s.total) + " tokens", requests: k(life.requests) + (life.requests === 1 ? " request" : " requests"),
    since: life.since && life.requests > 0 ? "since " + life.since : "nothing run yet", months: months,
    cells: days.map(function(v, i) { return v > 0 ? Math.ceil(v / top * 4) : 0 }),
    // what a hovered day says: its date and its tokens
    labels: days.map(function(v, i) {
      var d = new Date(first.getTime())
      d.setDate(d.getDate() + i)
      return DAYS[d.getDay()] + " " + MONTHS[d.getMonth()] + " " + d.getDate() + "  " + (v > 0 ? k(v) + " tokens" : "no tokens")
    }) }
}

// A running model's card: its all-time token line, its name and cards, and Open, More and Stop (Stop and More while
// it starts)
function card(s, d) {
  var all = (d.session || {}).all || {}
  var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 })
  // a card that does not report its memory in use (Intel) shows only how much it has
  var known = cards.every(function(g) { return g.usedMiB != null })
  var used = cards.reduce(function(a, g) { return a + (g.usedMiB || 0) / 1024 }, 0)
  var total = cards.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0)
  var r = { type: "run", name: d.name, family: d.family, line: all.line || [], more: "more|" + d.id,
    gpu: (cards.length > 1 ? cards.length + " × " : "") + (cards[0] ? cards[0].name : "GPU"),
    mem: total && !working(d) ? (known ? Math.round(used) + " / " : "") + total + " GB" : "" }
  if (d.state === "ready") {
    r.chips = [all.decode ? { icon: "speed", text: all.decode + " tok/s" } : null, { icon: "tokens", text: k(all.tokens) }].filter(Boolean)
    r.primary = { label: "Open " + d.agent, action: "open|" + d.id }
    r.stop = stop(d)
  } else {
    r.progress = d.percent > 0 && d.state !== "stopping" ? d.percent : -1
    r.sub = (d.detail || d.state) + (r.progress >= 0 && d.state !== "download" ? " · " + d.percent + "%" : "")
    r.primary = { label: "Stop model", action: stop(d), quiet: true }
  }
  return r
}

// The hardware: the machine in figures first (cards, their memory, what runs, RAM, CPU threads, disk), then every
// card with its maker, memory in use, temperature and what is on it; a running one opens its model, a free one the
// models for it; then the CPU and the crashed models to run again or dismiss
function gpusView(s, ui) {
  var cards = (s.gpus || []).filter(function(g) { return g.backend !== "cpu" }), h = s.host || {}
  var vram = cards.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0)
  var known = cards.filter(function(g) { return g.usedMiB != null })
  var used = known.reduce(function(a, g) { return a + g.usedMiB / 1024 }, 0)
  var rows = [{ type: "sec", label: "THIS MACHINE" }, { type: "grid", cells: [
    { v: String(cards.length), u: "", k: cards.length === 1 ? "GPU" : "GPUs" },
    // in use only where the card says (Intel's do not)
    { v: known.length ? Math.round(used) + "/" + vram : String(vram), u: "GB", k: known.length ? "VRAM used" : "VRAM" },
    { v: String((s.deployments || []).filter(function(d) { return d.state === "ready" }).length), u: "", k: "running" },
    { v: h.ramGb ? Math.floor(h.freeRamGb) + "/" + Math.floor(h.ramGb) : "–", u: "GB", k: "RAM free" },
    { v: h.cpus ? String(h.cpus) : "–", u: "", k: "CPU threads" },
    { v: h.diskFreeGb != null ? String(Math.floor(h.diskFreeGb)) : "–", u: "GB", k: h.disk === "nvme" ? "NVMe free" : "disk free" }] }]
  if (cards.length) rows.push({ type: "sec", label: cards.length === 1 ? "GPU" : "GPUS" })
  // a card is one line (maker, name, temperature, what it is doing); opened, its memory and where it leads
  cards.forEach(function(g) {
    var d = (s.deployments || []).filter(function(x) { return x.keys.indexOf(g.key) >= 0 })[0], kd = find(s.kinds || [], "hw", g.hw)
    var held = !d && ((kd && kd.taken.indexOf(g.key) >= 0) || g.held)
    var status = d ? (d.state === "ready" ? "running " : d.state === "error" ? "stopped: " : d.state + " ") + d.name
      : held ? "in use by another program" : kd ? "free" : "no tested model yet"
    var open = ui.open === "hw:" + g.key || ui.wide
    rows.push({ type: "field", logo: vendor(g), label: g.name, value: (g.tempC != null ? g.tempC + "°  " : "") + (d ? (d.state === "ready" ? "running" : d.state) : held ? "in use" : kd ? "free" : "–"),
      warn: held, drop: !ui.wide, open: open, action: ui.wide ? "" : "pick|hw:" + g.key })
    if (open) {
      var mem = gpuRow(g)
      mem.status = status
      rows.push(mem)
      rows.push({ type: "links", items: [d ? { label: "Open " + d.name + " ›", action: "more|" + d.id } : kd ? { label: "Models for it ›", action: "find|" + short(g.name) } : { label: "Supported hardware ›", action: SUPPORTED }] })
    }
  })
  var cpu = (s.gpus || []).filter(function(g) { return g.backend === "cpu" })[0]
  if (cpu) {
    rows.push({ type: "sec", label: "CPU" })
    // its maker's name without the marketing tail (24-Core Processor, (R), (TM), @ 3.2GHz)
    var cpuName = (h.cpuName || cpu.name).replace(/\((R|TM)\)/g, "").replace(/\s+(\d+-Core Processor|CPU\b.*|@.*)$/i, "").replace(/\s+/g, " ").trim()
    rows.push({ type: "field", icon: "machine", label: cpuName, value: (h.cpus ? h.cpus + " threads · " : "") + cpu.ramGb + " GB" })
  }
  var crashed = stopped(s, ui)
  if (crashed.length) rows = rows.concat([{ type: "sec", label: "STOPPED" }], crashed)
  return { back: true, where: "hardware", rows: rows }
}

// nothing to run on yet: the same home, its grid and this machine's hardware, each saying it has no tested model,
// what Local AI runs, and where the list of supported hardware lives
function soonView(s, ui) {
  var names = (s.gpus || []).map(function(g) { return g.name }), rows = [activity(s, ui), { type: "sec", label: "HARDWARE" }]
  names.filter(function(n, i) { return names.indexOf(n) === i }).forEach(function(n) {
    var c = names.filter(function(x) { return x === n }).length
    rows.push({ type: "field", icon: "gpu", label: (c > 1 ? c + " × " : "") + n, value: "no tested model yet" })
  })
  if (!names.length) rows.push({ type: "field", icon: "gpu", label: "no supported GPU found", value: "" })
  if (s.host && s.host.ramGb) rows.push({ type: "field", icon: "memory", label: "RAM", value: Math.floor(s.host.freeRamGb) + " / " + Math.floor(s.host.ramGb) + " GB free" })
  rows.push({ type: "links", note: "Local AI runs only models tested on your hardware. New ones arrive by themselves as they are tested.", items: [] })
  rows.push({ type: "acts", items: [{ label: "Supported hardware ›", action: SUPPORTED }] })
  return { title: "LOCAL AI", version: s.version, rows: rows }
}

// A model's page, the same for a running model, a free card and a group: m is the running model (d) or the chosen
// recipe, with its cards, the models to choose from and what Run does. Its name and what it is, its token line and
// figures when it runs, its cards, what Open uses, its weights, where it answers when it runs, and Run or Log and Stop.
function page(s, ui, m) {
  var run = m.d, failed = run && run.state === "error", u = run ? run.session || {} : {}, all = u.all || {}, line = all.line || [], top = line.length ? line[line.length - 1] : 0
  var facts = spec(run ? Object.assign({}, m, { sizeGb: 0 }) : m)
  facts.splice(m.format ? 1 : 0, 0, { icon: "gpu", text: m.cards.length + " × " + (m.cards[0] ? m.cards[0].name : "GPU") })
  if ((m.caps || {}).vision) facts.push({ icon: "vision", text: "" })
  var v = { back: true, where: m.name, whereFamily: m.family, rows: [], hero: { name: "", family: "", chips: facts } }
  if (run && !failed) Object.assign(v.hero, { line: line, top: k(top) + " tokens", mid: k(Math.round(top / 2)), since: all.since || "", now: all.last ? ago(all.last) : "now" })
  // one line: what it is doing, or why it cannot start
  var dl = find(s.downloads || [], "id", run ? base(run.id) : m.id), held = (m.cards[0] || {}).status
  var said = failed ? run.error || "the engine stopped"
    : run ? (run.state === "ready" ? "running" + (all.decode != null ? " · " + all.decode + " tok/s" : "")
      : (run.detail || run.state) + (run.percent > 0 && run.state !== "stopping" ? " · " + run.percent + "%" : ""))
    : m.unfit ? m.unfit
    : !m.action ? (held ? "its " + m.cards[0].name + " is " + held : "its cards are in use")
    : dl && dl.state === "download" ? "downloading · " + (dl.detail || "") + (dl.percent > 0 ? " · " + dl.percent + "%" : "")
    : (m.downloaded ? "downloaded · ready to start" : "starts with a " + gb(m.sizeGb || 0) + " download") + (m.reported ? " · reported, not yet run by the lab" : "")
  v.rows.push(failed || m.unfit ? { type: "error", label: said } : { type: "links", note: said, items: [] })
  // one action, two when it runs: Open and Stop; none for a model this machine cannot run
  if (!m.unfit || run) v.rows.push({ type: "acts", items: failed ? [{ label: "Run again ›", action: "again|" + run.id + "|" + run.keys.join(","), primary: true }, { label: "Dismiss", action: "stop|" + run.id, danger: true }]
    : run && run.state === "ready" ? [{ label: "Open " + agentName(run.agent) + " ›", action: "open|" + run.id, primary: true }, { label: "Stop", action: stop(run), danger: true }]
    : run ? [{ label: "Stop", action: stop(run), danger: true }]
    : [{ label: "Start ›", action: m.action || "", primary: true }] })
  // full screen has room for its model card, from Hugging Face at the pinned revision
  v.cardFor = run ? base(run.id) : m.id
  if (ui.wide) {
    var text = (ui.cards || {})[v.cardFor]
    v.rows.push({ type: "sec", label: "MODEL CARD" })
    v.rows.push(text ? { type: "card", text: cardText(text) } : { type: "links", note: text === "" ? "no model card on Hugging Face" : "fetching the model card…", items: [] })
  }
  // the rest, one tap away: figures, what it needs, its cards, which agent and folder, its weights, where it answers
  // full screen opens with them shown
  if (!ui.wide) v.rows.push({ type: "field", label: "details", value: "", drop: true, open: !!ui.details, action: "details" })
  if (!ui.details && !ui.wide) return v
  if (run && !failed) v.rows.push({ type: "grid", cells: [
    { v: all.decode != null ? String(all.decode) : "–", u: "tok/s", k: "decode avg" },
    { v: all.prefill != null ? k(all.prefill) : "–", u: "tok/s", k: "prefill avg" },
    { v: all.ttft != null ? (all.ttft / 1000).toFixed(1) : "–", u: "s", k: "first token" },
    { v: k(u.tokens), u: "", k: "session" },
    { v: k(u.week), u: "", k: "week" },
    { v: isNaN(Date.parse(run.startedAt)) ? "–" : dur((Date.now() - Date.parse(run.startedAt)) / 1000), u: "", k: "up" }] })
  needsTable(v.rows, m)
  v.rows.push({ type: "sec", label: m.cards.some(function(g) { return g.cpu }) ? "CPU" : "GPUS" })
  m.cards.forEach(function(g) { v.rows.push(g) })
  v.rows.push({ type: "sec", label: "OPENS WITH" })
  pickers(s, v.rows, ui, run ? run.agent : (s.defaults || {}).agent, run ? run.folder : (s.defaults || {}).folder, run ? run.id : "")
  weights(v.rows, m.weights)
  if (run && !failed) {
    v.rows.push({ type: "sec", label: "REACH" })
    // addresses stay hidden until clicked, beside a copy
    v.rows.push({ type: "field", icon: "machine", label: "this machine", value: "http://127.0.0.1:" + run.port, secret: true, action: "copy|http://127.0.0.1:" + run.port })
    if (s.tailnet) v.rows.push(run.shared
      ? { type: "field", icon: "tailnet", label: "tailnet", value: run.shared, secret: true, action: "copy|" + run.shared }
      : { type: "field", icon: "tailnet", label: "tailnet", value: "share", action: "share|" + run.id })
    if (run.shared) v.rows.push({ type: "links", items: [{ label: "Stop sharing", action: "share|" + run.id + "|off" }] })
  }
  v.rows.push({ type: "links", items: [{ label: "View logs", action: "log" }] })
  return v
}

// A model card as the panel draws it: its markdown without the front matter, styles, HTML or images (nothing is loaded
// from the network to draw it), tables as rows of cells, and at most 40,000 characters
function cardText(md) {
  return md.replace(/^---\n[\s\S]*?\n---\n/, "").replace(/<(style|script)[\s\S]*?<\/\1>/gi, "").replace(/<!--[\s\S]*?-->/g, "")
    // an HTML table's cells apart, a row a paragraph; a lone rule of dashes left behind is no heading
    .replace(/<\/t[dh]>/gi, "  ·  ").replace(/<\/tr>/gi, "\n\n").replace(/^\s*[-=]{2,}\s*$/gm, "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "").replace(/<[^>]+>/g, "")
    // every other image form (reference ![a][r], collapsed ![a][], shortcut ![a], nested brackets) becomes a plain
    // link: Text.MarkdownText fetches an image's URL to draw it, but a link loads nothing until it is clicked
    .replace(/!\[/g, "[")
    .replace(/\n{3,}/g, "\n\n").trim().slice(0, 40000)
}

// a second copy of a recipe runs as <recipe>--2
function base(id) { return id.indexOf("--") >= 0 ? id.slice(0, id.lastIndexOf("--")) : id }
// what a model takes of the machine, as a table: its format and engine, the cards it fills, system RAM besides them,
// disk for its weights, whether they must sit on NVMe, and its context
function needsTable(rows, m) {
  var n = m.needs || {}, cards = m.cards || [], g = cards[0] || {}
  rows.push({ type: "thead", cells: ["NEEDS", ""], pair: true })
  ;[["format", fmt(m.format) || "–"], ["engine", m.engine || "–"],
    [g.cpu ? "CPU" : "GPU", cards.length ? (cards.length > 1 ? cards.length + " × " : "") + g.name + (g.cpu ? "" : " · " + (g.mem || "").replace(/^.* \/ /, "")) : "–"],
    ["RAM", n.host_ram_gb ? Math.ceil(n.host_ram_gb) + " GB" : "–"], ["disk", gb(n.disk_gb || m.sizeGb || 0)],
    ["NVMe", n.fast_storage === "nvme" ? "required" : "no"], ["context", m.ctx ? ctx(m.ctx) + " tokens" : "–"]].forEach(function(x) {
    rows.push({ type: "trow", pair: true, cells: [x[0], x[1]] })
  })
}

function runView(s, id, ui) {
  var d = find(s.deployments, "id", id)
  if (!d) return null
  return page(s, ui, Object.assign({ d: d }, d, { cards: (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 }).map(gpuRow) }))
}

// a card kind's page, for the card its row was opened from (else the first free one): the models validated for it,
// the recommended one chosen until another is, and Run when that card is free; a card another program holds says why
function kindView(s, hw, ui) {
  var kd = find(s.kinds, "hw", hw), models = kd ? kd.models : [], pick = find(models, "id", ui.model) || best(models) || models[0]
  if (!pick) return null
  var key = kd.keys.indexOf(ui.key) >= 0 ? ui.key : kd.free[0], free = kd.free.indexOf(key) >= 0, g = key && find(s.gpus, "key", key)
  return page(s, ui, Object.assign({}, pick, { models: models, action: free ? "run|" + pick.id + "|" + key : "",
    cards: g ? [Object.assign(gpuRow(g), { status: kd.taken.indexOf(key) >= 0 ? "in use by another program" : g.busy ? "running a model" : "" })] : [] }))
}

// a group of free cards of a kind: the models validated for that many cards, on the cards it would run on
function groupView(s, hw, n, ui) {
  var kd = find(s.kinds, "hw", hw), models = kd ? (kd.groups || []).filter(function(x) { return x.cards === n }) : []
  var gr = find(models, "id", ui.model) || best(models) || models[0]
  if (!gr || kd.keys.length < n) return null
  // its cards: free ones to run on, else the first of the kind, with nothing to run until enough are free
  var free = kd.free.length >= n, keys = (free ? kd.free : kd.keys).slice(0, n)
  return page(s, ui, Object.assign({}, gr, { models: models, action: free ? "run|" + gr.id + "|" + keys.join(",") : "",
    cards: keys.map(function(key) { return gpuRow(find(s.gpus, "key", key)) }) }))
}

// the maker of a card, for its logo
function vendor(g) { return ({ nvidia: "nvidia", "intel-xpu": "intel", "amd-rocm": "amd" })[g.backend] || "" }
function gpuRow(g) {
  if (g.backend === "cpu") return { type: "gpu", cpu: true, name: g.name, bar: false, mem: g.ramGb + " GB RAM", temp: "" }
  var used = g.usedMiB != null ? g.usedMiB / 1024 : null
  return { type: "gpu", vendor: vendor(g), name: g.name, bar: used != null, pct: used != null && g.vramGb ? Math.min(100, Math.round(used / g.vramGb * 100)) : 0,
    mem: (used != null ? Math.round(used * 10) / 10 + " / " : "") + g.vramGb + " GB",
    temp: g.tempC != null ? g.tempC + "°" : "" }
}

function weights(rows, list) {
  if (!(list || []).length) return
  rows.push({ type: "sec", label: "WEIGHTS" })
  list.forEach(function(w) {
    rows.push({ type: "field", logo: "hf", label: "hugging face", value: w.repository,
      action: "url|https://huggingface.co/" + w.repository + "/tree/" + w.revision })
  })
}

// Agent identity and actions keep the same rows and buttons as the rest of the panel.
function agentName(a) {
  return ({ pi: "pi", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", omp: "oh-my-pi",
    crush: "Crush", grok: "Grok", copilot: "GitHub Copilot", hermes: "Hermes" })[a] || a || "Choose an agent"
}
// The agent: closed, one row with the one chosen; opened, every agent once, the chosen one marked (a check, an ink
// bar), each of the others choosing itself. Then default and update for the chosen one, and the folder.
// an agent's newer version, when its manager has one (outdated.json): "Update to 2.1.292"
function update(s, ui, a) {
  var u = (s.updates || {})[a]
  return u ? { label: ui.updatingAgent === a ? "Updating…" : "Update to " + u.latest, action: ui.updatingAgent ? "" : "update|" + a } : null
}
function pickers(s, rows, ui, agent, folder, id, always) {
  // on the agents page choosing sets the default; on a model it sets that model's agent
  var choose = function(a) { return always ? "default|" + a : "set|agent|" + encodeURIComponent(a) + "|" + id }
  if (ui.open === "agent" || always) (s.agents || []).forEach(function(a) {
    rows.push({ type: "agent", agent: a, label: agentName(a), on: a === agent, action: a === agent ? (always ? "" : "pick|agent") : choose(a) })
  })
  else rows.push({ type: "agent", agent: agent || "", label: agentName(agent), on: true, drop: true, action: "pick|agent" })
  var u = !always && agent && update(s, ui, agent)
  if (u) rows.push({ type: "links", items: [u] })
  rows.push({ type: "field", icon: "folder", label: "folder", value: home(folder),
    action: "folder|" + id + "|" + encodeURIComponent(folder || "") })
}

function agentsView(s, ui) {
  var rows = [{ type: "sec", label: "DEFAULT AGENT" }]
  pickers(s, rows, ui, (s.defaults || {}).agent, (s.defaults || {}).folder, "", true)
  // only agents with a newer version, each with its update
  var ups = (s.agents || []).map(function(a) { return [a, update(s, ui, a)] }).filter(function(x) { return x[1] })
  if (ups.length) {
    rows.push({ type: "sec", label: "UPDATES" })
    ups.forEach(function(x) {
      rows.push({ type: "field", label: agentName(x[0]), value: (s.updates[x[0]].current || "") + " → " + s.updates[x[0]].latest })
      rows.push({ type: "links", items: [x[1]] })
    })
  }
  return { back: true, where: "agents", rows: rows }
}

function build(s, ui) {
  s = s || {}
  var v = (ui.view === "agents" ? agentsView(s, ui) : ui.view === "run" ? runView(s, ui.id, ui) : ui.view === "kind" ? kindView(s, ui.id, ui) : ui.view === "gpus" ? gpusView(s, ui) : ui.view === "group" ? groupView(s, ui.id, Number(ui.key), ui) : null) || homeView(s, ui)
  if (ui.problem || ui.pollProblem || s.setupError) v.rows.unshift({ type: "error", label: ui.problem || ui.pollProblem || s.setupError })
  else if (ui.notice) v.rows.unshift({ type: "banner", text: ui.notice })
  return Object.assign(v, { mark: ui.problem || ui.pollProblem || s.setupError ? "failed" : mark(s) })
}

if (typeof module !== "undefined") module.exports = { build: build, parse: parse, tones: tones, catalog: catalog }
