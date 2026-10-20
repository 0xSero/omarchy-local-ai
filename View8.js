// Local AI 8: the backend's snapshot and the panel's ui state in, one page out. Pure: no clock, no I/O; the panel
// passes ui.now for durations, and Page8.qml draws the animations (hands, strip) from its own clock. Pages are cards of rows, drawn the same in the panel
// (340 wide) and full screen (ui.wide); only widths and how much is shown differ.
//
// Pages: connect (the brand hands, then the cards found), tree (hardware and its models), model (one recipe on one
// card or card set), main (running, several running, nothing running, first time) and settings.

// The dot hands from Omarchy's Matte Black wallpaper (art by @samdape), as text: ● a dot, · a shading dot.
// brand/hands.js mapped onto a 178 × 24 character grid; the fingertips are closest on row 11, columns 73-94.
var HANDS = ["                 ●●●●●●●●●●●●●                                                                                                                                                    ", "             ●●●●●●●●●●●●●●●●●●●●●●●●●●                                                                                                                                           ", "         ●●●●●●●●●●●●●●●●●●●●●●●●●●●·●●●●●●●●●●●●                                                                                                                        ●●●●●●●●●", "     ●●●●●●·●●●●●●●●●●●●●●●●●●●●●●●●●●●●●·●●········                                                                                                               ●●●●●●●●●●●●●●●", "●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●···                                                                                                      ●●●●●●●●●●●●●●●●●●●●●●", "●●●●●●●●●●●●···········●●●●●●●●●●●●●●●●●●●●●●●●●●●●●·····                                                                                            ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●", "●●●●●●  ················●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●········                                                                       ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●", "●●●●●●···················●●●●●●●●●●●●●●●·····●●●●●●●●●●●●●●●·····                                                            ●●●●●●●●●●●●●●●●●●●●●····●●···●●●●●●●●●●●●●●●●●●●●●●●", "●●●●●·····················●●●●●●●●●●●●●●···················●●●●●···                                    ····●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●··●●●········●●●●●●●●●●●●●●●●●●●●●●●●", "●●●●····················●●·●●●●●●●●●●●●●●·····················●●●●··                                 ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●······●·······●··●●●●●●●●●●●●●●●●●●●●●●●●", "●···················●      ●●●●··●·●●●●●●●●·   ●·················●●●··                           ●●●●●●●··●●●●●●●●●●●●●·····●●●●●●●●●●●●··························●●··········●●●●", "●·················●         ●●●·····●●●●●●●●··  ················ ······                        ●●●···············●●●·●●···●●●●●●●●●●●●●···········································", "················●             ●●●●●●●●●●●●●●●●●●·····   ········   ·····                        ··●●●         ●··●·······●●●●●●···●●··············································", "··············●                    ●●●●●●●●●●●●●●····    ········   ·●●·●                                         ·····●●●●●●·····················································", "············●                           ●●●●●●●·●·····    ········    ●●●                                        ·●●●●●●●·······················●●                     ···●·●●●●●●", "··········●                               ●●●●●·····●··    ·······                                             ·●●●●●·······●●················●●                                ●●", "·······●                                       ···●●··●     ··· ··                                           ·●●●●●●·········●●●●··●●●·····●●●                                    ", "····●                                          ···  ●●                                                      ●●········●●················●●●●                                      ", "●●                                                                                                           ●●●●●···●····●   ····●●●●●●●                                         ", "                                                                                                               ●●····●···●   ····●                                                ", "                                                                                                               ●····●···●   ····●                                                 ", "                                                                                                               ●●●··●···●   ●●··●                                                 ", "                                                                                                               ●●●··●●·●●   ●●·●                                                  ", "                                                                                                                ●··● ●●●●   ●●●                                                   "]
var GAP_ROW = 11, GAP_FROM = 73, GAP_LEN = 22

