// Local AI panel renderer: Model.js's real view, drawn with Panel.qml's own metrics.
//
// Panel.qml draws the view Model.js builds. This file draws the same view the same way, into SVG
// instead of QML, so a screen can be looked at, measured, diffed and imported without a Linux desktop
// and without Quickshell. Every constant below is read from tokens.json, which is the same numbers
// Panel.qml uses through Style.space() and Style.font; nothing here is a fresh invention.
//
// The one assumption is text measurement. The panel's font is the bar's own family, a Nerd Font
// monospace, so a label's implicitWidth is its character count x 0.6 x its size (JetBrains Mono's
// advance is 600/1000 em) and Qt's implicitHeight for one line is size x 1.4. Everything else,
// including the APCA tone solve, comes from Model.js itself.

// >>> node only
// In Node the tokens and Model.js are read from the repository. A page has no filesystem, so
// design/build.mjs inlines the same two things and strips this block; nothing else in this file is
// Node-only, so the renderer that draws the studio is the renderer the app runs.
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const HERE = path.dirname(fileURLToPath(import.meta.url))

export const TOKENS = JSON.parse(fs.readFileSync(path.join(HERE, "tokens.json"), "utf8"))

// Model.js is the view model. It is a plain CommonJS file with no Qt in it, so the renderer draws the
// real view rather than a copy of it. It is loaded through vm because a package.json above this repo can
// put the whole tree in module mode, which would make require() return nothing.
export const MODEL = (() => {
  const mod = { exports: {} }
  const src = fs.readFileSync(path.join(HERE, "..", "Model.js"), "utf8")
  vm.runInNewContext(src, { module: mod, exports: mod.exports, console, Date, Math, JSON, Object, Array, String, Number, isNaN, parseFloat, parseInt })
  return mod.exports
})()
// <<< node only

// ---------------------------------------------------------------- numbers

const px = (t) => t.$value.value
export const L = {
  w: px(TOKENS.layout.panelWidth), edge: px(TOKENS.layout.edge), gutter: px(TOKENS.layout.gutter),
  pad: px(TOKENS.layout.pad), padTop: px(TOKENS.layout.padTop), padBottom: px(TOKENS.layout.padBottom),
  rowH: px(TOKENS.layout.rowH), headH: px(TOKENS.layout.headH), groupGap: px(TOKENS.layout.groupGap),
  blockGap: px(TOKENS.layout.blockGap), topGap: px(TOKENS.layout.topGap), cardH: px(TOKENS.layout.cardH),
  chartH: px(TOKENS.layout.chartH), gridCellH: px(TOKENS.layout.gridCellH), agentRowH: px(TOKENS.layout.agentRowH),
  slotCrashedH: px(TOKENS.layout.slotCrashedH), radius: px(TOKENS.layout.radius.cell),
  logoTile: px(TOKENS.layout.logo.tile), logoSmall: px(TOKENS.layout.logo.small),
  logoMini: px(TOKENS.layout.logo.mini), logoRadius: px(TOKENS.layout.logo.radius), logoGap: px(TOKENS.layout.logo.gap),
  plateH: px(TOKENS.layout.plate.h), modelH: px(TOKENS.layout.model.h), modelGap: px(TOKENS.layout.model.gap),
  barH: px(TOKENS.layout.stroke.bar), progressH: px(TOKENS.layout.stroke.progress),
  cellMax: px(TOKENS.activity.cellMax), cellGap: px(TOKENS.activity.cellGap), monthsH: px(TOKENS.activity.months),
  actRows: TOKENS.activity.rows.$value, actLevels: TOKENS.activity.levels.$value,
  chartStroke: px(TOKENS.chart.stroke), chartInset: px(TOKENS.chart.inset),
  // the panel has no navigation today, so the path and the back stack are tokens like any other
  navDepth: TOKENS.nav.depth.$value, crumbH: px(TOKENS.nav.crumb), segGap: px(TOKENS.nav.segmentGap),
  wall: { width: px(TOKENS.wall.width), height: px(TOKENS.wall.height), rail: px(TOKENS.wall.rail), gap: px(TOKENS.wall.gap),
    pane: px(TOKENS.wall.pane), detail: px(TOKENS.wall.detail) },
}
export const F = {
  small: px(TOKENS.font.size.captionSmall), caption: px(TOKENS.font.size.caption),
  captionLarge: px(TOKENS.font.size.captionLarge), body: px(TOKENS.font.size.body),
  subtitle: px(TOKENS.font.size.subtitle), head: px(TOKENS.font.size.head),
  advance: TOKENS.font.advance.$value, line: TOKENS.font.lineHeight.$value,
}
export const glyph = (name) => (TOKENS.icon[name] ? String.fromCodePoint(TOKENS.icon[name].$value) : "")

// A mark is a rounded tile holding one glyph or one monogram: the make of a card, the family of a model.
// The panel draws with a Nerd Font, so a monogram is the one logo that renders in every theme and at every
// width, and a family reads at a glance in a list of four.
const MONOGRAM = { qwen: "Q", llama: "L", mistral: "M", gemma: "G", deepseek: "D", phi: "P", glm: "G",
  granite: "Gr", olmo: "O", "gpt-oss": "O", exaone: "E", nemotron: "N", qwq: "Q" }
const VENDOR = { nvidia: "N", amd: "A", intel: "i", apple: "A", cpu: "C", metal: "M", vulkan: "V" }
export const monogram = (name) => MONOGRAM[String(name || "").toLowerCase()] || String(name || "?").slice(0, 1).toUpperCase()
export const vendorMark = (key) => VENDOR[String(key || "").split(":")[0].toLowerCase()] || String(key || "?").slice(0, 1).toUpperCase()

// The numbers the panel uses today, so a before-and-after is two token sets rather than two screenshots. L is
// read by every row renderer, so swapping its values is the whole switch; rendering is synchronous.
export function useDense(on) {
  const src = on ? TOKENS.was : TOKENS.layout
  for (const k of ["gutter", "pad", "rowH", "headH", "groupGap", "blockGap", "topGap"]) L[k] = px(src[k])
}

// Qt puts one line of a Text at size x 1.4, and a monospace advance is 0.6 em, so a label's width is
// its character count x 0.6 x its size. That is the whole measurement model.
export const textW = (s, size) => String(s || "").length * F.advance * size
export const textH = (lines, size) => Math.max(1, lines) * F.line * size

// Text.ElideRight / Text.ElideMiddle, the way Qt cuts a line that does not fit
export function elide(s, size, maxW, mode = "right") {
  s = String(s || "")
  if (textW(s, size) <= maxW) return s
  const fits = Math.max(0, Math.floor(maxW / (F.advance * size)) - 1)
  if (mode === "middle") {
    const head = Math.ceil(fits / 2), tail = Math.floor(fits / 2)
    return s.slice(0, head) + "…" + s.slice(s.length - tail)
  }
  return s.slice(0, fits) + "…"
}

