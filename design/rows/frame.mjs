// The Local AI panel in a frame: every state, as it should be built (design/SPEC.md, the issues on GitHub).
// Every popup screen has the same header band (tabs, tokens generated, today, the line, the full-screen door) and the
// same footer band (the machine in one line, logs · refresh), one surface tone, fixed heights per machine, so the top
// and the bottom never move. Between them each GPU is a two-line row; pages under gpus open in the body with a ‹ back.
// Data: the office box (2 × RTX 3090, 2 × Arc Pro B70). Temperatures, speeds and history are SAMPLE values.
import { Sheet, P, G, tw, USAGE, logo, familyOf } from "./kit.mjs"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..")

const BAND = "rgba(255,255,255,0.045)", EDGE = "rgba(255,255,255,0.08)", DRAWER = "rgb(34,34,38)"
const short = (n) => n >= 1e9 ? +(n / 1e9).toFixed(1) + "B" : n >= 1e6 ? +(n / 1e6).toFixed(1) + "M" : n >= 1e3 ? Math.round(n / 1e3) + "k" : String(n)
const LINE = USAGE.line, DAYS = USAGE.days, TOTAL = 2810000
const TIERS = [["today", "23k"], ["week", "184k"], ["month", "702k"], ["3 months", "2.1M"], ["year", "2.8M"], ["lifetime", "2.8M"]]

// a sheet of any width (the kit's is the popup's 340)
class Wide extends Sheet {
  constructor(w) { super(); this.w = w }
  svg(h) {
    const s = super.svg(h)
    return { h: s.h, svg: s.svg.replace(/width="340" height="(\d+)" viewBox="0 0 340 (\d+)"/, `width="${this.w}" height="$1" viewBox="0 0 ${this.w} $2"`) }
  }
}

// ---------------------------------------------------------------- pieces

function spark(s, x, y, w, h, v, tone) {
  const n = v.length, bw = w / n, mx = Math.max(...v, 1)
  v.forEach((t, i) => { const bh = Math.max(t ? 2 : 1, t / mx * h); s.rect(x + i * bw + .5, y + h - bh, Math.max(1, bw - 1.5), bh, t ? tone : P.rule) })
}
function bar(s, x, y, w, frac, tone) { s.rect(x, y, w, 3, P.rule); if (frac != null) s.rect(x, y, w * frac, 3, tone) }
function cumulative(s, x, y, w, h, pts) {
  if (!pts) { s.line(x, y + h - .5, x + w, y + h - .5, { stroke: P.rule }); return }
  const mx = Math.max(...pts), xy = pts.map((v, i) => [x + i / (pts.length - 1) * w, y + h - v / mx * h * .92])
  s.path("M" + xy.map((p) => p.join(",")).join("L") + `L${x + w},${y + h}L${x},${y + h}Z`, { fill: "rgba(221,221,221,0.06)" })
  s.path("M" + xy.map((p) => p.join(",")).join("L"), { stroke: P.value, sw: 1.4 })
}
function button(s, x, y, label, w) {
  w = w || tw(label, 12) + 26
  s.parts.push(`<rect x="${x}" y="${y}" width="${w}" height="26" rx="3" fill="${P.ink}"/>`)
  s.text(x + w / 2, y + 17, label, { size: 12, fill: P.bg, anchor: "middle" })
  return w
}
function days(s, x, y, w, h, pick = DAYS.length - 2) {
  const bw = w / DAYS.length, mx = Math.max(...DAYS.map((d) => d.tokens))
  DAYS.forEach((d, i) => { const bh = d.tokens / mx * h; if (bh) s.rect(x + i * bw + .5, y + h - bh, Math.max(1, bw - 2), bh, i === pick ? P.ink : P.v(.28)) })
  s.line(x, y + h + .5, x + w, y + h + .5, { stroke: P.rule })
  s.text(x, y + h + 16, DAYS[0].label.replace(/^\S+ /, ""), { size: 10, fill: P.label })
  s.text(x + w, y + h + 16, DAYS[pick].label + "  " + short(DAYS[pick].tokens), { size: 10, fill: P.ink, anchor: "end" })
}
// The calendar: a column a week, a row a weekday (Mon at the top), the last n weeks ending today; each day shaded in five
// steps by its tokens against the busiest day; the month above its first week; today outlined; a hovered day is said
// under it. SAMPLE history: the last 4 weeks are the fixture's days, older weeks a fixed pattern.
const TODAY = new Date(2026, 9, 6)
function history(weeks) {
  const n = weeks * 7 - (6 - ((TODAY.getDay() + 6) % 7)), out = []
  for (let i = 0; i < n; i++) {
    const back = n - 1 - i, fx = DAYS[DAYS.length - 1 - back]
    out.push(fx ? fx.tokens : ((i * 7919) % 13 < 4 ? 0 : ((i * 104729) % 97) * 600))
  }
  return out
}
function calendar(s, x, y, weeks, cell, gap, o = {}) {
  const v = history(weeks), mx = Math.max(...v), L = [0.06, 0.22, 0.42, 0.66, 0.95], step = cell + gap
  const start = new Date(TODAY); start.setDate(start.getDate() - (v.length - 1))
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  let last = -1
  for (let w = 0; w < weeks; w++) {
    const d = new Date(start); d.setDate(d.getDate() + w * 7)
    if (d.getMonth() !== last && w < weeks - 2) s.text(x + w * step, y, MON[d.getMonth()], { size: o.label || 9, fill: P.label })
    last = d.getMonth()
  }
  const gy = y + 8
  ;["M", "", "W", "", "F", "", ""].forEach((k, r) => k && o.days && s.text(x - 12, gy + r * step + cell - 1, k, { size: 8, fill: P.label }))
  v.forEach((t, i) => {
    const w = Math.floor(i / 7), r = i % 7, lvl = t ? Math.min(4, Math.ceil(t / mx * 4)) : 0
    s.parts.push(`<rect x="${x + w * step}" y="${gy + r * step}" width="${cell}" height="${cell}" rx="1.5" fill="rgba(221,221,221,${L[lvl]})"${i === v.length - 1 ? ` stroke="${P.ink}" stroke-width="1"` : ""}/>`)
  })
  const by = gy + 7 * step + 14
  s.text(x, by, o.said || "Mon Oct 5  ·  23k tokens", { size: o.label || 10, fill: P.value })
  s.text(x + weeks * step - gap, by, "less ▫ ◻ ◼ more", { size: 9, fill: P.label, anchor: "end" })
  return by
}