function k(n) {
  n = n || 0
  return n >= 1e9 ? (n / 1e9).toFixed(1) + "B" : n >= 1e6 ? (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K" : String(Math.round(n))
}
function gb(n) { return (n >= 9.95 ? Math.round(n) : Math.round((n || 0) * 10) / 10) + " GB" }
function ctx(n) { return n >= 1024 ? Math.round(n / 1024) + "K" : String(n || 0) }
function dur(sec) {
  sec = Math.max(0, Math.round(sec))
  var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
  return d ? d + " d " + h + " h" : h ? h + " h " + m + " m" : m + " m"
}
function home(dir) { return (dir || "").replace(/^\/home\/[^\/]+/, "~") }
function find(list, key, v) { return (list || []).filter(function(x) { return x[key] === v })[0] || null }
function base(id) { return id.indexOf("--") >= 0 ? id.slice(0, id.lastIndexOf("--")) : id }
function agentName(a) {
  return ({ pi: "pi", claude: "Claude Code", codex: "Codex", opencode: "OpenCode", omp: "omp", crush: "Crush", grok: "Grok", copilot: "Copilot", hermes: "Hermes" })[a] || a || "agent"
}
// a card's short name: "Arc Pro B70" stays, "NVIDIA GeForce RTX 3090" becomes "RTX 3090"; narrow drops the maker words
function cardName(name, narrow) {
  var n = (name || "GPU").replace(/^NVIDIA /, "").replace(/^GeForce /, "").replace(/ Laptop GPU$/, " Laptop")
  return narrow ? n.replace(/^Arc Pro /, "").replace(/^Radeon /, "").replace(/^Instinct /, "") : n
}
function gpusOf(s, keys) { return (s.gpus || []).filter(function(g) { return keys.indexOf(g.key) >= 0 }) }
function setName(gs, narrow, s) {
  if (!gs.length) return "CPU"
  var name = (gs.length > 1 ? gs.length + " × " : "") + cardName(gs[0].name, narrow)
  // one card of several of the same kind says which: "B70 #2"
  if (gs.length === 1 && s) {
    var same = (s.gpus || []).filter(function(g) { return g.name === gs[0].name })
    if (same.length > 1) name += " #" + (same.indexOf(gs[0]) + 1)
  }
  return name
}
function deps(s) { return s.deployments || [] }
function working(d) { return d.state !== "ready" && d.state !== "error" }
function recipe(s, id) {
  var out = null
  ;(s.kinds || []).forEach(function(kd) { kd.models.concat(kd.groups || []).forEach(function(r) { if (r.id === id) out = { r: r, kd: kd } }) })
  return out
}
function vision(r) { return !!(r && r.caps && r.caps.vision) }
// what tells two recipes of one model apart: the detail in their format, else the RAM they need, else their context
function variant(r) {
  var d = ((r.format || "").match(/\(([^)]+)\)/) || [])[1]
  var ram = r.needs && r.needs.host_ram_gb ? Math.ceil(r.needs.host_ram_gb) + " GB RAM" : ""
  return [d ? d.split(",")[0] : "", ram].filter(Boolean).join(" · ") || ctx(r.ctx) + " context"
}
// cards free for a recipe of n cards on its kind
function freeFor(kd, n) { return kd && kd.free.length >= n ? kd.free.slice(0, n) : null }
function cpuKind(kd) { return /cpu/.test(kd.hw) }

// ---- text pictures (monospace) ----------------------------------------------------------------------------------