// Text.WordWrap: greedy, at the space, cut at maxLines
export function wrap(s, size, maxW, maxLines = 99) {
  const words = String(s || "").split(" "), lines = []
  let line = ""
  for (const word of words) {
    const next = line ? line + " " + word : word
    if (line && textW(next, size) > maxW) { lines.push(line); line = word } else line = next
    if (lines.length === maxLines) break
  }
  if (line && lines.length < maxLines) lines.push(line)
  if (!lines.length) lines.push("")
  if (lines.length === maxLines) {
    const last = lines[maxLines - 1]
    lines[maxLines - 1] = elide(last + " …", size, maxW)
  }
  return lines
}

// ---------------------------------------------------------------- themes and tones

export const THEMES = {
  dark: { name: "Omarchy dark", theme: { r: .867, g: .867, b: .867 }, bg: { r: .07, g: .07, b: .08 }, urgent: { r: 1, g: .333, b: .333 } },
  light: { name: "Omarchy light", theme: { r: .13, g: .13, b: .15 }, bg: { r: .96, g: .96, b: .96 }, urgent: { r: .85, g: .13, b: .13 } },
  catppuccin: { name: "Catppuccin Mocha", theme: { r: .90, g: .89, b: .93 }, bg: { r: .12, g: .12, b: .18 }, urgent: { r: .95, g: .55, b: .60 } },
  gruvbox: { name: "Gruvbox", theme: { r: .92, g: .86, b: .78 }, bg: { r: .16, g: .15, b: .13 }, urgent: { r: .98, g: .29, b: .27 } },
  nord: { name: "Nord", theme: { r: .85, g: .87, b: .91 }, bg: { r: .11, g: .13, b: .16 }, urgent: { r: .75, g: .38, b: .42 } },
}

// Panel.qml: surface is Util.alpha(theme, 0.06) over the popup background, and tones() solves every
// text and line colour on the card surface (the lighter of the two), so the worst case is the one measured.
//
// Every colour is a CSS variable rather than a literal, so the studio switches a whole theme by setting
// eight values on one element, and one generated file carries every screen in every theme. The variables are
// computed here, from Model.js's own tone solve, so a theme cannot be drawn with colours it did not solve.
export function palette(themeName, literal = false) {
  const t = THEMES[themeName] || THEMES.dark
  const surface = { r: t.theme.r, g: t.theme.g, b: t.theme.b, a: .06 }
  const tones = MODEL.tones({ r: t.theme.r, g: t.theme.g, b: t.theme.b, a: 1 }, { r: t.bg.r, g: t.bg.g, b: t.bg.b, a: 1 }, surface, { r: t.urgent.r, g: t.urgent.g, b: t.urgent.b, a: 1 })
  const N = (a) => String(Math.round(a * 100))
  // An exported sheet has no stylesheet above it, so it carries the colours itself; the studio
  // carries the variable names instead and switches a whole theme by setting eight values.
  if (literal) return { name: t.name, tones, full: false,
    bg: rgb(t.bg), surface: alphaCss(t.theme, .06), card: alphaCss(t.theme, .08),
    ink: rgb(tones.ink), value: rgb(tones.value), label: rgb(tones.label), rule: rgb(tones.rule),
    alert: rgb(tones.alert || t.urgent), alertRule: rgb(tones.alertRule || tones.rule), themeCss: rgb(t.theme),
    v: (a) => alphaCss(t.theme, a), k: (a) => alphaCss(tones.ink, a), act: L.actLevels.map((a) => alphaCss(t.theme, a)) }
  return { name: t.name, tones,
    bg: "var(--bg)", surface: "var(--surface)", card: "var(--card)",
    ink: "var(--ink)", value: "var(--value)", label: "var(--label)", rule: "var(--rule)",
    alert: "var(--alert)", alertRule: "var(--alert-rule)", themeCss: "var(--theme)",
    // true in the full-screen layout: the same rows, in a wider column. A row asks for it rather
    // than the renderer branching per row, so a row can never be wide and narrow at once.
    full: false,
    // a tone at an alpha: the panel's own alpha(), as a variable
    v: (a) => `var(--theme-${N(a)})`, k: (a) => `var(--ink-${N(a)})`,
    // one activity level
    act: L.actLevels.map((a) => `var(--act-${N(a)})`) }
}

// The eight values a theme is made of, for the studio's stylesheet and for the generated file's :root.
export function themeVars(themeName) {
  const t = THEMES[themeName] || THEMES.dark
  const P = palette(themeName), N = (a) => String(Math.round(a * 100))
  const out = { "--bg": rgb(t.bg), "--theme": rgb(t.theme), "--ink": rgb(P.tones.ink), "--value": rgb(P.tones.value),
    "--label": rgb(P.tones.label), "--rule": rgb(P.tones.rule), "--alert": rgb(P.tones.alert), "--alert-rule": rgb(P.tones.alertRule),
    "--surface": alphaCss(t.theme, .06), "--card": alphaCss(t.theme, .08) }
  for (const a of [.04, .06, .08, .12, .19, .55, .6]) out[`--theme-${N(a)}`] = alphaCss(t.theme, a)
  for (const a of [.06, .25]) out[`--ink-${N(a)}`] = alphaCss(P.tones.ink, a)
  L.actLevels.forEach((a, i) => { out[`--act-${N(a)}`] = alphaCss(t.theme, a) })
  return out
}
const alphaCss = (c, a) => `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`
const rgb = (c) => `rgb(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)})`

// ---------------------------------------------------------------- primitives

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")

