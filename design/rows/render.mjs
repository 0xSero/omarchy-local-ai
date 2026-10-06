// node design/rows/render.mjs <row file> [<out dir>]: draw every screen of one row to SVG.
// A row file exports `ROW = { id, title, primitive, idea, screens: [{ id, title, draw }] }`, each draw()
// returning a Sheet's svg() ({ svg, h }). design/rows/render.sh turns them into PNGs and one strip per row.
import fs from "node:fs"
import path from "node:path"
import { pathToFileURL } from "node:url"

const file = path.resolve(process.argv[2] || "")
const { ROW } = await import(pathToFileURL(file).href)
if (!ROW || !Array.isArray(ROW.screens) || !ROW.screens.length) { console.error("row: export ROW with screens"); process.exit(1) }
const out = path.resolve(process.argv[3] || path.join(path.dirname(file), "out", ROW.id))
fs.rmSync(out, { recursive: true, force: true })
fs.mkdirSync(out, { recursive: true })
const meta = { id: ROW.id, title: ROW.title, primitive: ROW.primitive, idea: ROW.idea, screens: [] }
ROW.screens.forEach((sc, i) => {
  const r = sc.draw()
  const name = `${String(i + 1).padStart(2, "0")}-${sc.id}`
  fs.writeFileSync(path.join(out, name + ".svg"), r.svg)
  if (r.svg.match(/width="(\d+)"/)[1] !== "340") console.error(`warning: ${name} is not 340 px wide`)
  meta.screens.push({ id: sc.id, title: sc.title, file: name, h: r.h })
  console.log(`${name} 340x${r.h}`)
})
fs.writeFileSync(path.join(out, "row.json"), JSON.stringify(meta, null, 1))