var EIGHTHS = " ▁▂▃▄▅▆▇█"
// a filled area of values 0..1, rows high
function area(vals, rows) {
  var out = []
  for (var r = 0; r < rows; r++) out.push(vals.map(function(v) {
    var lvl = v * rows - (rows - 1 - r)
    return lvl >= 1 ? "█" : lvl <= 0 ? (r === rows - 1 ? "▁" : " ") : EIGHTHS[Math.max(1, Math.round(lvl * 8))]
  }).join(""))
  return out.join("\n")
}
// the three-row dot strip in the hands' texture: "fill" to a fraction, "wave" moving with the tick, "flat" grey
function strip(kind, frac, tick, cols) {
  var rows = []
  for (var r = 0; r < 3; r++) {
    var line = []
    for (var c = 0; c < cols; c++) {
      var on = kind === "full" ? true
        : kind === "fill" ? c < Math.round(frac * cols)
        : kind === "wave" ? (2 - r) <= Math.round(1 + Math.sin((c - tick) * 0.6))
        : false
      line.push(on ? "●" : "·")
    }
    rows.push(line.join(" "))
  }
  return rows.join("\n")
}
// the hands drawn in from both edges, then a spark running across the gap between the fingertips
function hands(tick) {
  var reveal = Math.min(90, tick * 2)
  var g = HANDS.map(function(l) { return l.split("").map(function(ch, c) { return Math.min(c, 177 - c) < reveal ? ch : " " }) })
  if (reveal >= 90) {
    var t = (tick - 45) % (GAP_LEN * 2), pos = t < GAP_LEN ? t : GAP_LEN * 2 - 1 - t
    for (var i = 0; i < GAP_LEN; i++) { var d = Math.abs(i - pos); g[GAP_ROW][GAP_FROM + i] = d === 0 ? "●" : d === 1 ? "•" : d === 2 ? "·" : " " }
  }
  return g.map(function(r) { return r.join("") }).join("\n")
}
// days of tokens as calendar levels 0-4, a week a column, Sunday first, oldest first
function levels(s, weeks) {
  var life = s.life || {}, days = (life.days || []).slice(0, Math.max(0, (life.today || 0) + 1))
  var cells = days.slice(-weeks * 7)
  while (cells.length < weeks * 7) cells.unshift(0)
  var top = Math.max.apply(null, cells.concat([1]))
  return cells.map(function(v) { return v > 0 ? Math.min(4, Math.max(1, Math.ceil(v / top * 4))) : 0 })
}
// days of tokens as a calendar: a column a week, a row a weekday, shaded in four steps against the busiest day
function calendar(s, weeks) {
  var life = s.life || {}, days = (life.days || []).slice(0, Math.max(0, (life.today || 0) + 1))
  var cells = days.slice(-weeks * 7)
  while (cells.length < weeks * 7) cells.unshift(0)
  var top = Math.max.apply(null, cells.concat([1])), lv = "·░▒▓█", rows = []
  for (var r = 0; r < 7; r++) {
    var line = []
    for (var w = 0; w < weeks; w++) { var v = cells[w * 7 + r]; line.push(v > 0 ? lv[Math.min(4, Math.max(1, Math.ceil(v / top * 4)))] : "·") }
    rows.push(line.join(" "))
  }
  return rows.join("\n")
}

// ---- pages ------------------------------------------------------------------------------------------------------

function header(ui, left, title) {
  return { left: left || null, title: title || "", toggle: ui.wide ? "full|off" : "full|on", gear: ui.page !== "settings" && ui.page !== "connect" }
}

var READY_SAYS = {
  "needs-setup": "Local AI needs a one-time setup on this machine",
  "docker-down": "Docker is not answering",
  "unsupported": "this Omarchy has no Sudoless Docker setup",
  "legacy-polkit": "files left by Local AI 6.0-6.4 must be removed first"
}
function connectPage(s, ui) {
  var ready = (s.readiness || {}).state || (s.gpus ? "ready" : "")
  var cards = (s.gpus || []).filter(function(g) { return g.backend !== "cpu" })
  var p = { name: "connect", header: header(ui), anim: true, cards: [] }
  var rows = [{ type: "hands" }]
  // the hands draw themselves first (Page8 runs the clock); what was found shows once they are drawn
  if (!s.gpus) { rows.push({ type: "note", center: true, spin: true, text: "looking for your cards" }); p.cards.push({ bare: true, grow: true, rows: rows }); return p }
  rows.push({ type: "note", center: true, spin: true, untilDrawn: true, text: "looking for your cards" })
  if (ready && ready !== "ready") {
    rows.push({ type: "note", center: true, alert: true, afterDrawn: true, text: (s.readiness || {}).message || READY_SAYS[ready] || ready })
    rows.push({ type: "buttons", center: true, afterDrawn: true, items: ready === "legacy-polkit"
      ? [{ label: "How to remove them", action: "url|https://github.com/0xSero/omarchy-local-ai/blob/main/docs/legacy-polkit.md", primary: true }]
      : ready === "needs-setup" ? [{ label: "Set up Local AI", action: "setup", primary: true }] : [] })
  } else {
    var kinds = {}
    cards.forEach(function(g) { kinds[g.name] = (kinds[g.name] || 0) + 1 })
    var found = Object.keys(kinds).map(function(n) { return (kinds[n] > 1 ? kinds[n] + " × " : "") + cardName(n, !ui.wide) }).join(" · ")
    rows.push({ type: "note", center: true, afterDrawn: true, text: found || "no graphics card · models run on the CPU" })
    rows.push({ type: "buttons", center: true, afterDrawn: true, items: [{ label: "Continue", action: "page|main", primary: true }] })
  }
  p.cards.push({ bare: true, grow: true, rows: rows })
  return p
}