class Canvas {
  constructor(width, height, P) {
    this.w = width; this.h = height; this.P = P; this.parts = []; this.boxes = []; this.y = 0
    // ox is the left edge of the column being drawn: the panel's own edge, or the main pane's
    // when the rail is beside it. Every row draws in its own coordinates, so the same row functions
    // serve the 340 px panel and the full-screen layout.
    this.ox = 0
  }
  rect(x, y, w, h, o = {}) {
    this.parts.push(`<rect x="${r2(this.ox + x)}" y="${r2(y)}" width="${r2(w)}" height="${r2(h)}"${o.r ? ` rx="${r2(o.r)}"` : ""} fill="${o.fill || "none"}"${o.stroke ? ` stroke="${o.stroke}" stroke-width="${o.sw || 1}"${o.dash ? ` stroke-dasharray="${o.dash}"` : ""}` : ""}/>`)
  }
  // a Label: y is its baseline, x is its left edge, or its right edge when anchor is end
  text(x, y, s, o = {}) {
    if (!s) return
    this.parts.push(`<text x="${r2(this.ox + x)}" y="${r2(y)}" font-size="${r2(o.size || F.caption)}" fill="${o.fill || this.P.value}"${o.anchor ? ` text-anchor="${o.anchor}"` : ""} xml:space="preserve">${esc(s)}</text>`)
  }
  // one line of a wrapped label: the box is as wide as the widest line, and every line is centred
  lines(x, y, arr, size, o = {}) {
    arr.forEach((s, i) => this.text(x, y + i * size * F.line, s, o))
    return arr.length
  }
  poly(points, o = {}) {
    this.parts.push(`<polygon points="${points.map((p) => `${r2(this.ox + p[0])},${r2(p[1])}`).join(" ")}" fill="${o.fill}"${o.stroke ? ` stroke="${o.stroke}" stroke-width="${o.sw || 1}"` : ""}/>`)
  }
  line(points, o = {}) {
    this.parts.push(`<polyline points="${points.map((p) => `${r2(this.ox + p[0])},${r2(p[1])}`).join(" ")}" fill="none" stroke="${o.stroke}" stroke-width="${o.sw || 1}"/>`)
  }
  // A box is the row Panel.qml draws and, when it carries an action, the target it makes
  // clickable. Nothing else in the drawing knows about the mouse.
  box(type, x, y, w, h, label, action) { this.boxes.push({ type, x: this.ox + x, y, w, h, label, action: action || "" }) }
  toSVG() {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${r2(this.w)}" height="${r2(this.h)}" viewBox="0 0 ${r2(this.w)} ${r2(this.h)}" font-family="JetBrainsMono Nerd Font, JetBrains Mono, monospace">` +
      `<rect width="100%" height="100%" fill="${this.P.bg}"/>` + this.parts.join("") + "</svg>"
    return { svg, boxes: this.boxes, height: this.h, width: this.w }
  }
}
const r2 = (n) => Math.round(n * 100) / 100

// ---------------------------------------------------------------- a button

// Panel.qml's Btn: filled for the primary action, outlined in the same ink for the rest, alert for a
// danger. The label is centred optically: first on its ink, then nudged right by a sixth of the space a
// trailing chevron leaves.
function button(c, x, y, b) {
  const chevron = /\s›$/.test(b.label), size = F.caption
  const full = textW(b.label, size), words = textW(b.label.replace(/\s›$/, ""), size)
  const weight = chevron ? (full - words) / 6 : 0
  const w = Math.ceil(full) + 24, h = textH(1, size) + 10
  const off = full / 2 - (full / 2) + weight // the label's centre, nudged by the chevron's weight
  const fill = b.primary ? c.P.ink : "none"
  const stroke = b.primary ? null : b.danger ? c.P.alertRule : c.P.ink
  c.rect(x, y, w, h, { fill, stroke, sw: 1 })
  c.text(x + w / 2 + off, y + h / 2 + size * .35, b.label, { size, fill: b.primary ? c.P.bg : b.danger ? c.P.alert : c.P.ink, anchor: "middle" })
  c.box("btn" + (b.primary ? "-primary" : b.danger ? "-danger" : ""), x, y, w, h, b.label, b.action)
  return w
}

// Chips: small icon-and-text pairs, spaced instead of joined with dots
function chips(c, x, y, items, tone, size) {
  let at = x
  for (const item of items) {
    if (item.icon) { c.text(at, y, glyph(item.icon), { size, fill: c.P.label }); at += 12 + 4 }
    if (item.text) {
      c.text(at, y, item.text, { size, fill: tone || c.P.label })
      at += textW(item.text, size) + 12
    }
  }
  return at - 12 - x
}
const chipsH = (items, size) => items.reduce((a, i) => a + (i.icon ? 16 : 0) + textW(i.text, size) + 12, 0) - 12

// ---------------------------------------------------------------- one row

// Panel.qml's components, one function each. Each returns the height it used.
// A mark: a rounded tile, a glyph or a monogram in it, and nothing else. `size` is the tile; the mark is
// drawn at 0.55 of it, which is the largest it can be and still leave the tile a tile.
function mark(c, x, y, size, r) {
  const bg = r.tone === "off" ? c.P.v(.04) : r.on ? c.P.v(.14) : c.P.v(.07)
  const fg = r.tone === "off" ? c.P.label : r.on ? c.P.ink : c.P.value
  c.rect(x, y, size, size, { r: L.logoRadius, fill: bg })
  if (r.on) c.rect(x, y, size, size, { r: L.logoRadius, stroke: c.P.v(.35) })
  const inner = size * 0.55
  const label = r.mark || r.mono
  c.text(x + size / 2, y + size / 2 + inner * .35, r.glyph ? glyph(r.glyph) : label, { size: inner, fill: fg, anchor: "middle" })
  c.box("logo", x, y, size, size, r.glyph || label || "")
}