const agentMark = (name) => {
  const f = { claude: "claude.svg", codex: "codex.svg", opencode: "opencode.svg", crush: "crush.png", hermes: "hermes.svg", omp: "omp.svg", copilot: "copilot.svg" }[name]
  if (!f) return null
  return `data:${f.endsWith(".png") ? "image/png" : "image/svg+xml"};base64,${fs.readFileSync(path.join(ROOT, "agents", f)).toString("base64")}`
}

// ---------------------------------------------------------------- the popup frame

const PW = 340, HEAD = 156, FOOT = 44, BODY = 600
// one machine, one body height: its tallest screen's, so nothing below the header ever moves
function frame(tab, o = {}) {
  const body = o.body || BODY, H = HEAD + body + FOOT, s = new Wide(PW)
  s.H = H
  s.rect(0, 0, PW, HEAD, BAND); s.line(0, HEAD + .5, PW, HEAD + .5, { stroke: EDGE })
  s.rect(0, H - FOOT, PW, FOOT, BAND); s.line(0, H - FOOT - .5, PW, H - FOOT - .5, { stroke: EDGE })
  let x = G
  for (const t of ["home", "gpus"]) {
    s.text(x, 32, t, { size: 13, fill: t === tab ? P.ink : P.label })
    if (t === tab) s.line(x, 40, x + tw(t, 13), 40, { stroke: P.ink, sw: 1.5 })
    x += tw(t, 13) + 26
  }
  s.text(PW - G, 32, "󰊓", { size: 14, fill: P.label, anchor: "end" })
  if (o.empty) {
    s.text(G, 76, "0", { size: 26, fill: P.label }); s.text(G + tw("0", 26) + 8, 76, "tokens generated", { size: 12, fill: P.label })
    cumulative(s, G, 92, PW - 2 * G, 46, null)
  } else {
    s.text(G, 76, short(TOTAL), { size: 26, fill: P.ink }); s.text(G + tw(short(TOTAL), 26) + 8, 76, "tokens generated", { size: 12, fill: P.label })
    s.text(PW - G, 76, "today 23k", { size: 11, fill: P.label, anchor: "end" })
    cumulative(s, G, 92, PW - 2 * G, 46, LINE)
  }
  s.text(G, H - 17, o.foot ?? "4 GPUs · 2 models running", { size: 11, fill: P.label })
  s.text(PW - G, H - 17, "logs · refresh", { size: 11, fill: P.label, anchor: "end" })
  return s
}
const done = (s) => s.svg(s.H)