// the tree: each kind of card; a set of the same card has a branch for models across all of them and one per card
function treePage(s, ui) {
  var closed = ui.closed || {}, more = ui.more || {}, narrow = !ui.wide
  var p = { name: "tree", header: header(ui, { label: "‹ main", action: "page|main" }, "hardware and models"), cards: [] }
  function modelRows(list, keys, lead, id) {
    var shown = more[id] ? list : list.slice(0, 3), out = []
    shown.forEach(function(r, i) {
      var twin = list.some(function(o) { return o !== r && o.name === r.name })
      var last = i === shown.length - 1 && list.length <= 3
      out.push({ type: "item", prefix: lead + (last ? "└─ " : "├─ "), label: r.name + (twin ? " · " + variant(r) : ""), tag: vision(r) ? "vision" : "",
        mid: ui.wide ? ctx(r.ctx) + " context" : "", right: gb(r.sizeGb || 0), dim: !!r.unfit, on: !!r.downloaded,
        action: "model|" + r.id + "|" + keys.join(",") })
    })
    if (list.length > 3) out.push({ type: "item", prefix: lead + "└─ ", label: more[id] ? "less" : "more (" + (list.length - 3) + ")", quiet: true, action: "more|" + id })
    return out
  }
  ;(s.kinds || []).forEach(function(kd) {
    var gs = gpusOf(s, kd.keys), rows = [], id = kd.hw
    var open = !closed[id]
    rows.push({ type: "item", node: true, caret: open ? "▾" : "▸", label: cpuKind(kd) ? "CPU" : setName(gs, narrow),
      right: cpuKind(kd) ? Math.round((s.host || {}).ramGb || 0) + " GB RAM" : gs.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0) + " GB", action: "node|" + id })
    if (open) {
      if (kd.keys.length > 1) {
        var branches = []
        var groups = (kd.groups || []).filter(function(r) { return r.cards <= kd.keys.length })
        branches.push({ id: id + "/all", label: kd.keys.length === 2 ? "both cards" : "all " + kd.keys.length + " cards", list: groups, keys: kd.keys,
          right: gs.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0) + " GB", empty: "no recipe across these cards yet" })
        gs.forEach(function(g, i) {
          branches.push({ id: id + "/" + g.key, label: cardName(g.name, narrow) + " #" + (i + 1), list: kd.models, keys: [g.key], right: g.vramGb + " GB",
            status: kd.free.indexOf(g.key) < 0 ? "in use" : "" , closedByDefault: i > 0 })
        })
        branches.forEach(function(b, bi) {
          var lastB = bi === branches.length - 1, bOpen = closed[b.id] === undefined ? !b.closedByDefault : !closed[b.id]
          rows.push({ type: "item", node: true, prefix: lastB ? "└─ " : "├─ ", caret: bOpen ? "▾" : "▸", label: b.label, mid: b.status || "", right: b.right, action: "node|" + b.id + "|" + (b.closedByDefault ? "1" : "0") })
          if (!bOpen) return
          var lead = lastB ? "   " : "│  "
          if (!b.list.length) rows.push({ type: "item", prefix: lead + "└─ ", label: b.empty, quiet: true, action: "" })
          else rows = rows.concat(modelRows(b.list, b.keys, lead, b.id))
        })
      } else rows = rows.concat(modelRows(kd.models, kd.keys, "", id))
    }
    p.cards.push({ rows: rows })
  })
  if (!p.cards.length) p.cards.push({ rows: [{ type: "note", text: "no graphics card or CPU with a tested model was found" }] })
  return p
}