const ROWS = {
  // your lifetime: the totals, then the activity grid (a column a week, a row a weekday), then the months
  life(c, y, r, w) {
    const top = y
    c.text(L.gutter, y + textH(1, F.caption) / 2 + F.caption * .35, r.tokens, { size: F.caption, fill: c.P.ink })
    const tokensW = textW(r.tokens, F.caption)
    c.text(L.gutter + tokensW + 10, y + textH(1, F.caption) / 2 + F.caption * .35, r.requests, { size: F.caption, fill: c.P.label })
    c.text(w - L.gutter, y + textH(1, F.caption) / 2 + F.caption * .35, r.since, { size: F.caption, fill: c.P.label, anchor: "end" })
    y += textH(1, F.caption) + 10
    const cells = r.cells || [], cols = Math.ceil(cells.length / L.actRows)
    const gridTop = y
    // The grid is the one row that is genuinely a chart, so in the full-screen layout it takes a bigger
    // cell and the readout moves beside it. At 340 px the readout goes under, because there is no beside.
    const cellMax = c.P.full ? 24 : L.cellMax
    const avail = c.P.full ? Math.min(w - 2 * L.gutter, cols * (cellMax + L.cellGap) - L.cellGap) : w - 2 * L.gutter
    const cell = Math.min(cellMax, (avail - (cols - 1) * L.cellGap) / cols)
    for (let i = 0; i < cells.length; i++) {
      const col = Math.floor(i / L.actRows), row = i % L.actRows
      const x = L.gutter + col * (cell + L.cellGap), cy = y + row * (cell + L.cellGap)
      c.rect(x, cy, cell, cell, { r: L.radius, fill: cells[i] < 0 ? "none" : c.P.act[cells[i]] })
      c.box("day", x, cy, cell, cell, (r.labels || [])[i] || "")
    }
    y += L.actRows * cell + (L.actRows - 1) * L.cellGap + 10
    for (const m of r.months || [])
      c.text(L.gutter + m.col * (cell + L.cellGap), y + F.captionLarge * .9, m.label, { size: F.captionLarge, fill: c.P.label })
    y += L.monthsH + 10
    const last = (r.labels || [])[Math.max(0, (r.labels || []).length - 1)] || ""
    if (c.P.full) {
      // "today" is named, because a date with no heading reads like a tooltip that lost its tooltip
      const rx = L.gutter + cols * (cell + L.cellGap) + 32
      const mid = gridTop + (L.actRows * cell + (L.actRows - 1) * L.cellGap) / 2
      c.text(rx, mid - 8 + F.small * .35, "today", { size: F.small, fill: c.P.label })
      c.text(rx, mid + 8 + F.caption * .35, last, { size: F.caption, fill: c.P.ink })
      c.box("life-readout", rx, gridTop, w - L.gutter - rx, L.actRows * cell, last)
    } else {
      const arr = wrap(last, F.caption, w - 2 * L.gutter, 2)
      c.lines(L.gutter, y + F.caption * .9, arr, F.caption, { fill: c.P.label })
      y += arr.length * F.caption * F.line
    }
    c.box("life", 0, top, w, y - top, r.tokens)
    return y - top
  },

  // a running model: its all-time token line behind its name, then its card, speed and tokens, then Open and More
  run(c, y, r, w) {
    // In the full-screen layout the card is taller and the chart is 220 rather than 110: the token line
    // is the model's whole history, and at 110 px in a 340 px card it is only a sparkline.
    const cardH = c.P.full ? 240 : L.cardH, chartH = c.P.full ? 220 : L.chartH
    const top = y
    c.rect(0, y, w, cardH, { fill: c.P.v(.08), stroke: c.P.v(.19), sw: 1 })
    if ((r.line || []).length > 1) {
      const n = r.line.length, max = Math.max(...r.line, 1), pts = []
      for (let i = 0; i < n; i++) pts.push([i / (n - 1) * w, y + cardH - L.chartInset - (r.line[i] / max) * (cardH * .8)])
      c.poly(pts.concat([[w, y + cardH], [0, y + cardH]]), { fill: c.P.k(.06) })
      c.line(pts, { stroke: c.P.k(.25), sw: 1.2 })
    }
    let cy = y + 16
    c.text(L.pad, cy + F.subtitle * .35, elide(r.name, F.subtitle, w - 2 * L.pad - 22), { size: F.subtitle, fill: c.P.ink })
    cy += textH(1, F.subtitle) + 6
    c.text(L.pad, cy + F.caption * .35, r.gpu, { size: F.caption, fill: c.P.label })
    if (r.mem) c.text(L.pad + textW(r.gpu, F.caption) + 10, cy + F.caption * .35, r.mem, { size: F.caption, fill: c.P.v(.6) })
    cy += textH(1, F.caption) + 6 + 4
    if (r.sub) { const arr = wrap(r.sub, F.caption, w - 2 * L.pad, 2); cy += c.lines(L.pad, cy + F.caption * .35, arr, F.caption, { fill: c.P.value }) * F.caption * F.line }
    if (r.progress >= 0) {
      cy += 2
      c.rect(L.pad, cy, w - 2 * L.pad, L.progressH, { fill: c.P.rule })
      c.rect(L.pad, cy, (w - 2 * L.pad) * r.progress / 100, L.progressH, { fill: c.P.ink })
      cy += L.progressH
    }
    if ((r.chips || []).length) chips(c, w - L.pad - chipsH(r.chips, F.captionLarge), y + cardH - 20 - F.captionLarge, r.chips, c.P.label, F.captionLarge)
    const by = y + cardH - 14 - (textH(1, F.caption) + 10)
    let bx = L.pad
    bx += button(c, bx, by, r.primary) + 8
    button(c, bx, by, { label: "More", action: r.more })
    c.box("run", 0, top, w, cardH, r.name)
    return cardH
  },

  // one GPU: its name, then one quick action or what it is doing; a crashed one is framed in dashes
  slot(c, y, r, w) {
    const top = y, h = r.crashed ? L.slotCrashedH : L.rowH
    if (r.crashed) c.rect(L.edge, y, w - 2 * L.edge, h, { stroke: c.P.alertRule, sw: 1, dash: "3 3" })
    const mid = y + h / 2 + F.caption * .35
    let x = L.gutter
    c.text(x, mid, r.label, { size: F.caption, fill: r.open ? c.P.ink : c.P.value })
    x += textW(r.label, F.caption) + 10
    if (r.hint) c.text(x, mid, r.hint, { size: F.caption, fill: c.P.alert })
    if (r.run) {
      const label = r.run.label, lw = textW(label, F.caption)
      const rx = w - L.gutter - lw
      c.text(rx, mid, label, { size: F.caption, fill: c.P.ink })
      c.box("slot-run", rx - 12 - 6, y, lw + 18, h, label, r.run.action)
    } else {
      const note = elide(r.note || "", F.caption, c.P.full ? w - L.gutter * 3 : w * .6)
      c.text(w - L.gutter, mid, note, { size: F.caption, fill: r.warn ? c.P.alert : c.P.label, anchor: "end" })
    }
    if (r.dismiss) {
      const dw = textW("dismiss", F.caption)
      const dx = w - L.gutter - textW(r.run ? r.run.label : "", F.caption) - 6 - 16 - dw
      c.text(dx, mid, "dismiss", { size: F.caption, fill: c.P.label })
      c.box("slot-dismiss", dx - 6, y, dw + 12, h, "dismiss", r.dismiss)
    }
    c.box("slot", 0, top, w, h, r.label, r.toggle)
    return h
  },

  // a row of buttons, with what there is to know above it
  links(c, y, r, w) {
    let cy = y + 2
    if ((r.chips || []).length) { chips(c, L.gutter, cy + F.caption * .35, r.chips, c.P.label, F.caption); cy += textH(1, F.caption) + 8 }
    if (r.note) {
      const arr = wrap(r.note, F.caption, w - 2 * L.gutter, 99)
      c.lines(L.gutter, cy + F.caption * .35, arr, F.caption, { fill: c.P.label })
      cy += arr.length * F.caption * F.line + 8
    }
    if ((r.items || []).length) {
      // Panel.qml's linksC is a Flow, so a row of buttons wraps rather than running off the panel.
      const room = w - 2 * L.gutter, lineH = textH(1, F.caption) + 10
      let bx = L.gutter
      for (const item of r.items) {
        const bw = textW(item.label, F.caption) + 24
        if (bx > L.gutter && bx - L.gutter + bw > room) { bx = L.gutter; cy += lineH + 8 }
        bx += button(c, bx, cy, item) + 8
      }
      cy += lineH
    }
    c.box("links", 0, y, w, cy - y + 10, (r.items || []).map((i) => i.label).join(" · "))
    return cy - y + 10
  },

  // A row of buttons: the one action a page is for, and whatever sits beside it. Panel.qml draws these
  // as a Row of Btn; the renderer had no row for them, so every acts row in the design — Run, Stop, Open,
  // View logs, Refresh models — was in the view and not on the page.
  acts(c, y, r, w) {
    const items = (r.items || []).filter((i) => i.label)
    if (!items.length) return 0
    const lineH = textH(1, F.caption) + 10
    let bx = L.gutter, cy = y + 2, lines = 1
    const room = w - 2 * L.gutter
    for (const item of items) {
      const bw = textW(item.label, F.caption) + 24
      if (bx > L.gutter && bx - L.gutter + bw > room) { bx = L.gutter; cy += lineH + 8; lines++ }
      bx += button(c, bx, cy, item) + 8
    }
    const h = lines * lineH + (lines - 1) * 8 + 4
    c.box("acts", 0, y, w, h, items.map((i) => i.label).join(" · "))
    return h
  },

  // no card to run on: a square wave, one line, and where the supported list lives
  soon(c, y, r, w) {
    let cy = y + 28
    const waveW = 140, period = 28, stroke = 1.5
    for (let i = 0; i < Math.ceil(waveW / period) + 1; i++) {
      const x = L.gutter + (w - 2 * L.gutter - waveW) / 2 + i * period
      c.rect(x - stroke / 2, cy + 2, stroke, 18 - 4 + stroke, { fill: c.P.label })
      c.rect(x, cy + 2, period / 2, stroke, { fill: c.P.label })
      c.rect(x + period / 2 - stroke / 2, cy + 2, stroke, 18 - 4 + stroke, { fill: c.P.label })
      c.rect(x + period / 2, cy + 18 - 2, period / 2, stroke, { fill: c.P.label })
    }
    cy += 18 + 18
    const arr = wrap(r.head, F.caption, w - 2 * L.gutter, 2)
    c.lines(L.gutter, cy + F.caption * .35, arr, F.caption, { fill: c.P.value })
    cy += arr.length * F.caption * F.line + 18
    const bw = Math.ceil(textW("See supported cards ›", F.caption)) + 24
    button(c, (w - bw) / 2, cy, { label: "See supported cards ›", action: r.action })
    cy += textH(1, F.caption) + 10 + 20
    c.box("soon", 0, y, w, cy - y, r.head, r.action)
    return cy - y
  },

  // a section's name, or an error in its place
  text(c, y, r, w) {
    if (r.type === "sec") {
      c.text(L.gutter, y + L.headH / 2 + F.caption * .35, r.label, { size: F.caption, fill: c.P.label })
      // In the full-screen layout a rule runs from the name to the right edge: sections are the only
      // structure the panel has, and the rule makes them read as structure rather than as a bigger label.
      if (c.P.full) {
        const x = L.gutter + textW(r.label, F.caption) + 12
        c.rect(x, y + L.headH / 2, Math.max(0, w - L.gutter - x), 1, { fill: c.P.rule })
      }
      c.box("sec", 0, y, w, L.headH, r.label, r.action)
      return L.headH
    }
    const arr = wrap(r.label, F.caption, w - 2 * L.gutter, 99)
    c.lines(L.gutter, y + F.caption * .35, arr, F.caption, { fill: c.P.alert })
    c.box("error", 0, y, w, arr.length * F.caption * F.line, r.label)
    return arr.length * F.caption * F.line
  },

  // six figures, three by two, hairline gaps
  grid(c, y, r, w) {
    // at 340 px: three by two, because three 107 px figures are all that fit. In the full-screen
    // layout: six across, so the six figures read as one row rather than as two rows of three.
    const cols = c.P.full ? 6 : 3, cellH = c.P.full ? 64 : L.gridCellH
    const cw = (w - (cols - 1)) / cols
    ;(r.cells || []).forEach((cell, i) => {
      const x = (i % cols) * (cw + 1), cy = y + Math.floor(i / cols) * (cellH + 1)
      c.rect(x, cy, cw, cellH, { fill: c.P.surface })
      c.text(x + L.pad, cy + cellH / 2 - 6 + F.caption * .35, cell.v, { size: F.caption, fill: c.P.value })
      c.text(x + L.pad + textW(cell.v, F.caption) + 6, cy + cellH / 2 - 6 + F.caption * .35, cell.u, { size: F.caption, fill: c.P.label })
      c.text(x + L.pad, cy + cellH / 2 + 6 + F.caption * .35, cell.k, { size: F.caption, fill: c.P.label })
      c.box("figure", x, cy, cw, cellH, `${cell.v} ${cell.u} · ${cell.k}`)
    })
    const rows = Math.ceil((r.cells || []).length / cols)
    c.box("grid", 0, y, w, rows * cellH + (rows - 1), `${(r.cells || []).length} figures, ${cols} across`)
    return rows * cellH + (rows - 1)
  },

  // one card: its name (and what holds it), memory in use, temperature
  gpu(c, y, r, w) {
    const h = r.status ? 36 : L.rowH, mid = y + h / 2 + F.caption * .35
    // At 340 px the name is a fixed 100 px and the bar starts at a magic 104, so the two are not
    // derived from each other and a long card name elides into a column sized for nothing. In the
    // full-screen layout the row is four real columns: card | bar | used | temp.
    const tail = r.mem + (r.temp ? "  " + r.temp : "")
    // A card row is the one row on a page that names a thing and does nothing when it is tapped:
    // the panel's card rows have no action at all. The proposal gives them one, so a card row that has
    // an action carries the panel's own chevron and the tail gives way to it.
    const chevron = r.action ? "›" : ""
    let nameW = 100, barX = L.gutter + 104, barW = Math.max(0, (w - L.gutter - textW(tail, F.caption) - (chevron ? 14 : 0)) - barX - 12)
    if (c.P.full) {
      const tempW = r.temp ? 64 : 0, usedW = 120
      const content = w - 2 * L.gutter
      nameW = Math.max(60, (content - tempW - usedW) * .4)
      barX = L.gutter + nameW + 16
      barW = Math.max(0, content - nameW - tempW - usedW - 32)
      if (tempW) c.text(w - L.gutter, mid, r.temp, { size: F.caption, fill: c.P.value, anchor: "end" })
      c.text(w - L.gutter - tempW, mid, r.mem, { size: F.caption, fill: c.P.value, anchor: "end" })
    }
    c.text(L.gutter, mid - (r.status ? 8 : 0), elide(r.name, F.caption, nameW), { size: F.caption, fill: c.P.value })
    if (r.status) c.text(L.gutter, mid + 8, r.status, { size: F.caption, fill: c.P.label })
    if (r.bar) {
      c.rect(barX, y + h / 2 - L.barH / 2, barW, L.barH, { fill: c.P.rule })
      c.rect(barX, y + h / 2 - L.barH / 2, barW * r.pct / 100, L.barH, { fill: c.P.value })
      c.box("gpu-bar", barX, y + h / 2 - L.barH / 2, barW * r.pct / 100, L.barH, `${r.pct}%`)
    }
    if (!c.P.full) {
      if (chevron) { c.text(w - L.gutter, mid, chevron, { size: F.caption, fill: c.P.label, anchor: "end" }); c.box("gpu-action", w - L.gutter - 10, y, 10, h, "open", r.action) }
      c.text(w - L.gutter - (chevron ? 14 : 0), mid, tail, { size: F.caption, fill: c.P.value, anchor: "end" })
    }
    c.box("gpu", 0, y, w, h, r.name, r.action)
    c.box("gpu-name", L.gutter, y, nameW, h, r.name)
    return h
  },

  // a label on the left, a value on the right; a secret value stays hidden and small until clicked
  field(c, y, r, w) {
    const mid = y + L.rowH / 2 + F.caption * .35
    let lx = L.gutter
    if (r.icon) { c.text(lx, mid, glyph(r.icon), { size: F.caption, fill: c.P.label }); lx += 12 + 8 }
    if (r.logo) lx += 12 + 8
    c.text(lx, mid, r.label, { size: F.caption, fill: c.P.label })
    const labelW = lx - L.gutter + textW(r.label, F.caption)
    const value = r.secret ? (r.copied ? "copied" : "copy") : (r.value || "") + (r.drop ? "  " + glyph("down") : r.action ? " ›" : "")
    // At 340 px a long value loses its middle, which is the worst place to cut a repository or a
    // URL. In the full-screen layout the label takes a fixed column and the value takes the rest, so
    // nothing is cut in the middle.
    const room = c.P.full ? w - L.gutter - labelW - L.gutter : w - L.gutter - labelW - L.gutter - 16
    const vw = c.P.full ? room : Math.min(textW(value, F.caption), room)
    c.text(w - L.gutter, mid, elide(value, F.caption, vw, c.P.full ? "right" : r.secret ? "right" : "middle"), { size: F.caption, fill: r.open ? c.P.ink : c.P.value, anchor: "end" })
    if (r.secret) {
      const sw = Math.max(0, (w - L.gutter - vw) - L.gutter - labelW - 20)
      c.text(w - L.gutter - vw - 10, mid, elide(r.revealed ? r.value : String(r.value).replace(/[^.:/]+/g, "•••"), F.small, sw, "middle"), { size: F.small, fill: r.revealed ? c.P.themeCss : c.P.v(.55), anchor: "end" })
    }
    c.box("field", 0, y, w, L.rowH, r.label, r.action)
    c.box("field-label", L.gutter, y, labelW, L.rowH, r.label)
    c.box("field-value", w - L.gutter - vw, y, vw, L.rowH, r.value || "")
    return L.rowH
  },

  // The card a models page is about, as a plate: its mark, its name, what it is, and its memory. The page's
  // identity is the card, so the card gets the room a row would not, and the memory bar moves up into it.
  plate(c, y, r, w) {
    const h = L.plateH, pad = L.pad
    c.rect(0, y, w, h, { r: L.radius, fill: c.P.card })
    const tx = pad + L.logoTile + L.logoGap
    c.text(tx, y + pad + F.subtitle * .85, elide(r.name, F.subtitle, w - tx - pad), { size: F.subtitle, fill: c.P.ink })
    c.text(tx, y + pad + F.subtitle * 1.4 + 10, elide(r.sub, F.caption, w - tx - pad), { size: F.caption, fill: c.P.label })
    const barY = y + h - pad - L.barH - F.caption * 1.4 - 8
    c.rect(pad, barY, w - 2 * pad, L.barH, { fill: c.P.rule })
    if (r.pct > 0) c.rect(pad, barY, (w - 2 * pad) * r.pct / 100, L.barH, { fill: c.P.value })
    c.text(pad, barY + L.barH + F.caption * 1.15, r.mem, { size: F.caption, fill: c.P.value })
    if (r.temp) c.text(w - pad, barY + L.barH + F.caption * 1.15, r.temp, { size: F.caption, fill: c.P.value, anchor: "end" })
    mark(c, pad, y + pad, L.logoTile, r)
    c.box("plate", 0, y, w, h, r.name, r.action)
    c.box("plate-name", tx, y + pad, w - tx - pad, F.subtitle * 1.4, r.name)
    return h
  },

  // A model as a card rather than a line: its mark, its name, its figures under it, and how it fits as a
  // mark on the right rather than a word the name has to give way to.
  model(c, y, r, w) {
    const h = L.modelH, pad = L.pad
    const mx = L.gutter, tx = mx + L.logoSmall + L.logoGap
    const fitW = textW(r.fit, F.caption)
    c.rect(0, y, w, h, { r: L.radius, fill: r.on ? c.P.card : "none" })
    c.rect(0, y, w, h, { r: L.radius, stroke: r.on ? c.P.v(.3) : c.P.v(.12) })
    mark(c, mx, y + (h - L.logoSmall) / 2, L.logoSmall, { mark: r.mark || r.mono, on: r.on, tone: r.off ? "off" : "" })
    const nameW = Math.max(0, w - tx - pad - (r.fit ? fitW + 12 : 0))
    c.text(tx, y + h / 2 - F.caption * .45, elide(r.label, F.body, nameW), { size: F.body, fill: r.off ? c.P.label : r.on ? c.P.ink : c.P.value })
    c.text(tx, y + h / 2 + F.caption * .75, elide(r.figures, F.caption, w - tx - pad), { size: F.caption, fill: c.P.label })
    if (r.fit) c.text(w - pad, y + h / 2 - F.caption * .45, elide(r.fit, F.caption, fitW), { size: F.caption, fill: r.off ? c.P.alert : c.P.label, anchor: "end" })
    c.box("model", 0, y, w, h, r.label + "  " + r.figures, r.action)
    c.box("model-name", tx, y, nameW, h, r.label)
    return h
  },

  // a model choice: its name, whether it fits, and a check on the chosen one
  opt(c, y, r, w) {
    const mid = y + L.rowH / 2 + F.caption * .35
    // At 340 px the fit may take half the row from the name, which is the name that elides and the
    // fit that keeps its room. In the full-screen layout the row is three columns — check 24,
    // name 1fr, fit 200 — so neither can push the other and the name is never the one that gives way.
    const fitW = c.P.full ? 200 : (w - 2 * L.gutter) / 2
    const valueW = r.value ? Math.min(textW(r.value, F.caption), fitW) : 0
    const labelW = Math.max(0, (w - L.gutter - valueW) - L.gutter - 10)
    c.text(L.gutter, mid, r.on ? glyph("check") : "", { size: F.caption, fill: c.P.ink })
    c.text(L.gutter + 12 + 8, mid, elide(r.label, F.caption, Math.max(0, labelW - 20)), { size: F.caption, fill: r.on ? c.P.ink : r.off ? c.P.label : c.P.value })
    if (r.value) c.text(w - L.gutter, mid, elide(r.value, F.caption, valueW), { size: F.caption, fill: c.P.label, anchor: "end" })
    c.box("opt", 0, y, w, L.rowH, `${r.label}  ${r.value || ""}`, r.action)
    c.box("opt-name", L.gutter + 20, y, Math.max(0, labelW - 20), L.rowH, r.label)
    c.box("opt-fit", w - L.gutter - valueW, y, valueW, L.rowH, r.value || "")
    return L.rowH
  },

  // an agent choice: its logo, its name, and what clicking it does
  agent(c, y, r, w) {
    const mid = y + L.agentRowH / 2 + F.caption * .35
    c.rect(L.gutter, y + L.agentRowH / 2 - 12, 24, 24, { fill: c.P.v(.12), r: 4 })
    c.text(L.gutter + 12, mid, r.agent === "pi" ? "π" : glyph("agent"), { size: F.caption, fill: c.P.ink, anchor: "middle" })
    c.text(L.gutter + 24 + 10, mid, r.label, { size: F.caption, fill: c.P.ink })
    c.text(w - L.gutter, mid, (r.value || "") + " ›", { size: F.caption, fill: c.P.label, anchor: "end" })
    c.box("agent", 0, y, w, L.agentRowH, r.label, r.action)
    return L.agentRowH
  },
}

