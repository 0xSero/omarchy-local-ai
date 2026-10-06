// What the Local AI panel shows, as data: the backend's snapshot and the panel's ui state in, a view out.
// Panel.qml draws it and turns its actions ("verb|arg|arg") into backend verbs. No Qt, no side effects.
// The panel (design/SPEC.md): a header band (tabs, tokens generated, today, the line) and a footer band (the machine in
// one line) around a body. home: launch what runs (each model in its agent and folder), the usage tiers, the calendar.
// gpus: one row per running model, card and build; every row opens in place with its buttons. Errors are not drawn
// here: the panel sends them to the desktop's notifications.

// tokens with k / M / B / T
function short(n) {
  n = n || 0
  var u = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]].filter(function(x) { return n >= x[0] })[0]
  return u ? +(n / u[0]).toFixed(u[1] === "k" && n >= 1e4 ? 0 : 1) + u[1] : String(n)
}
function home(dir) { return (dir || "").replace(/^\/home\/[^\/]+/, "~") }
function find(list, key, v) { return (list || []).filter(function(x) { return x[key] === v })[0] || null }
function fits(r) { return !r.unfit }
function best(list) { return (list || []).filter(fits)[0] || null }
function working(d) { return d.state !== "ready" && d.state !== "error" }
function parse(text) { try { return JSON.parse(text) } catch (e) { return null } }
function sum(a) { return (a || []).reduce(function(x, y) { return x + (y || 0) }, 0) }
function dur(s) {
  s = Math.max(0, Math.round(s))
  return s < 3600 ? Math.floor(s / 60) + "m" : Math.floor(s / 3600) + ":" + ("0" + Math.floor(s % 3600 / 60)).slice(-2)
}

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
// ink for what matters now, value for what a label names, label for every label, dim for what cannot be used,
// rule for lines that are not text; a theme too soft to lead is pushed toward white (or black) until it does
var LC = { ink: 90, value: 80, label: 60, dim: 35, rule: 15 }
function tones(ink, bg, surface) {
  var card = over(surface, bg), white = { r: 1, g: 1, b: 1 }, black = { r: 0, g: 0, b: 0 }
  var far = Math.abs(apca(white, card)) > Math.abs(apca(black, card)) ? white : black
  var top = reach(over(ink, bg), far, card, LC.ink)
  return { ink: top, value: reach(card, top, card, LC.value), label: reach(card, top, card, LC.label),
    dim: reach(card, top, card, LC.dim), rule: reach(card, top, card, LC.rule) }
}

// the bar mark: failed, busy, ready or idle
function mark(s) {
  var d = (s && s.deployments) || []
  if (d.some(function(x) { return x.state === "error" })) return "failed"
  if (d.some(working)) return "busy"
  return d.some(function(x) { return x.state === "ready" }) ? "ready" : ""
}

// A card's full name without its maker's words that its mark already says
function cardName(g) {
  if (g.backend === "cpu") return "CPU"
  return g.name.replace(/^(NVIDIA|Intel|AMD)\s+/, "").replace(/^GeForce\s+/, "").trim() || g.name
}
function maker(g) { return g.backend === "cpu" ? "cpu" : g.backend === "nvidia" ? "nvidia" : /intel/.test(g.backend) ? "intel" : "amd" }
// a card's facts on the row's second line, and how full its memory is (null when the card does not say)
function facts(g, s) {
  if (g.backend === "cpu") {
    var h = s.host || {}
    return { text: Math.floor(h.freeRamGb || 0) + " of " + Math.floor(h.ramGb || g.ramGb || 0) + " GB RAM free", frac: h.ramGb ? 1 - h.freeRamGb / h.ramGb : null }
  }
  var used = g.usedMiB != null ? g.usedMiB / 1024 : null
  return { text: (used != null ? Math.round(used) + " / " : "") + g.vramGb + " GB" + (g.tempC != null ? "  ·  " + g.tempC + "°" : ""),
    frac: used != null && g.vramGb ? Math.min(1, used / g.vramGb) : null }
}
function lack(m) { return (m.unfit || "").split("; ")[0].replace(/, you have \d+$/, "").replace("the models folder on ", "") }
function note(m) {
  if (!fits(m)) return lack(m)
  return [m.onDisk ? "on disk" : m.sizeGb ? Math.round(m.sizeGb) + " GB download" : "", m.needs && m.needs.host_ram_gb ? "+" + Math.ceil(m.needs.host_ram_gb) + " GB RAM" : ""]
    .filter(Boolean).join(" · ")
}
function agentName(a) {
  return ({ pi: "pi", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", omp: "oh-my-pi",
    crush: "Crush", grok: "Grok", copilot: "Copilot", hermes: "Hermes" })[a] || a || "an agent"
}