// one recipe on one card or card set: what it is, what it needs, how it ran here, and Load
function modelPage(s, ui) {
  var hit = recipe(s, ui.id)
  if (!hit) return treePage(s, Object.assign({}, ui, { page: "tree" }))
  var r = hit.r, kd = hit.kd, n = r.cards || 1, narrow = !ui.wide
  var keys = (ui.keys || "").split(",").filter(Boolean)
  if (keys.length !== n) keys = freeFor(kd, n) || kd.keys.slice(0, n)
  var gs = gpusOf(s, keys), on = cpuKind(kd) ? "CPU" : setName(gs, narrow, s)
  var d = deps(s).filter(function(x) { return base(x.id) === r.id })[0] || null
  var dl = find(s.downloads || [], "id", r.id)
  var p = { name: "model", header: header(ui, { label: "‹ " + on, action: "page|tree" }), cards: [], anim: !!d || !!dl }
  var sub = [on, gb(r.sizeGb || 0), ctx(r.ctx) + " context"]
  if (vision(r)) sub.push("vision")
  var repo = ((r.weights || [])[0] || {}).repository
  var stripKind = d ? (d.state === "ready" ? "full" : d.state === "error" ? "flat" : "wave") : dl ? "fill" : r.downloaded ? "full" : "flat"
  var frac = dl ? (dl.percent || 0) / 100 : 0
  p.cards.push({ rows: [
    { type: "title", text: r.name, sub: sub.join(" · "), strip: { kind: stripKind, frac: frac, cols: narrow ? 12 : 18 } },
    repo ? { type: "links", items: [{ label: "model card ↗", action: "url|https://huggingface.co/" + repo }, { label: r.engine + " · " + (r.format || "") }] } : null
  ].filter(Boolean) })
  // how it ran on this machine, from its own gateway's log; nothing is shown that was not measured here
  var all = d && d.session ? d.session.all || {} : {}
  if (d && d.state === "ready" && (all.decode != null || all.prefill != null)) p.cards.push({ rows: [
    { type: "label", text: "measured on this machine" },
    { type: "figs", cells: [
      { k: "decode", v: all.decode != null ? all.decode + " tok/s" : "–" },
      { k: "prefill", v: all.prefill != null ? k(all.prefill) + " tok/s" : "–" },
      { k: "first token", v: all.ttft != null ? (all.ttft / 1000).toFixed(1) + " s" : "–" },
      { k: "tokens", v: k(all.tokens) }] }] })
  // what it is, from its recipe
  var w = (r.weights || [])[0] || {}
  p.cards.push({ rows: [
    { type: "kv", label: "engine", value: (r.engine || "") + " · " + (r.format || "") },
    { type: "kv", label: "context", value: (r.ctx || 0).toLocaleString ? String(r.ctx).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + " tokens" : String(r.ctx) },
    { type: "kv", label: "download", value: gb(r.sizeGb || 0) + (r.downloaded ? " · on this machine" : "") },
    { type: "kv", label: "can", value: Object.keys(r.caps || {}).filter(function(c) { return r.caps[c] }).join(" · ") || "chat" },
    w.repository ? { type: "kv", label: "weights", value: w.repository + (w.revision ? " @ " + w.revision.slice(0, 7) : "") } : null,
    r.aa != null ? { type: "kv", label: "intelligence", value: "Artificial Analysis " + r.aa } : null
  ].filter(Boolean) })
  // what it needs besides its cards
  var needs = []
  if (r.needs && r.needs.host_ram_gb) needs.push(Math.ceil(r.needs.host_ram_gb) + " GB free RAM")
  if (r.needs && r.needs.disk_gb) needs.push(Math.ceil(r.needs.disk_gb) + " GB free disk")
  if (r.needs && r.needs.fast_storage) needs.push("models folder on NVMe")
  if (needs.length) p.cards.push({ rows: [{ type: "label", text: "also needs" }, { type: "note", text: needs.join(" · ") }] })
  // one line on its state, then its action
  var state, items = []
  if (d && d.state === "ready") { state = "running on " + on; items = [{ label: "Open " + agentName(d.agent), action: "open|" + d.id, primary: true }, { label: "Stop", action: "stop|" + d.id }] }
  else if (d && d.state === "error") { state = d.error || "the engine stopped"; items = [{ label: "Load again", action: "again|" + d.id + "|" + d.keys.join(","), primary: true }, { label: "Dismiss", action: "stop|" + d.id }] }
  else if (d) { state = (d.detail || d.state) + (d.percent > 0 ? " · " + d.percent + "%" : ""); items = [{ label: "Cancel", action: "stop|" + d.id }] }
  else if (dl) { state = "downloading" + (dl.percent > 0 ? " · " + dl.percent + "%" : ""); items = [{ label: "Cancel", action: "download|" + r.id + "|off" }] }
  else if (r.unfit) state = r.unfit
  else if (kd.keys.length < n) state = "needs " + n + " cards, this machine has " + kd.keys.length
  else if (!freeFor(kd, n) || keys.some(function(k2) { return kd.free.indexOf(k2) < 0 })) state = on + " is in use"
  else { state = r.downloaded ? "on this machine · ready to load" : "loads after a " + gb(r.sizeGb || 0) + " download"; items = [{ label: "Load", action: "run|" + r.id + "|" + keys.join(","), primary: true }] }
  p.foot = { note: state, alert: !!(r.unfit || d && d.state === "error"), items: items }
  return p
}