// A GPU row. Closed: the mark, the name, what it is doing on the right, then the card's facts and a memory bar the
// width of the row. Click opens it in place (a dropdown, no animation): the details on a raised surface, and its
// buttons inside. Running: speed, prefill, first token, today, total, up; its agent, folder, share; [Open pi] Stop · logs.
// Free: what Run starts, as fast · medium · smart with their speeds, its format, context and size; [Run medium] all models ›.
const RAISED = "rgba(255,255,255,0.035)"
// every model for a card, best first: the three choices tagged, the picked one highlighted, on disk / download / what it
// needs under each name, one this machine cannot hold dim with its reason; ro: shown but not runnable (the card is held)
const MODELS = [["fast", "Qwen3.6-35B-A3B", 310, "on disk"], ["medium", "Qwen3.8-27B", 129, "on disk"], ["smart", "Qwen3.8-Flash-Next", 51, "+75 GB RAM"],
  ["", "Gemma 4 26B A4B", 96, "on disk"], ["", "Qwen3.5-9B", 113, "14 GB download"], ["", "DeepSeek-V4.1-Flash", 18, "needs 228 GB RAM", true]]
function models(s, x, y, w, pick = "Qwen3.8-27B", ro = false) {
  MODELS.forEach(([tag, n, v, note, unfit], i) => {
    const on = n === pick && !ro, ry = y + i * 30, tone = unfit || ro ? P.v(.4) : on ? P.ink : P.value
    if (on) s.parts.push(`<rect x="${x - 6}" y="${ry}" width="${w + 6}" height="28" rx="3" fill="rgba(255,255,255,0.07)"/>`)
    s.text(x, ry + 12, tag, { size: 10, fill: on ? P.ink : P.label })
    logo(s, x + 46, ry + 2, 12, familyOf(n), tone); s.text(x + 64, ry + 12, n, { size: 12, fill: tone })
    s.text(x + 64, ry + 24, note, { size: 9, fill: unfit ? P.v(.35) : P.label })
    s.text(PW - G, ry + 12, v + " tok/s", { size: 10, fill: unfit || ro ? P.v(.35) : P.label, anchor: "end" })
  })
  return y + MODELS.length * 30
}
function row(s, y, r, open = false) {
  const top = y + 20, sub = y + 38
  const dim = r.kind === "dim", tone = dim ? P.v(.35) : r.kind === "stopped" ? P.label : P.ink
  if (open) s.parts.push(`<rect x="8" y="${y + 2}" width="${PW - 16}" height="${r.openH}" rx="6" fill="${RAISED}" stroke="${EDGE}"/>`)
  const model = r.kind === "run" || r.kind === "busy" || r.kind === "stopped"
  if (model) logo(s, G, top - 12, 15, familyOf(r.model), tone)
  else if (r.maker === "cpu") s.text(G + 7, top + 1, "\u{f061a}", { size: 15, fill: dim ? tone : P.value, anchor: "middle" })
  else logo(s, G, top - 12, 15, r.maker, dim ? tone : P.value)
  s.text(G + 24, top, model ? r.model : r.name, { size: 13, fill: model ? tone : dim ? tone : P.value })
  const right = r.kind === "run" ? r.tps + " tok/s" : r.kind === "busy" ? r.step : r.kind === "stopped" ? "stopped" : dim ? r.why || "in use" : "free"
  s.text(PW - G - 14, top, right, { size: 12, fill: r.kind === "run" ? P.value : P.label, anchor: "end" })
  s.text(PW - G, top, open ? "⌃" : "⌄", { size: 11, fill: P.label, anchor: "end" })
  if (r.kind === "run") s.dot(G + 24 + tw(r.model, 13) + 9, top - 4, 2.5, P.ink)
  s.text(G + 24, sub, r.facts, { size: 11, fill: dim ? P.v(.3) : P.label })
  bar(s, G + 24, sub + 9, PW - 2 * G - 24, r.kind === "busy" ? r.pct : r.used, r.kind === "busy" ? P.ink : dim ? P.v(.25) : P.v(.55))
  let y2 = y + 62
  if (!open) return y2
  // ---- opened
  const x = G + 24, w = PW - G - x
  if (r.kind === "run") {
    const cells = [["88", "tok/s"], ["1.9k", "prefill/s"], ["0.4 s", "first token"], ["23k", "today"], ["1.9M", "total"], ["3:12", "up"]]
    cells.forEach(([v, k], i) => { const cx = x + (i % 3) * (w / 3), cy = y2 + 8 + Math.floor(i / 3) * 38; s.text(cx, cy, v, { size: 14, fill: P.ink }); s.text(cx, cy + 14, k, { size: 10, fill: P.label }) })
    y2 += 82
    spark(s, x, y2, w, 18, r.spark, P.v(.5)); s.text(x, y2 + 32, "the last hour", { size: 9, fill: P.label }); y2 += 44
    for (const [k, v] of [["model", "change ›"], ["agent", "pi ›"], ["folder", "~/Work ›"], ["share", "off · turn on"]]) { y2 += 20; s.text(x, y2, k, { size: 12, fill: P.label }); s.text(PW - G, y2, v, { size: 12, fill: P.value, anchor: "end" }) }
    y2 += 16; const bw = button(s, x, y2, "Open pi"); s.text(x + bw + 14, y2 + 17, "Stop  ·  logs", { size: 12, fill: P.label }); y2 += 44
  } else if (r.kind === "free") {
    s.text(x, y2 + 6, "model", { size: 10, fill: P.label }); y2 += 12
    y2 = models(s, x, y2, w) + 8
    const bw = button(s, x, y2, "Run Qwen3.8-27B"); s.text(x + bw + 14, y2 + 17, "refresh", { size: 12, fill: P.label }); y2 += 44
  } else if (r.kind === "dim") {
    // held: what holds it, then what it could run, readable but not runnable until it is free
    s.text(x, y2 + 6, r.held, { size: 11, fill: P.value }); s.text(x, y2 + 22, r.heldWhy, { size: 10, fill: P.label }); y2 += 36
    s.text(x, y2 + 6, "runs here when free", { size: 10, fill: P.label }); y2 += 12
    y2 = models(s, x, y2, w, "", true) + 8
  } else if (r.kind === "stopped") {
    s.text(x, y2 + 8, "stopped 2 min ago: needs 75 GB of RAM, 41 free", { size: 10, fill: P.label }); y2 += 20
    const bw = button(s, x, y2, "Run again"); s.text(x + bw + 14, y2 + 17, "dismiss  ·  logs", { size: 12, fill: P.label }); y2 += 44
  }
  return y2 + 6
}
const ROWS = {
  q27: { kind: "run", model: "Qwen3.8-27B", tps: 88, facts: "RTX 3090  ·  21 / 24 GB  ·  62°  ·  87%", used: 21.2 / 24, openH: 338, spark: [70, 82, 91, 88, 64, 0, 0, 77, 90, 93, 86, 88, 84, 90, 91, 0, 0, 0, 72, 88, 92, 89, 87, 88] },
  q35: { kind: "run", model: "Qwen3.6-35B-A3B", tps: 115, facts: "2 × Arc Pro B70  ·  64 GB  ·  57°  ·  64%", used: null, openH: 318, spark: [100, 112, 118, 0, 0, 0, 104, 117, 120, 115, 111, 115] },
  free: { kind: "free", maker: "hw-nvidia", name: "RTX 3090", facts: "24 GB free  ·  38°  ·  idle", used: .03, openH: 300 },
  pair: { kind: "dim", maker: "hw-nvidia", name: "2 × RTX 3090", facts: "48 GB  ·  needs both cards free", used: .45 },
  held: { kind: "dim", maker: "hw-nvidia", name: "RTX 3090", why: "in use", facts: "15.5 / 24 GB  ·  44°  ·  92%", used: 15.5 / 24, openH: 318,
    held: "held by another program", heldWhy: "VLLM::EngineCore in container dsv41-lab" },
}
function gpus(rows, o = {}) {
  const s = frame("gpus", o)
  let y = HEAD + 6
  rows.forEach((r, i) => {
    if (r === "rule") { s.line(G, y + 4, PW - G, y + 4, { stroke: P.rule }); y += 8; return }
    y = row(s, y, r, i === o.open)
  })
  return done(s)
}
const office = (o = {}) => gpus([ROWS.q27, ROWS.q35, ROWS.free, "rule", ROWS.pair], o)

