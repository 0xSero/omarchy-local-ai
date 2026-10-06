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
const agentMark = (name) => {
  const f = { claude: "claude.svg", codex: "codex.svg", opencode: "opencode.svg", crush: "crush.png", hermes: "hermes.svg", omp: "omp.svg", copilot: "copilot.svg" }[name]
  if (!f) return null
  return `data:${f.endsWith(".png") ? "image/png" : "image/svg+xml"};base64,${fs.readFileSync(path.join(ROOT, "agents", f)).toString("base64")}`
}

// ---------------------------------------------------------------- the popup frame

const PW = 340, HEAD = 156, FOOT = 44, BODY = 372
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

// A GPU row, two lines: what is on it (or the card), then the card's facts. kind: run | free | busy | stopped | dim.
// open: its drawer, slid in from the right (one button, quiet links); at rest a 4 px sliver says it is there.
function row(s, y, r, open = false) {
  const top = y + 18, sub = y + 36
  const tone = r.kind === "dim" ? P.v(.35) : r.kind === "stopped" ? P.label : P.ink
  if (r.kind === "run" || r.kind === "busy" || r.kind === "stopped") {
    logo(s, G, top - 12, 15, familyOf(r.model), tone)
    s.text(G + 24, top, open && r.model.length > 13 ? r.model.slice(0, 12) + "…" : r.model, { size: 13, fill: tone })
    if (r.kind === "run" && !open) {
      const sp = r.tps + " tok/s"
      spark(s, PW - G - 12 - tw(sp, 12) - 58, top - 11, 48, 12, r.spark, P.v(.55))
      s.text(PW - G - 12, top, sp, { size: 12, fill: P.value, anchor: "end" }); s.dot(PW - G - 3, top - 4, 3, P.ink)
    }
    if (r.kind === "busy") s.text(PW - G, top, r.step, { size: 12, fill: P.label, anchor: "end" })
    if (r.kind === "stopped" && !open) s.text(PW - G, top, "stopped", { size: 12, fill: P.label, anchor: "end" })
    s.text(G + 24, sub, open ? r.on.split("  ·  ")[0] : r.on, { size: 11, fill: P.label })
    if (r.kind === "busy") bar(s, G + 24, sub + 8, PW - 2 * G - 24, r.pct, P.ink)
  } else {
    const t = r.kind === "dim" ? tone : open ? P.ink : P.value
    if (r.maker === "cpu") s.text(G + 7, top + 1, "\u{f061a}", { size: 15, fill: t, anchor: "middle" })
    else logo(s, G, top - 12, 15, open && r.next ? familyOf(r.next) : r.maker, t)
    s.text(G + 24, top, open && r.next ? r.next : r.name, { size: 13, fill: t })
    if (!open) s.text(PW - G, top, r.kind === "dim" ? r.why || "in use" : "free", { size: 12, fill: r.kind === "dim" ? tone : P.label, anchor: "end" })
    s.text(G + 24, sub, open && r.next ? "on " + r.name : r.facts, { size: 11, fill: r.kind === "dim" ? P.v(.3) : P.label })
    if (!open && r.kind === "free") bar(s, PW - G - 60, sub - 4, 60, r.used, P.value)
  }
  const acts = r.kind === "run" ? ["Open pi", "stop  ⋯"] : r.kind === "free" ? ["Run", "config"] : r.kind === "stopped" ? ["Run again", "dismiss"] : r.kind === "busy" ? [null, "stop"] : null
  if (acts && open) {
    const dw = 176, dx = PW - dw
    s.parts.push(`<rect x="${dx}" y="${y + 6}" width="${dw}" height="40" rx="4" fill="${DRAWER}"/>`)
    s.line(dx, y + 6, dx, y + 46, { stroke: EDGE })
    const bw = acts[0] ? button(s, dx + 14, y + 13, acts[0], 76) : -12
    s.text(dx + 14 + bw + 12, y + 30, acts[1], { size: 12, fill: P.label })
  } else if (acts) s.parts.push(`<rect x="${PW - 4}" y="${y + 10}" width="4" height="32" rx="1" fill="${DRAWER}"/>`)
  return y + 52
}
const ROWS = {
  q27: { kind: "run", model: "Qwen3.8-27B", tps: 88, on: "on RTX 3090  ·  62°  ·  87%", spark: [70, 82, 91, 88, 64, 0, 0, 77, 90, 93, 86, 88] },
  q35: { kind: "run", model: "Qwen3.6-35B-A3B", tps: 115, on: "2 × Arc Pro B70  ·  57°  ·  64%", spark: [100, 112, 118, 0, 0, 0, 104, 117, 120, 115, 111, 115] },
  free: { kind: "free", maker: "hw-nvidia", name: "RTX 3090", facts: "24 GB  ·  38°", used: .03, next: "Qwen3.8-27B" },
  pair: { kind: "dim", maker: "hw-nvidia", name: "2 × RTX 3090", facts: "48 GB  ·  needs both cards" },
}
function gpus(rows, o = {}) {
  const s = frame("gpus", o)
  let y = HEAD + 10
  rows.forEach((r, i) => {
    if (r === "rule") { s.line(G, y + 6, PW - G, y + 6, { stroke: P.rule }); y += 12; return }
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
  y += 116; s.text(G, y, "per day", { size: 10, fill: P.label })
  days(s, G, y + 10, PW - 2 * G, 90)
  return done(s)
}
S["home-first"] = () => { const s = frame("home", { empty: true, foot: "4 GPUs · nothing run yet" }); message(s, "No tokens yet", ["Run a model on gpus and they add up", "here: today, this week, all time."]); return done(s) }
S["gpus"] = () => office()
S["gpus-hover-running"] = () => office({ open: 0 })
S["gpus-hover-free"] = () => office({ open: 2 })
S["starting-download"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "busy", model: "Qwen3.8-27B", step: "downloading 42%", pct: .42, on: "on RTX 3090  ·  6.1 of 14.5 GB" }, "rule", ROWS.pair])
S["starting-load"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "busy", model: "Qwen3.8-27B", step: "loading 80%", pct: .8, on: "on RTX 3090  ·  checking it answers" }, "rule", ROWS.pair])
S["stopped"] = () => gpus([ROWS.q27, ROWS.q35, { kind: "stopped", model: "Qwen3.8-Flash-Next", on: "on RTX 3090  ·  stopped 2 min ago" }, "rule", ROWS.pair], { open: 2 })
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
S["one-gpu"] = () => gpus([ROWS.q27], { body: 236, foot: "1 GPU · 1 model running" })
S["cpu-only"] = () => gpus([{ kind: "run", model: "LFM2.5-2.6B", tps: 38, on: "on the CPU  ·  4 GB RAM", spark: [30, 36, 38, 0, 37, 39, 38, 36] },
  { kind: "free", maker: "cpu", name: "CPU", facts: "64 GB RAM  ·  61 free", used: .05, next: "Qwen3.5-9B" }], { body: 236, foot: "CPU only · 1 model running" })

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
  s.text(X, by - 12, "per day", { size: 11, fill: P.label }); days(s, X, by, FW - 2 * X, 90)
  return s.svg(FH)
}
S["full-home"] = () => {
  const s = full("home"), y = FHEAD + 50
  s.text(X, y, "per day, the last 4 weeks", { size: 11, fill: P.label }); days(s, X, y + 12, 760, 200)
  const tx = 860
  s.text(tx, y, "by model", { size: 11, fill: P.label })
  ;[["Qwen3.8-27B", "1.9M", "88 tok/s", "RTX 3090"], ["Qwen3.6-35B-A3B", "820k", "115 tok/s", "2 × B70"], ["LFM2.5-2.6B", "61k", "38 tok/s", "CPU"]].forEach(([m, t, v, c], i) => {
    const ry = y + 30 + i * 52
    logo(s, tx, ry - 12, 15, familyOf(m), P.value); s.text(tx + 24, ry, m, { size: 13, fill: P.value }); s.text(FW - X, ry, t, { size: 13, fill: P.ink, anchor: "end" })
    s.text(tx + 24, ry + 18, v + "  ·  " + c, { size: 11, fill: P.label })
  })
  return s.svg(FH)
}

export const SCREENS = S
export const ROW = { id: "frame", title: "The panel in a frame", primitive: "header and footer bands; two-line GPU rows; full screen",
  idea: "The top and the bottom never move.", screens: Object.entries(SCREENS).map(([id, draw]) => ({ id, title: id, draw })) }
