// The kit every design row draws with: the panel's tones (solved per theme by Model.js tones()), the bar's
// font, the panel's 340 px column, and the shared data. A row may add its own drawing helpers in its own file;
// it may not add colours, fonts or widths the panel does not have.
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { MODEL, palette, TOKENS } from "../panel.mjs"
import { MACHINES } from "../fixtures.mjs"

const HERE = path.dirname(fileURLToPath(import.meta.url))

// ---------------------------------------------------------------- the drawing surface

export const W = 340, G = TOKENS.layout.gutter.$value.value // the panel's own width and gutter
const FAMILY = TOKENS.font.family.$value.concat(["CaskaydiaMono Nerd Font"]).join(", ")
const ADV = TOKENS.font.advance.$value
export const P = palette("dark", true)
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
export const tw = (s, size) => String(s).length * ADV * size

// A small SVG surface: text, lines, dots, rects, paths. A screen is one Sheet; svg() returns { svg, h }.
export class Sheet {
  constructor() { this.parts = []; this.h = 0 }
  text(x, y, s, o = {}) {
    const size = o.size || 12
    this.parts.push(`<text x="${x}" y="${y}" font-size="${size}" fill="${o.fill || P.value}"${o.anchor ? ` text-anchor="${o.anchor}"` : ""}${o.weight ? ` font-weight="${o.weight}"` : ""}${o.underline ? ` text-decoration="underline"` : ""}>${esc(s)}</text>`)
    this.h = Math.max(this.h, y + size * .4)
    return tw(s, size)
  }
  line(x1, y1, x2, y2, o = {}) { this.parts.push(`<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${o.stroke || P.rule}" stroke-width="${o.sw || 1}"/>`) }
  dot(x, y, r, fill) { this.parts.push(`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}"/>`) }
  rect(x, y, w, h, fill) { this.parts.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}"/>`) }
  path(d, o = {}) { this.parts.push(`<path d="${d}" fill="${o.fill || "none"}" stroke="${o.stroke || "none"}" stroke-width="${o.sw || 1}"/>`) }
  // a run of words on one line, each with its own size and tone, laid out left to right
  run(x, y, bits) { let at = x; for (const b of bits) { at += this.text(at, y, b.t, b) + (b.gap ?? 0) } return at - x }
  // wrapped text that flows like prose: the pieces are joined by a separator and wrap at the column
  flow(x, y, pieces, o = {}) {
    const size = o.size || 12, lh = o.lh || size * 1.7, sep = o.sep ?? "  "
    let at = x, ly = y
    for (const p of pieces) {
      const w = tw(p.t + sep, size)
      if (at + tw(p.t, size) > W - G && at > x) { at = x; ly += lh }
      this.text(at, ly, p.t, { size, fill: p.fill })
      at += w
    }
    return ly - y + lh
  }
  svg(h) { const H = Math.ceil(Math.max(h || 0, this.h + G)); return { h: H, svg: `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xml:space="preserve" font-family="${FAMILY}"><rect width="100%" height="100%" fill="${P.bg}"/>${this.parts.join("")}</svg>` } }
}

// Usage, from the studio's fixture: the running model, its cumulative token line, and tokens per day.
const snap = MACHINES.desktop(), dep = snap.deployments[0]
const life = snap.life, MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const lived = life.days.slice(0, life.today + 1)
export const USAGE = {
  model: dep.name, agent: dep.agent, folder: "~/Work", gpu: "RTX 3090",
  tokens: MODEL.short(lived.reduce((a, b) => a + b, 0)), requests: String(life.requests), since: life.since,
  tps: Math.round(dep.session.all.decode), prefill: dep.session.all.prefill, ttft: dep.session.all.ttft / 1000,
  line: dep.session.all.line,
  days: lived.slice(-28).map((v, i, a) => {
    const d = new Date(life.start * 1000); d.setDate(d.getDate() + lived.length - a.length + i)
    return { label: `${WD[d.getDay()]} ${MON[d.getMonth()]} ${d.getDate()}`, tokens: v }
  }),
}

export function actions(s, y, main, links = []) {
  const bw = tw(main, 13) + 28, bh = 30
  s.parts.push(`<rect x="${G}" y="${y - 20}" width="${bw}" height="${bh}" rx="3" fill="${P.ink}"/>`)
  s.text(G + bw / 2, y, main, { size: 13, fill: P.bg, anchor: "middle" })
  if (links.length) s.text(G + bw + 16, y, links.join(" · "), { size: 13, fill: P.label })
  return bh
}
// The cumulative token line Sero liked on home.
export function cumulative(s, top, h, pts = USAGE.line) {
  const n = pts.length, mx = Math.max(...pts)
  const xy = pts.map((v, i) => [G + i / (n - 1) * (W - 2 * G), top + h - v / mx * h * .92])
  s.path("M" + xy.map((p) => p.join(",")).join("L") + `L${W - G},${top + h}L${G},${top + h}Z`, { fill: "rgba(221,221,221,0.05)" })
  s.path("M" + xy.map((p) => p.join(",")).join("L"), { stroke: P.value, sw: 1.4 })
  return h
}
// A raw SVG fragment, for anything the Sheet has no helper for (paths, rounded rects, groups).
export const raw = (s, svg) => s.parts.push(svg)

// ---------------------------------------------------------------- lab logos (design/logos, one colour)

const LOGOS = path.join(HERE, "..", "logos")
const logoCache = {}
function logoInner(family) {
  if (!(family in logoCache)) {
    const f = path.join(LOGOS, family + ".svg")
    logoCache[family] = fs.existsSync(f) ? fs.readFileSync(f, "utf8").replace(/^<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "").replace(/<title>.*?<\/title>/, "") : null
  }
  return logoCache[family]
}
// A model's family → its lab's logo at `size`, in `tone`; a family with no logo gets a monogram tile.
export function logo(s, x, y, size, family, tone = P.value) {
  const inner = logoInner(family)
  if (inner) s.parts.push(`<g transform="translate(${x} ${y}) scale(${size / 24})" color="${tone}" fill="${tone}">${inner}</g>`)
  else {
    s.parts.push(`<rect x="${x}" y="${y}" width="${size}" height="${size}" rx="3" fill="none" stroke="${tone}" stroke-width="1"/>`)
    s.text(x + size / 2, y + size * .74, String(family || "?").slice(0, 1).toUpperCase(), { size: size * .7, fill: tone, anchor: "middle" })
  }
  return size + 8
}
// The family of a model name, as the registry groups them
export const familyOf = (name) => {
  const n = String(name).toLowerCase()
  for (const [k, f] of [["swift", "swift"], ["qwen", "qwen"], ["gemma", "gemma"], ["deepseek", "deepseek"], ["glm", "glm"], ["step", "step"], ["kimi", "kimi"], ["minimax", "minimax"], ["mimo", "mimo"], ["nemotron", "nemotron"], ["ling", "ling"], ["hy3", "hunyuan"], ["laguna", "laguna"], ["muse", "muse"], ["leanstral", "mistral"], ["inkling", "inkling"], ["ornith", "ornith"], ["lfm", "lfm"], ["bonsai", "bonsai"]]) if (n.includes(k)) return f
  return "hf"
}