// The model Run starts on a card or a build: the one picked in its list, else the registry's first that fits
function chosen(ui, key, list) { return find((list || []).filter(fits), "id", (ui.picks || {})[key]) || best(list) }
// every model for a card or build, best first, as rows of a list: the picked one on, one that does not fit off
function modelList(ui, key, list, ro) {
  var pick = chosen(ui, key, list)
  return (list || []).map(function(m, i) {
    return { name: m.name, family: m.family, note: note(m), on: !ro && !!pick && m.id === pick.id, off: ro || !fits(m),
      tag: i === 0 && fits(m) ? "recommended" : "", action: ro || !fits(m) ? "" : "pick|" + key + "|" + m.id,
      remove: !ro && m.onDisk ? "forget|" + m.id : "" }
  })
}

// ---------------------------------------------------------------- gpus

var SUPPORTED = "url|https://local.sybilsolutions.ai"
// One row per running model, per card that is not running one, and per build of several cards of a kind.
// A row: { id, mark: {kind: lab|hw, name}, name, right, facts, frac, live, quiet, dim, progress, open, detail }
function rows(s, ui) {
  var out = [], deps = s.deployments || [], used = {}
  deps.forEach(function(d) {
    d.keys.forEach(function(k) { used[k] = 1 })
    var cards = (s.gpus || []).filter(function(g) { return d.keys.indexOf(g.key) >= 0 }), g = cards[0]
    var f = g ? facts(g, s) : { text: "", frac: null }, all = (d.session || {}).all || {}
    var r = { id: "d:" + d.id, mark: { kind: "lab", name: d.family }, name: d.name,
      facts: (cards.length > 1 ? cards.length + " × " : "") + (g ? cardName(g) + "  ·  " + f.text : ""), frac: cards.length > 1 ? null : f.frac }
    if (d.state === "error") Object.assign(r, { right: "stopped", quiet: true, detail: { kind: "stopped", lines: [d.error || "the engine stopped"],
      button: { label: "Run again", action: "again|" + d.id + "|" + d.keys.join(",") }, links: [{ label: "dismiss", action: "stop|" + d.id }, { label: "logs", action: "log" }] } })
    else if (working(d)) Object.assign(r, { right: d.state === "stopping" ? "stopping" : (d.detail || d.state) + (d.percent > 0 ? " " + d.percent + "%" : ""),
      progress: d.state === "stopping" ? -1 : d.percent || 0, detail: { kind: "busy", links: d.state === "stopping" ? [] : [{ label: "stop", action: "stop|" + d.id }] } })
    else {
      var line = all.line || [], spark = line.map(function(v, i) { return i ? Math.max(0, v - line[i - 1]) : 0 }).slice(1)
      var kd = g && find(s.kinds, "hw", g.hw), more = kd && (kd.models || []).length > 1
      Object.assign(r, { right: all.decode ? Math.round(all.decode) + " tok/s" : "ready", live: true, detail: { kind: "run",
        cells: [[all.decode ? String(Math.round(all.decode)) : "–", "tok/s"], [all.prefill ? short(all.prefill) : "–", "prefill/s"],
          [all.ttft != null ? (all.ttft / 1000).toFixed(1) + " s" : "–", "first token"], [short((d.session || {}).tokens), "this run"],
          [short(all.tokens), "total"], [isNaN(Date.parse(d.startedAt)) ? "–" : dur((Date.now() - Date.parse(d.startedAt)) / 1000), "up"]],
        spark: spark,
        kv: [{ k: "model", v: more ? "change ›" : "", action: more ? "go|model|" + d.id : "" },
          { k: "agent", v: agentName(d.agent) + " ›", action: "go|agent|" + d.id },
          { k: "folder", v: home(d.folder) + " ›", action: "go|folder|" + d.id }].concat(s.tailnet ? [d.shared
            ? { k: "share", v: "on ›", action: "go|share|" + d.id } : { k: "share", v: "off · turn on", action: "share|" + d.id }] : []),
        button: { label: "Open " + agentName(d.agent), action: "open|" + d.id },
        links: [{ label: "Stop", action: "stop|" + d.id }, { label: "logs", action: "log" }] } })
    }
    out.push(r)
  })
  var free = [], dim = []
  ;(s.gpus || []).forEach(function(g) {
    if (used[g.key]) return
    var kd = find(s.kinds, "hw", g.hw), f = facts(g, s), m = kd && chosen(ui, g.key, kd.models)
    var r = { id: "g:" + g.key, mark: { kind: "hw", name: maker(g) }, name: cardName(g), facts: f.text, frac: f.frac }
    if (!kd || !(kd.models || []).length) dim.push(Object.assign(r, { right: "no model yet", dim: true,
      detail: { kind: "held", lines: ["No tested model for this card yet."], links: [{ label: "supported cards", action: SUPPORTED }] } }))
    else if (kd.taken.indexOf(g.key) >= 0) dim.push(Object.assign(r, { right: "in use", dim: true,
      detail: { kind: "held", lines: ["Held by another program" + (g.usedMiB != null ? ", " + Math.round(g.usedMiB / 1024) + " GB of its memory in use." : ".")],
        note: "runs here when free", models: modelList(ui, g.key, kd.models, true) } }))
    else (m ? free : dim).push(Object.assign(r, { right: m ? "free" : lack(kd.models[0]), dim: !m, detail: { kind: "free", models: modelList(ui, g.key, kd.models),
      button: m ? { label: "Run " + m.name, action: "run|" + m.id + "|" + g.key } : null } }))
  })
  // a build of n cards of a kind: its own row, runnable while n of them are free
  ;(s.kinds || []).forEach(function(kd) {
    var g = find(s.gpus, "key", kd.keys[0]), seen = {}
    ;(kd.groups || []).forEach(function(gr) {
      var n = gr.cards
      if (seen[n] || !g) return
      seen[n] = 1
      var key = kd.hw + "*" + n, list = kd.groups.filter(function(x) { return x.cards === n }), m = chosen(ui, key, list), ok = kd.free.length >= n && !!m
      var r = { id: "b:" + key, mark: { kind: "hw", name: maker(g) }, name: n + " × " + cardName(g), facts: g.vramGb * n + " GB  ·  " + kd.free.length + " of " + kd.keys.length + " free", frac: null }
      ;(ok ? free : dim).push(Object.assign(r, { right: ok ? "free" : "in use", dim: !ok, detail: { kind: ok ? "free" : "held",
        lines: ok ? null : ["Needs " + n + " free cards; " + kd.free.length + " free now."], note: ok ? "" : "runs here when free", models: modelList(ui, key, list, !ok),
        button: ok ? { label: "Run " + m.name, action: "run|" + m.id + "|" + kd.free.slice(0, n).join(",") } : null } }))
    })
  })
  var all = out.concat(free)
  if (dim.length && all.length) all.push({ type: "rule" })
  return all.concat(dim).map(function(r) { return r.type ? r : Object.assign({ type: "row", open: ui.open === r.id }, r) })
}