// ---------------------------------------------------------------- the panel

// Panel.qml's gapBefore: a group opens a gap, a surface follows a surface closely, rows in a group touch
function gapBefore(view, i) {
  const rows = view.rows || [], t = rows[i].type
  if (i === 0 && !view.hero && t !== "sec") return L.topGap
  if (t === "sec" || t === "acts" || t === "error") return L.groupGap
  if (t === "model") return L.modelGap
  if (t === "plate") return i === 0 && !view.hero ? L.topGap : L.groupGap
  if (t === "run" || t === "grid") return i === 0 && !view.hero ? L.topGap : L.blockGap
  return i === 0 ? L.topGap : 0
}

// One page: the top line, the hero, then every row. `x` is the left edge of its column and `w` its
// width. The panel draws this once at 340; the full-screen layout draws it twice, at 340 and at 704, so
// the same rows serve both and no row is ever stretched to a width it was not designed for.
function drawPane(c, snap, ui, opts) {
  const w = opts.width, x = opts.x || 0
  const view = opts.view || MODEL.build(snap, ui)
  const crumb = opts.crumb || []
  // A column in the full-screen layout names its own page rather than offering a way back: the way
  // back there is Esc, not a row. So a head label wins over the view's own back flag.
  const label = opts.headLabel || ""
  const head = { title: label || view.title || "LOCAL AI", version: label ? "" : view.version || "",
    back: !label && !crumb.length && !!view.back }
  const prev = { full: c.P.full, propose: c.P.propose }
  c.P = Object.assign({}, c.P, { full: !!opts.full, propose: !!opts.propose })
  let y = L.padTop
  c.ox = x
  const mid = y + L.headH / 2 + F.caption * .35
  // The top line: the page's own name and version, or the way back. A page reached from another page
  // carries the path instead — the parent is the way back and the rest is where you are. It costs no
  // height, because the path shares the head row the panel already draws.
  if (crumb.length) {
    let hx = L.gutter
    const seg = (s, tone, type) => {
      if (!s) return
      const tw = textW(s, F.caption)
      c.text(hx, mid, elide(s, F.caption, Math.max(0, w - L.gutter - hx)), { size: F.caption, fill: tone })
      if (type) c.box(type, hx, y, tw, L.headH, s)
      hx += tw + L.segGap
    }
    seg("‹ " + crumb[0], c.P.value, "head-back")
    for (const s of crumb.slice(1)) { seg("›", c.P.v(.55)); seg(s, c.P.ink, "crumb") }
  } else {
    c.text(L.gutter, mid, head.back ? "‹ home" : head.title, { size: F.caption, fill: head.back ? c.P.value : c.P.label })
    if (!head.back && head.version) c.text(L.gutter + textW(head.title, F.caption) + 8, mid, head.version, { size: F.small, fill: c.P.v(.55) })
  }
  c.box("head", 0, y, w, L.headH, crumb.length ? crumb.join(" › ") : head.back ? "‹ home" : head.title, head.back ? "back" : "")
  y += L.headH
  if (view.hero) { c.ox = 0; y += L.topGap + hero(c, y + L.topGap, view.hero, w, x) }
  for (let i = 0; i < (view.rows || []).length; i++) {
    const r = view.rows[i]
    y += gapBefore(view, i)
    // a running model's card and the figures sit at the panel's edge, so their own inset lives on the
    // row; every other row keeps the gutter
    const inset = r.type === "run" || r.type === "grid" ? L.edge : 0
    c.ox = x + inset
    y += (ROWS[r.type] || ROWS.text)(c, y, r, w - 2 * inset) || 0
  }
  y += L.padBottom
  c.P = Object.assign({}, c.P, prev)
  return y
}