// the body's own pieces for pages and messages
function message(s, head, lines, btn, y = HEAD + 40) {
  s.text(G, y, head, { size: 16, fill: P.ink }); y += 22
  for (const l of lines) { s.text(G, y, l, { size: 12, fill: P.label }); y += 18 }
  if (btn) button(s, G, y + 14, btn)
  return y + 54
}
function back(s, label, sub) {
  s.text(G, HEAD + 36, "‹ " + label, { size: 15, fill: P.ink })
  if (sub) s.text(G + tw("‹ " + label, 15) + 10, HEAD + 36, sub, { size: 11, fill: P.label })
  return HEAD + 56
}

// ---------------------------------------------------------------- the states

const S = {}
// not ready: what is wrong and the one fix; the header stays, empty
S["not-ready-setup"] = () => {
  const s = frame("gpus", { empty: true, foot: "4 GPUs found · not set up" })
  let y = message(s, "Set up Local AI", ["Docker access and the NVIDIA toolkit,", "once. It asks for your password in", "a terminal."], "Set up")
  s.text(G, y + 8, "found", { size: 10, fill: P.label }); y += 20
  for (const [m, n] of [["hw-nvidia", "RTX 3090"], ["hw-nvidia", "RTX 3090"], ["hw-intel", "Arc Pro B70"], ["hw-intel", "Arc Pro B70"]]) { logo(s, G, y + 6, 13, m, P.v(.5)); s.text(G + 22, y + 17, n, { size: 12, fill: P.v(.5) }); y += 26 }
  return done(s)
}
S["not-ready-docker"] = () => { const s = frame("gpus", { foot: "4 GPUs · Docker stopped" }); message(s, "Docker isn't running", ["Models run in Docker. Start it and", "Local AI picks up where it was."], "Start Docker"); return done(s) }
S["not-ready-old"] = () => { const s = frame("gpus", { empty: true, foot: "4 GPUs · Omarchy too old" }); message(s, "Omarchy is too old for Local AI", ["Local AI needs Omarchy's Sudoless", "Docker, which came with a newer", "Omarchy."], "Update Omarchy"); return done(s) }
S["no-supported-gpu"] = () => { const s = frame("gpus", { empty: true, foot: "1 GPU · none tested yet" }); message(s, "No tested model for RX 6600 yet", ["The list grows as cards are tested."], "See supported cards"); return done(s) }
S["home"] = () => {
  const s = frame("home"); let y = HEAD + 34
  TIERS.forEach(([k, v], i) => {
    const cx = G + (i % 3) * ((PW - 2 * G) / 3), cy = y + Math.floor(i / 3) * 48
    s.text(cx, cy, v, { size: 17, fill: i === 0 ? P.ink : P.value }); s.text(cx, cy + 16, k, { size: 10, fill: P.label })
  })
  y += 112
  calendar(s, G + 12, y, 25, 9, 2, { days: true })
  return done(s)
}
S["home-first"] = () => { const s = frame("home", { empty: true, foot: "4 GPUs · nothing run yet" }); message(s, "No tokens yet", ["Run a model on gpus and they add up", "here: today, this week, all time."]); return done(s) }
S["gpus"] = () => office()
S["gpus-open-running"] = () => office({ open: 0 })
S["gpus-open-free"] = () => office({ open: 2 })
S["starting-download"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "busy", model: "Qwen3.8-27B", step: "downloading 42%", pct: .42, facts: "RTX 3090  ·  6.1 of 14.5 GB  ·  12 MB/s" }, "rule", ROWS.pair])
S["starting-load"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "busy", model: "Qwen3.8-27B", step: "loading 80%", pct: .8, facts: "RTX 3090  ·  checking it answers" }, "rule", ROWS.pair])
S["gpus-open-in-use"] = () => gpus([ROWS.q35, ROWS.held, ROWS.free], { open: 1 })
S["stopped"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "stopped", model: "Qwen3.8-Flash-Next", facts: "RTX 3090  ·  24 GB free  ·  40°", used: .03, openH: 104 }, "rule", ROWS.pair], { open: 2 })
S["notification"] = () => {
  const s = new Wide(PW), x = 16, w = PW - 32, top = 16
  s.parts.push(`<rect x="${x}" y="${top}" width="${w}" height="78" rx="6" fill="rgb(28,28,31)" stroke="rgba(255,255,255,0.18)"/>`)
  s.text(x + 16, top + 24, "󰧑  Local AI", { size: 11, fill: P.label })
  s.text(x + 16, top + 44, "Qwen3.8-Flash-Next stopped", { size: 13, fill: P.ink })
  s.text(x + 16, top + 63, "needs 75 GB of RAM, 41 free  ·  click: logs", { size: 11, fill: P.value })
  return s.svg(top + 78 + 16)
}
// config: one list, the three choices first, then every other model; on disk and what it needs under each name
function config(hoverDisk) {
  const s = frame("gpus"); let y = back(s, "RTX 3090", "24 GB free")
  s.text(PW - G - 40, y, "tok/s", { size: 9, fill: P.label, anchor: "end" }); s.text(PW - G, y, "AA", { size: 9, fill: P.label, anchor: "end" }); y += 4
  const line = (tag, m, tps, aa, note, o = {}) => {
    const top = y + 18, tone = o.unfit ? P.v(.35) : o.on ? P.ink : P.value
    if (o.on) s.dot(G - 10, top - 4, 3, P.ink)
    s.text(G, top, tag, { size: 11, fill: o.on ? P.ink : P.label })
    const x = G + 56
    logo(s, x, top - 11, 13, familyOf(m), tone); s.text(x + 20, top, m, { size: 12, fill: tone })
    s.text(PW - G - 40, top, String(tps), { size: 12, fill: tone, anchor: "end" }); s.text(PW - G, top, String(aa), { size: 12, fill: tone, anchor: "end" })
    s.text(x + 20, top + 15, note, { size: 10, fill: o.unfit ? P.v(.35) : P.label })
    if (o.drawer) {
      const dx = PW - 166
      s.parts.push(`<rect x="${dx}" y="${y + 3}" width="166" height="34" rx="4" fill="${DRAWER}"/>`)
      const bw = button(s, dx + 12, y + 7, "Run", 62); s.text(dx + 12 + bw + 12, top, "remove", { size: 12, fill: P.label })
    }
    y += 40
  }
  line("fast", "Qwen3.6-35B-A3B", 310, 18, "on disk"); line("medium", "Qwen3.8-27B", 129, 28, "on disk", { on: true }); line("smart", "Qwen3.8-Flash-Next", 51, 40, "+75 GB RAM")
  s.line(G, y + 4, PW - G, y + 4, { stroke: P.rule }); y += 8
  line("", "Gemma 4 26B A4B", 96, 17, "on disk · 20 GB", { drawer: hoverDisk }); line("", "Qwen3.5-9B", 113, 11, "14 GB download"); line("", "DeepSeek-V4.1-Flash", 18, 40, "needs 228 GB RAM, 96 free", { unfit: true })
  button(s, G, y + 12, "Run medium")
  return done(s)
}
S["config"] = () => config(false)
S["config-hover-on-disk"] = () => config(true)
S["more"] = () => {
  const s = frame("gpus"); let y = back(s, "Qwen3.8-27B", "on RTX 3090")
  for (const [k, v] of [["agent", "pi ›"], ["folder", "~/Work ›"], ["share", "off · turn on"], ["logs", "›"]]) { y += 30; s.text(G, y, k, { size: 13, fill: P.label }); s.text(PW - G, y, v, { size: 13, fill: P.value, anchor: "end" }) }
  return done(s)
}
S["agent"] = () => {
  const s = frame("gpus"); let y = back(s, "agent", "Qwen3.8-27B")
  s.parts.push(`<defs><filter id="gray"><feColorMatrix type="saturate" values="0"/></filter></defs>`)
  for (const [a, name, note] of [["pi", "pi", "default"], ["claude", "Claude Code", ""], ["codex", "Codex", ""], ["opencode", "OpenCode", ""], ["crush", "Crush", ""], ["hermes", "Hermes", ""], ["omp", "oh-my-pi", ""], ["copilot", "Copilot", "install ›"]]) {
    y += 30; const on = a === "pi", off = note === "install ›", m = agentMark(a)
    if (on) s.dot(G - 10, y - 4, 3, P.ink)
    if (m) s.parts.push(`<image x="${G}" y="${y - 12}" width="15" height="15" href="${m}" filter="url(#gray)" opacity="${off ? .4 : .9}"/>`)
    else s.text(G + 7, y, "π", { size: 13, fill: P.ink, anchor: "middle" })
    s.text(G + 24, y, name, { size: 13, fill: on ? P.ink : off ? P.v(.4) : P.value })
    if (note) s.text(PW - G, y, note, { size: 10, fill: P.label, anchor: "end" })
  }
  s.text(G, y + 32, "make pi the default for new models", { size: 11, fill: P.label })
  return done(s)
}
S["folder"] = () => {
  const s = frame("gpus"); let y = back(s, "folder", "pi opens in")
  for (const f of ["~/Work", "~/projects/local-ai", "~/notes", "~", "choose another…"]) {
    y += 30; if (f === "~/Work") s.dot(G - 10, y - 4, 3, P.ink)
    s.text(G, y, f, { size: 13, fill: f === "~/Work" ? P.ink : f.endsWith("…") ? P.label : P.value })
  }
  return done(s)
}
S["share"] = () => {
  const s = frame("gpus"); let y = back(s, "share", "on")
  for (const [v, l] of [["office.tail1234.ts.net:12434", "address · copy"], ["sk-•••••••••••••••••", "key · copy"]]) { y += 30; s.text(G, y, v, { size: 13, fill: P.ink }); s.text(G, y + 18, l, { size: 11, fill: P.label }); y += 24 }
  button(s, G, y + 24, "Stop sharing")
  return done(s)
}
S["one-gpu"] = () => gpus([ROWS.q27], { body: 340, open: 0, foot: "1 GPU · 1 model running" })
S["cpu-only"] = () => gpus([{ kind: "run", model: "LFM2.5-2.6B", tps: 38, facts: "CPU  ·  4 GB of RAM  ·  12 threads", used: .06, spark: [30, 36, 38, 0, 37, 39, 38, 36] },
  { kind: "free", maker: "cpu", name: "CPU", facts: "61 of 64 GB RAM free  ·  52°", used: .05 }], { body: 236, foot: "CPU only · 1 model running" })