// ---------------------------------------------------------------- home

// launch: each ready model in the agent and folder it opens with, one press away; the agent and folder change here
function launch(s) {
  return (s.deployments || []).filter(function(d) { return d.state === "ready" }).map(function(d) {
    return { type: "launch", name: d.name, family: d.family, agent: agentName(d.agent), folder: home(d.folder),
      open: "open|" + d.id, agentAction: "go|agent|" + d.id, folderAction: "go|folder|" + d.id }
  })
}
// the tiers: today, the last 7, 30, 90 and 365 days, all time
function tiers(s) {
  var life = s.life || {}, days = (life.days || []).slice(0, (life.today || 0) + 1), n = days.length
  var last = function(k) { return sum(days.slice(Math.max(0, n - k))) }
  return { type: "tiers", cells: [[short(days[n - 1]), "today"], [short(last(7)), "week"], [short(last(30)), "month"],
    [short(last(90)), "3 months"], [short(last(365)), "year"], [short(s.total), "lifetime"]] }
}
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
// the calendar: a column a week (Monday on top), the last `weeks`, each day shaded 0..4 against the busiest day,
// -1 for days before the record or still to come; the month over its first week; what hovering a day says
function calendar(s, weeks) {
  var life = s.life || {}, days = (life.days || []).slice(0, (life.today || 0) + 1), top = Math.max.apply(null, days.concat([1]))
  var today = new Date((life.start || 0) * 1000)
  today.setDate(today.getDate() + days.length - 1)
  var dow = (today.getDay() + 6) % 7, total = weeks * 7, first = days.length - 1 - (total - 7 + dow)
  var cells = [], labels = [], months = [], last = -1
  for (var i = 0; i < total; i++) {
    var at = first + i, v = at >= 0 && at < days.length ? days[at] : -1
    var d = new Date(today)
    d.setDate(d.getDate() + at - (days.length - 1))
    cells.push(v < 0 ? -1 : v > 0 ? Math.ceil(v / top * 4) : 0)
    labels.push(v < 0 ? "" : DAYS[d.getDay()] + " " + MONTHS[d.getMonth()] + " " + d.getDate() + "  ·  " + short(v) + " tokens")
    if (i % 7 === 0) { if (d.getMonth() !== last && i / 7 < weeks - 2) months.push({ col: i / 7, label: MONTHS[d.getMonth()] }); last = d.getMonth() }
  }
  return { type: "calendar", weeks: weeks, cells: cells, labels: labels, months: months, today: total - 7 + dow }
}