// The whole popup: the panel's own 340, or the same page in the full-screen layout's first column.
export function renderScreen(snap, ui, opts = {}) {
  useDense(!!opts.dense)
  const theme = opts.theme || "dark"
  const P = palette(theme, !!opts.literal)
  const full = !!opts.fullscreen
  const total = full ? (opts.width || L.wall.width) : L.w
  const railW = full && opts.rail !== false ? L.wall.rail : 0
  const c = new Canvas(total, 10, P)
  c.P = Object.assign({}, P, { theme: THEMES[theme].theme, full, propose: !!opts.propose, logos: !!opts.logos })
  if (railW) { c.ox = 0; renderRail(c, snap, ui, railW) }
  const y = drawPane(c, snap, ui, { x: railW, width: total - railW, view: opts.view, crumb: opts.crumb,
    headLabel: opts.headLabel, propose: opts.propose })
  c.h = Math.max(y, opts.minHeight || y)
  spliceRail(c)
  return c.toSVG()
}

// The rail's own surface runs the whole way down, so it is drawn once the canvas height is known
function spliceRail(c) {
  if (!c.railMark) return
  const { mark, w } = c.railMark
  c.parts.splice(mark, 0,
    `<rect x="0" y="0" width="${r2(w - 1)}" height="${r2(c.h)}" fill="${c.P.v(.04)}"/>`,
    `<rect x="${r2(w - 1)}" y="0" width="1" height="${r2(c.h)}" fill="${c.P.v(.08)}"/>`)
}