// ---------------------------------------------------------------- full screen

const FW = 1280, FH = 760, FHEAD = 220, FFOOT = 52, X = 40
function full(tab) {
  const s = new Wide(FW)
  s.rect(0, 0, FW, FHEAD, BAND); s.line(0, FHEAD + .5, FW, FHEAD + .5, { stroke: EDGE })
  s.rect(0, FH - FFOOT, FW, FFOOT, BAND); s.line(0, FH - FFOOT - .5, FW, FH - FFOOT - .5, { stroke: EDGE })
  s.text(X, 40, "Local AI", { size: 15, fill: P.ink })
  let x = X + 130
  for (const t of ["home", "gpus"]) { s.text(x, 40, t, { size: 13, fill: t === tab ? P.ink : P.label }); if (t === tab) s.line(x, 48, x + tw(t, 13), 48, { stroke: P.ink, sw: 1.5 }); x += tw(t, 13) + 26 }
  s.text(FW - X, 40, "󰊔  esc", { size: 12, fill: P.label, anchor: "end" })
  s.text(X, 100, short(TOTAL), { size: 40, fill: P.ink }); s.text(X + tw(short(TOTAL), 40) + 12, 100, "tokens generated", { size: 14, fill: P.label })
  cumulative(s, X, 120, 760, 76, LINE)
  TIERS.forEach(([k, v], i) => {
    const cx = 860 + (i % 3) * 130, cy = 96 + Math.floor(i / 3) * 62
    s.text(cx, cy, v, { size: 22, fill: i === 0 ? P.ink : P.value }); s.text(cx, cy + 20, k, { size: 11, fill: P.label })
  })
  s.text(X, FH - 20, "office  ·  4 GPUs  ·  2 models running  ·  412 GB RAM free  ·  Local AI 7.1.0", { size: 12, fill: P.label })
  s.text(FW - X, FH - 20, "logs  ·  refresh models", { size: 12, fill: P.label, anchor: "end" })
  return s
}
S["full-gpus"] = () => {
  const s = full("gpus"), ty = FHEAD + 36, tw4 = (FW - 2 * X - 3 * 20) / 4, th = 250
  const tile = (i, span, c, run) => {
    const tx = X + i * (tw4 + 20), w = tw4 * span + 20 * (span - 1), ix = tx + 20
    s.parts.push(`<rect x="${tx}" y="${ty}" width="${w}" height="${th}" rx="6" fill="${BAND}" stroke="${EDGE}"/>`)
    logo(s, ix, ty + 18, 16, c.maker, P.value); s.text(ix + 26, ty + 31, c.name, { size: 13, fill: P.value })
    s.text(tx + w - 20, ty + 31, c.temp, { size: 12, fill: P.label, anchor: "end" })
    bar(s, ix, ty + 48, w - 40, c.used, P.value)
    s.text(ix, ty + 68, c.mem, { size: 11, fill: P.label }); s.text(tx + w - 20, ty + 68, c.util, { size: 11, fill: P.label, anchor: "end" })
    if (run) {
      logo(s, ix, ty + 98, 20, "qwen", P.ink); s.text(ix + 30, ty + 114, run.model, { size: 17, fill: P.ink })
      s.text(ix, ty + 150, String(run.tps), { size: 30, fill: P.ink }); s.text(ix + tw(String(run.tps), 30) + 8, ty + 150, "tok/s", { size: 12, fill: P.label })
      spark(s, ix, ty + 166, w - 40, 26, run.spark, P.v(.55))
      const bw = button(s, ix, ty + th - 44, "Open pi")
      s.text(ix + bw + 16, ty + th - 27, span > 1 ? "stop  ·  agent  ·  folder  ·  share" : "stop  ·  ⋯", { size: 12, fill: P.label })
    } else {
      s.text(ix, ty + 114, "free", { size: 17, fill: P.label }); s.text(ix, ty + 140, "Run starts", { size: 11, fill: P.label })
      logo(s, ix, ty + 150, 14, "qwen", P.value); s.text(ix + 22, ty + 162, "Qwen3.8-27B", { size: 13, fill: P.value })
      s.text(ix, ty + 182, "fast 310 · medium 129 · smart 51 tok/s", { size: 10, fill: P.label })
      const bw = button(s, ix, ty + th - 44, "Run"); s.text(ix + bw + 16, ty + th - 27, "config", { size: 12, fill: P.label })
    }
  }
  tile(0, 1, { maker: "hw-nvidia", name: "RTX 3090", temp: "62°", used: 21.2 / 24, mem: "21.2 / 24 GB", util: "87% busy" }, ROWS.q27)
  tile(1, 1, { maker: "hw-nvidia", name: "RTX 3090", temp: "38°", used: .6 / 24, mem: "0.6 / 24 GB", util: "idle" })
  tile(2, 2, { maker: "hw-intel", name: "2 × Arc Pro B70", temp: "55° / 57°", used: null, mem: "64 GB", util: "64% busy" }, ROWS.q35)
  const by = ty + th + 44
  calendar(s, X + 16, by - 14, 52, 12, 3, { days: true, label: 11 })
  return s.svg(FH)
}
S["full-home"] = () => {
  const s = full("home"), y = FHEAD + 50
  calendar(s, X + 16, y, 52, 12, 3, { days: true, label: 11, said: "Mon Oct 5  ·  23k tokens  ·  412 requests  ·  Qwen3.8-27B, Qwen3.6-35B-A3B" })
  const tx = 860
  s.text(tx, y, "by model", { size: 11, fill: P.label })
  ;[["Qwen3.8-27B", "1.9M", "88 tok/s", "RTX 3090"], ["Qwen3.6-35B-A3B", "820k", "115 tok/s", "2 × B70"], ["LFM2.5-2.6B", "61k", "38 tok/s", "CPU"]].forEach(([m, t, v, c], i) => {
    const ry = y + 30 + i * 52
    logo(s, tx, ry - 12, 15, familyOf(m), P.value); s.text(tx + 24, ry, m, { size: 13, fill: P.value }); s.text(FW - X, ry, t, { size: 13, fill: P.ink, anchor: "end" })
    s.text(tx + 24, ry + 18, v + "  ·  " + c, { size: 11, fill: P.label })
  })
  // by card: what each card generated, how long it ran, its energy (from the card's own counter) and the hottest it got
  const cy = y + 200
  s.text(X, cy, "by card", { size: 11, fill: P.label })
  ;["card", "tokens", "running", "energy", "hottest"].forEach((h, i) => s.text(X + [0, 340, 480, 620, 760][i], cy + 26, h, { size: 10, fill: P.label, anchor: i ? "end" : "start" }))
  ;[["hw-nvidia", "RTX 3090", "1.9M", "412 h", "96 kWh", "71°"], ["hw-nvidia", "RTX 3090", "140k", "38 h", "8 kWh", "64°"], ["hw-intel", "Arc Pro B70", "410k", "210 h", "31 kWh", "66°"], ["hw-intel", "Arc Pro B70", "410k", "210 h", "30 kWh", "68°"]].forEach((r, i) => {
    const ry = cy + 52 + i * 28
    logo(s, X, ry - 11, 13, r[0], P.value); s.text(X + 22, ry, r[1], { size: 12, fill: P.value })
    r.slice(2).forEach((v, j) => s.text(X + [340, 480, 620, 760][j], ry, v, { size: 12, fill: j ? P.label : P.ink, anchor: "end" }))
  })
  return s.svg(FH)
}

export const SCREENS = S
export const ROW = { id: "frame", title: "The panel in a frame", primitive: "header and footer bands; two-line GPU rows; full screen",
  idea: "The top and the bottom never move.", screens: Object.entries(SCREENS).map(([id, draw]) => ({ id, title: id, draw })) }