// ---------------------------------------------------------------- the body of the main view

var READY = {
  "needs-setup": { head: "Set up Local AI", lines: ["Docker access and, on NVIDIA, the container toolkit, once. It asks for your password in a terminal."], button: { label: "Set up", action: "setup" } },
  "docker-down": { head: "Docker isn't running", lines: ["Models run in Docker. Start it and Local AI picks up where it was."], button: { label: "Start Docker", action: "docker" } },
  unsupported: { head: "Omarchy is too old for Local AI", lines: ["Local AI needs Omarchy's Sudoless Docker, which came with a newer Omarchy."], button: { label: "Update Omarchy", action: "omarchy-update" } }
}

function body(s, ui) {
  var state = (s.readiness || {}).state || "ready"
  if (state !== "ready") {
    var t = READY[state] || { head: "Local AI is not ready", lines: ["It checks again by itself."] }, items = [{ type: "msg", head: t.head, lines: t.lines, button: t.button }]
    if (state === "needs-setup" && (s.gpus || []).length) {
      items.push({ type: "note", text: "found" })
      s.gpus.forEach(function(g) { items.push({ type: "row", id: "g:" + g.key, mark: { kind: "hw", name: maker(g) }, name: cardName(g), right: "", facts: facts(g, s).text, dim: true }) })
    }
    return items.concat(rows(s, ui).filter(function(r) { return r.type === "row" && r.id.indexOf("d:") === 0 }))
  }
  if (!(s.kinds || []).length && !(s.deployments || []).length) {
    var found = (s.gpus || []).map(function(g) { return cardName(g) }).filter(function(n, i, a) { return a.indexOf(n) === i })
    return [{ type: "msg", head: found.length ? "No tested model for " + found.join(", ") + " yet" : "No supported GPU here",
      lines: ["The list grows as cards are tested."], button: { label: "See supported cards", action: SUPPORTED } }]
  }
  if (ui.tab === "home") {
    var l = launch(s), out = l.length ? [{ type: "note", text: "launch" }].concat(l) : []
    if (!s.total) return out.concat([{ type: "msg", head: "No tokens yet", lines: ["Run a model on gpus and they add up here: today, this week, all time."] }])
    return out.concat([tiers(s), calendar(s, 25)])
  }
  return rows(s, ui)
}