// The full-screen layout: three columns and no row stretched. The panel's own page at 340 — the panel is
// 340 because the bar is a bar, and every row in it was designed for 340 — the page for whatever is
// selected at 704, where the wide rows live, and the rail at 220. 220 + 8 + 340 + 8 + 704 = 1280.
//
// This is the fix for the panel's two hardest pages rather than a second design: the model page and the
// hardware page are cramped only because 340 px is not enough for a card, a fit, a bar and a memory reading
// at once, and at 704 the detail column has room for all four. Nothing is stretched to reach it.
export function renderWall(snap, opts = {}) {
  useDense(!!opts.dense)
  const theme = opts.theme || "dark"
  const P = palette(theme, !!opts.literal)
  const W = L.wall.width, railW = L.wall.rail, gap = L.wall.gap, paneW = L.wall.pane
  const c = new Canvas(W, 10, P)
  c.P = Object.assign({}, P, { theme: THEMES[theme].theme, full: false, propose: !!opts.propose, logos: !!opts.logos })
  const page = opts.page || { ui: { view: "home" } }
  const detail = opts.detail || null
  const bgMark = c.parts.length
  c.ox = 0
  renderRail(c, snap, page.ui || {}, railW)
  const x1 = railW + gap, x2 = x1 + paneW + gap
  const y1 = drawPane(c, snap, page.ui || {}, { x: x1, width: paneW, view: page.view, crumb: page.crumb, headLabel: page.head })
  const y2 = detail ? drawPane(c, snap, detail.ui || {}, { x: x2, width: L.wall.detail, view: detail.view, crumb: detail.crumb,
    headLabel: detail.head, full: true, propose: opts.propose }) : 0
  c.h = Math.max(y1, y2, opts.minHeight || 0)
  // the columns' own surfaces, and a rule between them, drawn once the height is known so they run the
  // whole way down rather than only as far as their own content
  c.parts.splice(bgMark, 0,
    `<rect x="${r2(x1)}" y="0" width="${r2(paneW)}" height="${r2(c.h)}" fill="${c.P.v(.02)}"/>`,
    detail ? `<rect x="${r2(x2)}" y="0" width="${r2(L.wall.detail)}" height="${r2(c.h)}" fill="${c.P.v(.04)}"/>` : "",
    `<rect x="${r2(x1 - gap / 2)}" y="0" width="1" height="${r2(c.h)}" fill="${c.P.v(.08)}"/>`,
    detail ? `<rect x="${r2(x2 - gap / 2)}" y="0" width="1" height="${r2(c.h)}" fill="${c.P.v(.08)}"/>` : "")
  spliceRail(c)
  return c.toSVG()
}

