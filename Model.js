// What the Local AI panel shows, as data: the backend's snapshot and the panel's ui state in, a list of items out.
// Panel.qml draws each item and turns its actions ("verb|arg|arg") into backend verbs. No Qt, no side effects.
// The panel (design/SPEC.md): two tabs, home (tokens generated, a bar a day) and gpus (one line per GPU, model or
// build, each with a drawer that holds its actions); config, ⋯ (agent, folder, share) are the only pages below.
// Errors are not drawn here: the panel sends them to the desktop's notifications.

// tokens with k / M / B / T
function short(n) {
  n = n || 0
  var u = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]].filter(function(x) { return n >= x[0] })[0]
  return u ? +(n / u[0]).toFixed(u[1] === "k" ? 0 : 1) + u[1] : String(n)
}
function home(dir) { return (dir || "").replace(/^\/home\/[^\/]+/, "~") }
function find(list, key, v) { return (list || []).filter(function(x) { return x[key] === v })[0] || null }
function fits(r) { return !r.unfit }
function best(list) { return (list || []).filter(fits)[0] || null }
function working(d) { return d.state !== "ready" && d.state !== "error" }
function parse(text) { try { return JSON.parse(text) } catch (e) { return null } }
function pad(n, w) { n = String(n); while (n.length < w) n = " " + n; return n }

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

// A card's name without its maker's words: the mark beside it says whose it is
function cardName(g) {
  if (g.backend === "cpu") return "CPU"
  return g.name.replace(/\b(NVIDIA|GeForce|Intel|AMD|Radeon|Arc|Pro|RTX)\b\s*/g, "").trim() || g.name
}
function maker(g) { return g.backend === "cpu" ? "cpu" : g.backend === "nvidia" ? "nvidia" : /intel/.test(g.backend) ? "intel" : "amd" }
// a free card's temperature and memory, rounded and padded so every line is the same width
function room(g, s) {
  if (g.backend === "cpu") return Math.floor((s.host || {}).freeRamGb || g.ramGb || 0) + " GB RAM free"
  var free = g.usedMiB != null ? g.vramGb - g.usedMiB / 1024 : g.vramGb
  return (g.tempC != null ? pad(g.tempC, 2) + "°  " : "") + pad(Math.max(0, Math.round(free)), 2) + " GB free"
}
// why a model cannot run here, short enough for the right of a line
function lack(m) { return (m.unfit || "").split("; ")[0].replace(/, you have \d+$/, "").replace("the models folder on ", "") }
function ram(m) { return m.needs && m.needs.host_ram_gb ? "+" + Math.ceil(m.needs.host_ram_gb) + " GB RAM" : "" }

// The model Run starts on a card or a build: the one chosen in config, else the registry's first that fits
function chosen(ui, key, list) { return find((list || []).filter(fits), "id", (ui.picks || {})[key]) || best(list) }

// One line per running model, per free or busy card, and per build of several free cards of a kind.
// A line: { logo: {kind: lab|hw, name}, name, next (a free line's model, shown on hover), info, dim, progress,
// drawer: [main, second, third] } where main is the one solid button and the rest are quiet links.
function lines(s, ui) {
  var out = [], deps = s.deployments || [], used = {}
  deps.forEach(function(d) {
    d.keys.forEach(function(k) { used[k] = 1 })
    var all = (d.session || {}).all || {}, ln = { id: "d:" + d.id, logo: { kind: "lab", name: d.family }, name: d.name }
    if (d.state === "error") Object.assign(ln, { info: "stopped", quiet: true,
      drawer: [{ label: "Run again", action: "again|" + d.id + "|" + d.keys.join(",") }, { label: "dismiss", action: "stop|" + d.id }] })
    else if (working(d)) Object.assign(ln, { info: d.state === "stopping" ? "stopping" : (d.detail || d.state) + (d.percent > 0 ? " " + d.percent + "%" : ""),
      progress: d.state === "stopping" ? -1 : d.percent || 0, drawer: d.state === "stopping" ? null : [null, { label: "stop", action: "stop|" + d.id }] })
    else Object.assign(ln, { info: all.decode ? pad(Math.round(all.decode), 3) + " tok/s" : "ready",
      drawer: [{ label: "Open " + agentName(d.agent), action: "open|" + d.id }, { label: "stop", action: "stop|" + d.id }, { label: "⋯", action: "more|" + d.id }] })
    out.push(ln)
  })
  var free = [], dim = []
  ;(s.gpus || []).forEach(function(g) {
    if (used[g.key]) return
    var kd = find(s.kinds, "hw", g.hw), m = kd && chosen(ui, g.key, kd.models)
    var ln = { id: "g:" + g.key, logo: { kind: "hw", name: maker(g) }, name: cardName(g) }
    if (!kd) dim.push(Object.assign(ln, { info: "no model yet", dim: true }))
    else if (kd.taken.indexOf(g.key) >= 0) dim.push(Object.assign(ln, { info: "in use", dim: true }))
    else if (!m) dim.push(Object.assign(ln, { info: (kd.models || []).length ? lack(kd.models[0]) : "no model yet", dim: true,
      drawer: (kd.models || []).length ? [{ label: "Config", action: "config|" + g.key }] : null }))
    else free.push(Object.assign(ln, { info: room(g, s), next: { logo: { kind: "lab", name: m.family }, name: m.name },
      drawer: [{ label: "Run", action: "run|" + m.id + "|" + g.key }, { label: "config", action: "config|" + g.key }] }))
  })
  // a build of n cards of a kind: its own line, runnable while n of them are free
  ;(s.kinds || []).forEach(function(kd) {
    var g = find(s.gpus, "key", kd.keys[0]), seen = {}
    ;(kd.groups || []).forEach(function(gr) {
      var n = gr.cards
      if (seen[n] || !g) return
      seen[n] = 1
      var key = kd.hw + "*" + n, list = kd.groups.filter(function(x) { return x.cards === n }), m = chosen(ui, key, list)
      var ln = { id: "b:" + key, logo: { kind: "hw", name: maker(g) }, name: n + " × " + cardName(g) }
      if (kd.free.length < n || !m) dim.push(Object.assign(ln, { info: m ? "in use" : lack(list[0]), dim: true }))
      else free.push(Object.assign(ln, { info: room(Object.assign({}, g, { vramGb: g.vramGb * n, usedMiB: null }), s),
        next: { logo: { kind: "lab", name: m.family }, name: m.name },
        drawer: [{ label: "Run", action: "run|" + m.id + "|" + kd.free.slice(0, n).join(",") }, { label: "config", action: "config|" + key }] }))
    })
  })
  return out.concat(free, dim).map(function(ln) { return Object.assign({ type: "line" }, ln) })
}