function blockFor(s, d, ui) {
  var hit = recipe(s, base(d.id)), r = hit ? hit.r : null, gs = gpusOf(s, d.keys), narrow = !ui.wide
  var all = (d.session || {}).all || {}
  var ready = d.state === "ready", failed = d.state === "error"
  var row = { type: "block", name: d.name, tag: vision(r) ? "vision" : "", on: setName(gs, narrow, s), error: failed ? d.error || "the engine stopped" : "",
    strip: { kind: ready ? "wave" : failed ? "flat" : "fill", frac: (d.percent || 0) / 100, cols: narrow ? 12 : 22 },
    right: ready ? (all.decode != null ? all.decode + " tok/s" : k(all.tokens) + " tokens") : failed ? "" : (d.detail || d.state) + (d.percent > 0 ? " · " + d.percent + "%" : ""),
    alert: failed, action: "model|" + base(d.id) + "|" + d.keys.join(",") }
  row.items = ready ? [{ label: "Open", action: "open|" + d.id, primary: true }, { label: "Stop", action: "stop|" + d.id }]
    : failed ? [{ label: "Again", action: "again|" + d.id + "|" + d.keys.join(","), primary: true }, { label: "Dismiss", action: "stop|" + d.id }]
    : [{ label: "Cancel", action: "stop|" + d.id }]
  return row
}
function freeSets(s, narrow) {
  return (s.kinds || []).filter(function(kd) { return !cpuKind(kd) && kd.free.length }).map(function(kd) { return setName(gpusOf(s, kd.free), narrow, s) })
}
function lastUsed(s) {
  var on = []
  ;(s.kinds || []).forEach(function(kd) { kd.models.concat(kd.groups || []).forEach(function(r) { if (r.downloaded) on.push({ r: r, kd: kd }) }) })
  var pins = s.pins || []
  on.sort(function(a, b) { return (pins.indexOf(b.r.id) >= 0) - (pins.indexOf(a.r.id) >= 0) })
  return on
}
function loadAction(hit) {
  var keys = freeFor(hit.kd, hit.r.cards || 1)
  return keys ? "run|" + hit.r.id + "|" + keys.join(",") : "model|" + hit.r.id + "|"
}