// The top of a model's page: its name, what it is, and the surface under them when it runs
function hero(c, y, h, w, x0) {
  const top = y
  let cy = y
  c.text(x0 + L.pad, cy + F.body * .9, elide(h.name, F.body, w - 2 * L.pad - 22), { size: F.body, fill: c.P.ink })
  cy += textH(1, F.body) + 4
  chips(c, x0 + L.pad, cy + F.caption * .35, h.chips || [], c.P.value, F.caption)
  cy += textH(1, F.caption) + L.topGap
  if (h.line) {
    c.rect(x0 + L.edge, cy, w - 2 * L.edge, L.chartH, { fill: c.P.surface, stroke: c.P.v(.19), sw: 1 })
    const n = h.line.length, max = Math.max(...h.line, 1), pts = []
    for (let i = 0; i < n; i++) pts.push([x0 + L.edge + i / (n - 1) * (w - 2 * L.edge), cy + L.chartH - L.chartInset - (h.line[i] / max) * (L.chartH * .8)])
    c.poly(pts.concat([[x0 + w - L.edge, cy + L.chartH], [x0 + L.edge, cy + L.chartH]]), { fill: c.P.k(.06) })
    c.line(pts, { stroke: c.P.k(.25), sw: 1.2 })
    c.text(x0 + L.pad, cy + 8 + F.caption * .35, h.top || "", { size: F.caption, fill: c.P.label })
    c.text(x0 + L.pad, cy + L.chartH / 2 + F.caption * .35, h.mid || "", { size: F.caption, fill: c.P.label })
    c.text(x0 + L.pad, cy + L.chartH - 8 - F.caption, h.since || "", { size: F.caption, fill: c.P.label })
    c.text(x0 + w - 6, cy + L.chartH - 8 - F.caption, h.now || "", { size: F.caption, fill: c.P.label, anchor: "end" })
    c.box("chart", x0 + L.edge, cy, w - 2 * L.edge, L.chartH, `${h.top} · ${h.since} · ${h.now}`)
    cy += L.chartH
  }
  return cy - top
}

// The full-screen rail: the panel's three surfaces, then what is running. It is the one component the
// full-screen layout adds; every row beside it is the panel's own, at the panel's own 22 px row.
function renderRail(c, snap, ui, w) {
  // The rail's own surface is drawn once the canvas height is known, so it runs the whole way down
  // rather than only as far as its own content.
  const mark = c.parts.length
  let y = L.padTop
  const section = (label, first) => {
    if (!first) y += L.groupGap
    c.text(L.gutter, y + F.caption, label, { size: F.caption, fill: c.P.label })
    c.box("rail-sec", 0, y, w, L.headH + L.blockGap, label)
    y += L.headH + L.blockGap
  }
  const row = (label, on, note, action) => {
    const h = note ? L.agentRowH : L.rowH
    c.text(L.gutter, y + L.rowH / 2 + F.caption * .35, elide(label, F.caption, w - 2 * L.gutter), { size: F.caption, fill: on ? c.P.ink : c.P.value })
    if (note) c.text(L.gutter, y + L.rowH + F.small * .35, note, { size: F.small, fill: c.P.label })
    c.box("rail-item" + (on ? "-on" : ""), 0, y, w, h, label, action)
    y += h
  }
  section("SURFACES", true)
  for (const [id, label] of [["home", "Overview"], ["kind", "Models"], ["gpus", "Hardware"], ["agents", "Agents"]])
    row(label, (ui.view || "home") === id, "", "surface|" + id)
  section("RUNNING")
  const running = (snap.deployments || []).filter((d) => d.state !== "error")
  if (!running.length) row("nothing yet", false)
  for (const d of running) row(d.name, false, `${d.agent} · ${d.state}`, "more|" + d.id)
  y += L.groupGap
  row("Refresh models", false, "", "registry")
  c.railMark = { mark, w, bottom: y }
  return w
}