// tokens generated, all time, with its cumulative line over the days on record
function top(s, h) {
  var life = s.life || {}, days = (life.days || []).slice(0, Math.max(1, (life.today || 0) + 1)), sum = 0
  return { type: "top", tokens: short(s.total), h: h, line: days.map(function(v) { sum += v; return sum }) }
}
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
// a bar per day for the last 30, each with what hovering it says
function bars(s) {
  var life = s.life || {}, today = life.today || 0, from = Math.max(0, today - 29), days = (life.days || []).slice(from, today + 1)
  return { type: "bars", values: days, labels: days.map(function(v, i) {
    var d = new Date((life.start || 0) * 1000)
    d.setDate(d.getDate() + from + i)
    return DAYS[d.getDay()] + " " + MONTHS[d.getMonth()] + " " + d.getDate() + "  " + short(v)
  }) }
}

var SUPPORTED = "url|https://local.sybilsolutions.ai"
// not ready: what is wrong and the one thing that fixes it (lib/access.sh's states)
var READY = {
  "needs-setup": { head: "Set up Local AI", lines: ["Docker access and, on NVIDIA, the container toolkit, once.", "It asks for your password in a terminal."], button: { label: "Set up", action: "setup" } },
  "docker-down": { head: "Docker isn't running", lines: ["Models run in Docker. Start it and", "Local AI picks up where it was."], button: { label: "Start Docker", action: "docker" } },
  unsupported: { head: "Omarchy is too old for Local AI", lines: ["Local AI needs Omarchy's Sudoless Docker,", "which came with a newer Omarchy."], button: { label: "Update Omarchy", action: "omarchy-update" } }
}

function tabs(ui) { return { type: "tabs", on: ui.tab === "home" ? "home" : "gpus" } }

function mainView(s, ui) {
  var items = [tabs(ui)], state = (s.readiness || {}).state || "ready"
  if (state !== "ready") {
    var t = READY[state] || { head: "Local AI is not ready", lines: ["It checks again by itself."] }
    items.push({ type: "msg", head: t.head, lines: t.lines, button: t.button })
    if (state === "needs-setup" && (s.gpus || []).length) {
      items.push({ type: "note", text: "found" })
      s.gpus.forEach(function(g) { items.push({ type: "line", id: "g:" + g.key, logo: { kind: "hw", name: maker(g) }, name: cardName(g), info: "", dim: true }) })
    }
    return items.concat(lines({ deployments: s.deployments }, ui))
  }
  if (!(s.kinds || []).length && !(s.deployments || []).length) {
    var found = (s.gpus || []).map(function(g) { return g.name }).filter(function(n, i, a) { return a.indexOf(n) === i })
    return items.concat([{ type: "msg", head: found.length ? "No tested model for " + found.join(", ") + " yet" : "No supported GPU here",
      lines: ["The list grows as cards are tested."], button: { label: "See supported cards", action: SUPPORTED } }])
  }
  if (ui.tab === "home") {
    if (!s.total) return items.concat([{ type: "msg", head: "No tokens yet", lines: ["Run a model on gpus and they add up here."] }])
    return items.concat([top(s, 60), { type: "note", text: "per day" }, bars(s)])
  }
  if (s.total) items.push(top(s, 44))
  return items.concat(lines(s, ui))
}