function mainPage(s, ui) {
  var narrow = !ui.wide, running = deps(s), p = { name: "main", header: header(ui, { label: "models", action: "page|tree" }), cards: [], anim: running.length > 0 }
  var ready = running.filter(function(d) { return d.state === "ready" })
  var free = freeSets(s, narrow)
  if (running.length === 1 && ready.length === 1) {
    var d = ready[0], b = blockFor(s, d, ui), all = (d.session || {}).all || {}, line = all.line || []
    var gs = gpusOf(s, d.keys)
    var started = Date.parse(d.startedAt || ""), up = isNaN(started) || !ui.now ? "" : " · up " + dur((ui.now - started) / 1000)
    p.cards.push({ rows: [{ type: "title", text: d.name, sub: b.on + (b.tag ? " · vision" : "") + up, strip: b.strip }] })
    // the session's tokens over time, from the gateway's log: its running total at even steps since it started;
    // a total that has not moved yet is said, not drawn
    var cols = narrow ? 34 : 60
    var pts = line.slice(-cols), top = Math.max.apply(null, pts.concat([1]))
    var moved = pts.some(function(v) { return v !== pts[0] })
    p.cards.push({ rows: [
      { type: "label", text: "tokens this session", right: k(all.tokens || (line.length ? line[line.length - 1] : 0)) },
      moved ? { type: "bars", values: pts.map(function(v) { return v / top }), height: narrow ? 56 : 120 }
        : { type: "note", text: all.tokens ? k(all.tokens) + " tokens so far; the chart fills in as the session goes on" : "no answers yet" }] })
    var mem = gs.every(function(g) { return g.usedMiB != null }) ? Math.round(gs.reduce(function(a, g) { return a + g.usedMiB / 1024 }, 0)) + " / " : ""
    p.cards.push({ rows: [{ type: "figs", cells: [
      { k: "decode avg", v: all.decode != null ? all.decode + " tok/s" : "–" },
      { k: "prefill avg", v: all.prefill != null ? k(all.prefill) + " tok/s" : "–" },
      { k: "first token", v: all.ttft != null ? (all.ttft / 1000).toFixed(1) + " s" : "–" },
      { k: "card", v: mem + gs.reduce(function(a, g) { return a + (g.vramGb || 0) }, 0) + " GB" + (gs[0] && gs[0].tempC != null ? " · " + gs[0].tempC + "°" : "") }] }] })
    p.foot = { items: [{ label: "Open " + agentName(d.agent), action: "open|" + d.id, primary: true }, { label: "Stop", action: "stop|" + d.id }],
      link: free.length ? { label: "＋ load another on " + free.join(", "), action: "page|tree" } : null }
    return p
  }
  if (running.length) {
    var tps = ready.reduce(function(a, x) { return a + (((x.session || {}).all || {}).decode || 0) }, 0)
    var live = running.filter(function(x) { return x.state !== "error" }).length
    p.cards.push({ rows: [{ type: "title", text: live ? live + " running" : running.length === 1 ? "A model stopped" : running.length + " models stopped", sub: (tps ? tps + " tok/s together · " : "") + k((s.life || {}).days ? (s.life.days[s.life.today] || 0) : 0) + " tokens today",
      strip: { kind: ready.length ? "wave" : live ? "fill" : "flat", frac: 0.5, cols: narrow ? 12 : 18 } }] })
    running.forEach(function(x) { p.cards.push({ rows: [blockFor(s, x, ui)] }) })
    p.foot = free.length ? { items: [], link: { label: "＋ load another on " + free.join(", "), action: "page|tree" } } : null
    return p
  }
  // nothing running
  var mine = lastUsed(s), used = (s.life || {}).requests > 0
  var cardsLine = (s.kinds || []).filter(function(kd) { return !cpuKind(kd) }).map(function(kd) {
    return setName(gpusOf(s, kd.keys), narrow) + (kd.free.length === kd.keys.length ? " free" : kd.free.length ? " · " + kd.free.length + " free" : " in use")
  }).join(" · ")
  if (mine.length || used) {
    p.cards.push({ rows: [{ type: "title", text: "Nothing running", sub: mine.length ? "on this machine: " + mine.length + (mine.length === 1 ? " model" : " models") : "nothing downloaded", strip: { kind: "flat", frac: 0, cols: narrow ? 12 : 18 } }] })
    if (mine.length) p.cards.push({ rows: [{ type: "label", text: "on this machine" }].concat(mine.slice(0, narrow ? 3 : 5).map(function(h) {
      return { type: "item", label: h.r.name, tag: vision(h.r) ? "vision" : "", right: cpuKind(h.kd) ? "CPU" : setName(gpusOf(s, h.kd.keys.slice(0, h.r.cards || 1)), narrow), button: { label: "Load", action: loadAction(h) }, action: "model|" + h.r.id + "|" }
    })) })
    p.cards.push({ rows: [{ type: "label", text: narrow ? "tokens · 20 weeks" : "tokens · 30 weeks", right: k(s.total) }, { type: "calendar", weeks: narrow ? 20 : 30, cells: levels(s, narrow ? 20 : 30) }] })
    if (cardsLine) p.cards.push({ rows: [{ type: "note", text: cardsLine }] })
    p.foot = { items: mine.length ? [{ label: "Load " + mine[0].r.name, action: loadAction(mine[0]), primary: true }, { label: "Pick another", action: "page|tree" }] : [{ label: "Pick a model", action: "page|tree", primary: true }] }
    return p
  }
  // first time: the best model for each card set
  var picks = (s.kinds || []).map(function(kd) {
    var all2 = kd.keys.length > 1 ? (kd.groups || []).filter(function(r) { return !r.unfit && r.cards <= kd.keys.length }) : []
    var r = all2[0] || kd.models.filter(function(x) { return !x.unfit })[0]
    return r ? { r: r, kd: kd } : null
  }).filter(Boolean)
  var found = (s.kinds || []).filter(function(kd) { return !cpuKind(kd) }).map(function(kd) { return setName(gpusOf(s, kd.keys), narrow) }).join(" · ")
  p.cards.push({ rows: [{ type: "title", text: "Ready", sub: found ? "found " + found : "no graphics card · models run on the CPU", strip: { kind: "flat", frac: 0, cols: narrow ? 12 : 18 } }] })
  p.cards.push({ rows: [{ type: "label", text: "best for each of your cards" }].concat(picks.map(function(h) {
    return { type: "item", label: h.r.name, tag: vision(h.r) ? "vision" : "", right: cpuKind(h.kd) ? "CPU" : setName(gpusOf(s, h.kd.keys.slice(0, h.r.cards || 1)), narrow), button: { label: "Load", action: loadAction(h) }, action: "model|" + h.r.id + "|" }
  })) })
  p.foot = picks.length ? { items: [{ label: "Load " + picks[0].r.name, action: loadAction(picks[0]), primary: true }, { label: "Pick another", action: "page|tree" }] } : null
  return p
}