// ---------------------------------------------------------------- pages under a running model

function modelPage(s, ui) {
  var d = find(s.deployments, "id", ui.id), g = d && find(s.gpus, "key", d.keys[0]), kd = g && find(s.kinds, "hw", g.hw)
  if (!kd) return null
  var key = d.keys.join(","), rid = d.id.replace(/--\d+$/, ""), list = d.keys.length > 1 ? (kd.groups || []).filter(function(x) { return x.cards === d.keys.length }) : kd.models
  var pick = find(list.filter(fits), "id", (ui.picks || {})[key]) || find(list, "id", rid)
  var items = [{ type: "back", label: d.name, sub: (d.keys.length > 1 ? d.keys.length + " × " : "") + cardName(g) }, { type: "list", models: list.map(function(m) {
    return { name: m.name, family: m.family, note: m.id === rid ? "running" : note(m), on: !!pick && m.id === pick.id, off: !fits(m),
      action: fits(m) ? "pick|" + key + "|" + m.id : "", remove: m.onDisk && m.id !== rid ? "forget|" + m.id : "" }
  }) }]
  if (pick && pick.id !== rid) items.push({ type: "button", label: "Switch to " + pick.name, action: "switch|" + d.id + "|" + pick.id + "|" + key })
  return items
}
function agentPage(s, ui) {
  var d = find(s.deployments, "id", ui.id), def = (s.defaults || {}).agent
  if (!d) return null
  var items = [{ type: "back", label: "agent", sub: d.name }]
  ;(s.agents || []).forEach(function(a) {
    items.push({ type: "opt", agent: a, name: agentName(a), on: a === d.agent, note: a === def ? "default" : "", action: "set|agent|" + encodeURIComponent(a) + "|" + d.id })
  })
  if (d.agent && d.agent !== def) items.push({ type: "links", items: [{ label: "make " + agentName(d.agent) + " the default", action: "default|" + d.agent }] })
  return items
}
function folderPage(s, ui) {
  var d = find(s.deployments, "id", ui.id)
  if (!d) return null
  var seen = {}, items = [{ type: "back", label: "folder", sub: agentName(d.agent) + " opens in" }]
  ;[d.folder, (s.defaults || {}).folder].concat(s.folders || []).forEach(function(f) {
    if (!f || seen[f]) return
    seen[f] = 1
    items.push({ type: "opt", name: home(f), on: f === d.folder, action: "set|folder|" + encodeURIComponent(f) + "|" + d.id })
  })
  items.push({ type: "opt", name: "choose another…", quiet: true, action: "folder|" + d.id + "|" + encodeURIComponent(d.folder || "") })
  return items
}
function sharePage(s, ui) {
  var d = find(s.deployments, "id", ui.id)
  if (!d || !d.shared) return null
  return [{ type: "back", label: "share", sub: "on" },
    { type: "field", value: d.shared.replace(/^https:\/\//, ""), links: [{ label: "address · copy", action: "copy|" + d.shared }] },
    { type: "field", value: "sk-•••••••••••••••••", links: [{ label: "key · copy", action: "copykey" }] },
    { type: "button", label: "Stop sharing", action: "share|" + d.id + "|off" }]
}

// the header and footer bands: the same on every tab and page
function header(s) {
  var life = s.life || {}, days = (life.days || []).slice(0, (life.today || 0) + 1), run = 0
  return { tokens: short(s.total), today: s.total ? "today " + short(days[days.length - 1]) : "", empty: !s.total,
    line: days.map(function(v) { run += v; return run }) }
}
function footer(s) {
  var gpus = (s.gpus || []).filter(function(g) { return g.backend !== "cpu" }).length, ready = (s.deployments || []).filter(function(d) { return d.state === "ready" }).length
  var state = (s.readiness || {}).state || "ready"
  return (gpus ? gpus + (gpus === 1 ? " GPU" : " GPUs") : "CPU only") + "  ·  " + (state !== "ready" ? ({ "needs-setup": "not set up", "docker-down": "Docker stopped", unsupported: "Omarchy too old" })[state] || "not ready"
    : ready + (ready === 1 ? " model running" : " models running"))
}

function build(s, ui) {
  s = s || {}
  ui = ui || {}
  var page = { model: modelPage, agent: agentPage, folder: folderPage, share: sharePage }[ui.view]
  var items = page && s.gpus ? page(s, ui) : null
  var v = { mark: mark(s), page: items ? ui.view : "main", tab: ui.tab === "home" ? "home" : "gpus",
    header: header(s), footer: s.gpus ? footer(s) : "", items: items || (s.gpus ? body(s, ui) : []) }
  // full screen: the same tabs, wider. gpus is every row as a tile, opened; home is launch, the tiers and a year
  if (ui.full && s.gpus) v.full = (s.readiness || {}).state !== "ready" && (s.readiness || {}).state ? { items: body(s, ui) }
    : v.tab === "home" ? { items: launch(s).length ? [{ type: "note", text: "launch" }].concat(launch(s)) : [], tiers: tiers(s), calendar: s.total ? calendar(s, 52) : null }
    : { tiles: rows(s, ui).filter(function(r) { return r.type === "row" }).map(function(r) { return Object.assign({}, r, { open: !!r.detail }) }) }
  if (v.full) v.full.tiers = tiers(s)
  return v
}

// what newly went wrong between two snapshots: a model that stopped by itself, a setup that failed
function problems(before, after) {
  var was = {}, out = []
  ;((before || {}).deployments || []).forEach(function(d) { was[d.id] = d.state })
  ;((after || {}).deployments || []).forEach(function(d) {
    if (d.state === "error" && was[d.id] && was[d.id] !== "error") out.push({ title: d.name + " stopped", body: d.error || "the engine stopped" })
  })
  if ((after || {}).setupError && (after.setupError !== (before || {}).setupError)) out.push({ title: "Setup did not finish", body: after.setupError })
  return out
}

// A mark as one colour, or as black and white: a one-colour lab or card mark is drawn in the line's tone (its root fill
// and currentColor); a coloured mark (an agent's) has each colour turned to the grey of its own lightness
var NAMED = { white: "#ffffff", black: "#000000" }
function gray(hex) {
  var h = NAMED[hex] || hex, v = h.length === 4 ? h.replace(/#(.)(.)(.)/, "#$1$1$2$2$3$3") : h
  var n = parseInt(v.slice(1, 7), 16), y = Math.round(0.2126 * (n >> 16 & 255) + 0.7152 * (n >> 8 & 255) + 0.0722 * (n & 255))
  var c = ("0" + y.toString(16)).slice(-2)
  return "#" + c + c + c
}
function mono(svg, tone) {
  // a root sized in em (LobeHub's) is left to the viewBox, which Qt reads
  return String(svg || "").replace(/currentColor/g, tone).replace(/<svg\b[^>]*>/, function(r) {
    return r.replace(/\s(width|height|style|fill|color)="[^"]*"/g, "").replace(/<svg\b/, '<svg fill="' + tone + '" color="' + tone + '" width="24" height="24"')
  })
}
function grayscale(svg) {
  return String(svg || "").replace(/(fill|stroke|stop-color)="(#[0-9a-fA-F]{3,6}|white|black)"/g, function(m, k, v) { return k + '="' + gray(v) + '"' })
}

if (typeof module !== "undefined") module.exports = { build: build, parse: parse, tones: tones, problems: problems, short: short, mono: mono, grayscale: grayscale }