// config: what Run starts on a card or a build, one list; a model on disk can be run or removed from its line
function configView(s, ui) {
  var key = ui.id, g, list, label, run
  if (key.indexOf("*") > 0) {
    var hw = key.split("*")[0], n = Number(key.split("*")[1]), kd = find(s.kinds, "hw", hw)
    g = kd && find(s.gpus, "key", kd.keys[0])
    if (!g) return null
    list = kd.groups.filter(function(x) { return x.cards === n }); label = n + " × " + cardName(g)
    run = function(m) { return kd.free.length >= n ? "run|" + m.id + "|" + kd.free.slice(0, n).join(",") : "" }
  } else {
    g = find(s.gpus, "key", key)
    var kd1 = g && find(s.kinds, "hw", g.hw)
    if (!kd1) return null
    list = kd1.models; label = cardName(g)
    run = function(m) { return kd1.free.indexOf(key) >= 0 ? "run|" + m.id + "|" + key : "" }
  }
  var pick = chosen(ui, key, list), items = [{ type: "back", label: label, sub: g.backend === "cpu" ? "" : room(g, s).replace(/^.*°\s+/, "").trim() }]
  list.forEach(function(m) {
    items.push({ type: "pick", id: m.id, logo: { kind: "lab", name: m.family }, name: m.name, on: pick && m.id === pick.id, off: !fits(m),
      note: !fits(m) ? lack(m) : [m.onDisk ? "on disk" : "", ram(m)].filter(Boolean).join(" · "),
      action: fits(m) ? "pick|" + key + "|" + m.id : "",
      drawer: m.onDisk && fits(m) ? [{ label: "Run", action: run(m) }, { label: "remove", action: "forget|" + m.id }] : null })
  })
  items.push({ type: "button", label: "Run", action: pick ? run(pick) : "", right: { label: ui.registryBusy ? "refreshing models…" : "refresh models", action: ui.registryBusy ? "" : "registry" } })
  return items
}

function agentName(a) {
  return ({ pi: "pi", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", omp: "oh-my-pi",
    crush: "Crush", grok: "Grok", copilot: "Copilot", hermes: "Hermes" })[a] || a || "an agent"
}

// ⋯ on a running model: its agent, its folder, its share
function moreView(s, ui) {
  var d = find(s.deployments, "id", ui.id)
  if (!d) return null
  var g = find(s.gpus, "key", d.keys[0]), items = [{ type: "back", label: d.name, sub: g ? (d.keys.length > 1 ? d.keys.length + " × " : "") + cardName(g) : "" },
    { type: "kv", k: "agent", v: agentName(d.agent) + " ›", action: "go|agent|" + d.id },
    { type: "kv", k: "folder", v: home(d.folder) + " ›", action: "go|folder|" + d.id }]
  if (s.tailnet) items.push(d.shared ? { type: "kv", k: "share", v: "on ›", action: "go|share|" + d.id }
    : { type: "kv", k: "share", v: "off · turn on", action: d.state === "ready" ? "share|" + d.id : "" })
  items.push({ type: "links", items: [{ label: "logs", action: "log" }] })
  return items
}
function agentView(s, ui) {
  var d = find(s.deployments, "id", ui.id), def = (s.defaults || {}).agent
  if (!d) return null
  var items = [{ type: "back", label: "agent", sub: d.name }]
  ;(s.agents || []).forEach(function(a) {
    items.push({ type: "opt", agent: a, name: agentName(a), on: a === d.agent, note: a === def ? "default" : "", action: "set|agent|" + encodeURIComponent(a) + "|" + d.id })
  })
  if (d.agent && d.agent !== def) items.push({ type: "links", items: [{ label: "make " + agentName(d.agent) + " the default", action: "default|" + d.agent }] })
  return items
}
function folderView(s, ui) {
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
function shareView(s, ui) {
  var d = find(s.deployments, "id", ui.id)
  if (!d || !d.shared) return null
  return [{ type: "back", label: "share", sub: "on" },
    { type: "field", value: d.shared.replace(/^https:\/\//, ""), links: [{ label: "address · copy", action: "copy|" + d.shared }] },
    { type: "field", value: "sk-•••••••••••••••••", links: [{ label: "key · copy", action: "copykey" }] },
    { type: "button", label: "Stop sharing", action: "share|" + d.id + "|off" }]
}

function build(s, ui) {
  s = s || {}
  ui = ui || {}
  var page = { config: configView, more: moreView, agent: agentView, folder: folderView, share: shareView }[ui.view]
  var items = page && s.gpus ? page(s, ui) : null
  if (items) items = [tabs(ui)].concat(items)
  return { mark: mark(s), page: items ? ui.view : "main", items: items || (s.gpus ? mainView(s, ui) : [tabs(ui)]) }
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