function settingsPage(s, ui) {
  var p = { name: "settings", header: header(ui, { label: "‹ back", action: "page|main" }, "settings"), cards: [] }
  var agent = (s.defaults || {}).agent || "", agents = s.agents || []
  var next = agents.length ? agents[(agents.indexOf(agent) + 1) % agents.length] : ""
  var up = s.updates || {}, run = deps(s).filter(function(d) { return d.state === "ready" })[0]
  var rows = [
    { type: "kv", label: "agent", value: agentName(agent), button: next && next !== agent ? { label: "Use " + agentName(next), action: "default|" + next } : null },
    { type: "kv", label: "folder", value: home((s.defaults || {}).folder) || "home" },
    { type: "kv", label: "tailscale", value: !s.tailnet ? "not running" : run ? (run.shared ? "sharing " + run.name : "share " + run.name) : "nothing running to share",
      button: s.tailnet && run ? { label: run.shared ? "Stop sharing" : "Share", action: "share|" + run.id + (run.shared ? "|off" : "") } : null },
    { type: "kv", label: "version", value: s.version || "", button: s.pluginUpdate ? { label: ui.updatingAgent === "plugin" ? "Updating…" : "Update", action: ui.updatingAgent === "plugin" ? "" : "update|plugin", primary: true } : null },
    { type: "kv", label: "usage counts", value: s.reporting === "on" ? "on · anonymous totals" : s.reporting === "off" ? "off" : "not chosen",
      button: { label: s.reporting === "on" ? "Turn off" : "Turn on", action: "set|ping|" + (s.reporting === "on" ? "off" : "on") } }
  ]
  p.cards.push({ rows: rows })
  var outdated = Object.keys(up).filter(function(a) { return up[a] && up[a].latest && up[a].latest !== up[a].current })
  if (outdated.length) p.cards.push({ rows: [{ type: "label", text: "agent updates" }].concat(outdated.map(function(a) {
    return { type: "kv", label: agentName(a), value: up[a].current + " → " + up[a].latest, button: { label: ui.updatingAgent === a ? "Updating…" : "Update", action: ui.updatingAgent === a ? "" : "update|" + a } }
  })) })
  p.foot = { items: [{ label: "Report a bug", action: "report" }], note: "opens a GitHub issue with your cards, versions and the last 50 log lines filled in; you read it before sending" }
  return p
}

// ui: { page, id, keys, closed, more, tick, now, wide, problem, notice }
function build(s, ui) {
  ui = ui || {}
  s = s || {}
  var page = ui.page || "connect"
  if (page !== "connect" && (s.readiness || {}).state && s.readiness.state !== "ready") page = "connect"
  var p = page === "tree" ? treePage(s, ui) : page === "model" ? modelPage(s, ui) : page === "settings" ? settingsPage(s, ui)
    : page === "main" ? mainPage(s, ui) : connectPage(s, ui)
  var said = ui.problem || ui.pollProblem || s.setupError
  if (said) p.cards.unshift({ alert: true, rows: [{ type: "note", alert: true, text: said }] })
  else if (ui.notice) p.cards.unshift({ rows: [{ type: "note", text: ui.notice }] })
  var running = deps(s)
  p.mark = said || running.some(function(d) { return d.state === "error" }) ? "failed" : running.some(working) ? "busy" : running.length ? "ready" : ""
  return p
}

if (typeof module !== "undefined") module.exports = { build: build, hands: hands, strip: strip, calendar: calendar, area: area, levels: levels }
