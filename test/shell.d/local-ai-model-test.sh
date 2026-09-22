#!/bin/bash
# Model.js under node: every view from fixture snapshots, the way Omarchy tests its own Model.js files.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
if ! command -v node >/dev/null 2>&1; then skip "Model.js under node (node is not installed here; CI runs it)"; exit 0; fi

run_node_test "Model.js builds every view from a snapshot" <<'JS'
const M = requireFromRoot("Model.js")
const gpu = (i, used) => ({ key: "nvidia:" + i, backend: "nvidia", index: i, product: "NVIDIA GeForce RTX 3090", vramGb: 24, hardwareId: "rtx-3090-24gb", chosen: i === 0, usedGb: used, tempC: 40 + i, utilPct: 0 })
const recipe = { id: "test-a", name: "Qwen3.8-27B", engine: "tabbyapi", sizeGb: 15.6, ctxTokens: 262144, caps: { chat: true, tools: true, vision: true, reasoning: true }, onDisk: false, partialBytes: 0, hardwareId: "rtx-3090-24gb", cards: 1, recommended: true, running: false, gate: "" }
const card = { hardwareId: "rtx-3090-24gb", backend: "nvidia", product: gpu(0).product, name: "RTX 3090", vramGb: 24, count: 2, totalGb: 48, keys: ["nvidia:0", "nvidia:1"], chosen: true, claimed: 0, idle: 2, recipe: recipe }
const stats = { today: 412000, days: [30, 55, 80, 20, 45, 100, 62], byModel: [{ model: "Qwen3.8-27B", tokens: 392 }], decode: 78, hours: Array(24).fill(70) }
const base = { state: "idle", error: "", statusText: "", helpText: "", operation: { name: "", recipeId: "", detail: "", percent: 0, startedAt: "", expectedSeconds: 0 }, hardwareId: "rtx-3090-24gb",
  gpus: [gpu(0, 0.3), gpu(1, 0.1)], cards: [card], recipes: [recipe], models: [], running: null, agents: { default: "claude", directory: "/home/u/code/thing", installed: ["claude", "pi"], launchable: [] }, selected: null, reason: "", stats: stats }
const c = (snap, extra) => Object.assign({ snap, view: "home", pending: false, lastVerb: "", elapsed: 0, localError: "" }, extra || {})
const types = o => o.rows.map(r => r.type)

// idle: hero, the week of tokens, the GPUs, one run row per card type
let o = M.build(c(base))
assertEqual(o.hero.tone, "idle"); assertEqual(o.hero.title, "Local AI"); assertEqual(o.hero.sub, "2 GPUs"); assertEqual(o.hero.rightAction, "stats")
assert(types(o).indexOf("bars") >= 0, "the week of tokens shows when idle")
assertEqual(o.rows.filter(r => r.type === "gpu").length, 2)
assertEqual(o.rows.filter(r => r.type === "gpu")[0].temp, "40°")
const run = o.rows.filter(r => r.action === "run:test-a")[0]
assert(run && run.verb === "download & run" && /15\.6 GB/.test(run.small), JSON.stringify(run))
assert(!o.rows.some(r => r.action === "open-agent"), "no agent row without a model")
assertDeepEqual(M.loadKeys(base, "test-a"), ["nvidia:1"])   // the freest card

// on disk: the verb is run
o = M.build(c(Object.assign({}, base, { recipes: [Object.assign({}, recipe, { onDisk: true })], cards: [Object.assign({}, card, { recipe: Object.assign({}, recipe, { onDisk: true }) })] })))
assertEqual(o.rows.filter(r => r.action === "run:test-a")[0].verb, "run")

// gated: a dim row, no action
o = M.build(c(Object.assign({}, base, { cards: [Object.assign({}, card, { recipe: Object.assign({}, recipe, { gate: "needs NVIDIA driver 575.0 or newer" }) })] })))
const gated = o.rows.filter(r => r.label === "Qwen3.8-27B")[0]
assert(gated && gated.disabled && /575/.test(gated.small), JSON.stringify(gated))

// downloading: a progress row, the download row says stop
const working = Object.assign({}, base, { state: "download", operation: { name: "download", recipeId: "test-a", detail: "3 / 16 GB · file 1 of 4", percent: 39, startedAt: new Date().toISOString(), expectedSeconds: 0 }, selected: { recipeId: "test-a", name: "Qwen3.8-27B" } })
o = M.build(c(working, { elapsed: 134 }))
assertEqual(o.hero.eyebrow, "DOWNLOADING"); assertEqual(o.hero.title, "Qwen3.8-27B")
const prog = o.rows.filter(r => r.type === "prog")[0]
assert(prog && prog.pct === 39 && /6\.1 GB of 15\.6 GB/.test(prog.left) && prog.right === "2:14", JSON.stringify(prog))
assert(o.rows.some(r => r.action === "stop-download"), "the download can be stopped")
assert(!o.rows.some(r => /^run:/.test(r.action)), "no loads while working")
assert(M.isWorking(c(working)), "working")

// ready: two figures, the bars, busy GPUs, the agent row, stop
const model = { recipeId: "test-a", name: "Qwen3.8-27B", port: 12434, keys: ["nvidia:0"], cards: 1, state: "ready", note: "", servedModel: "Qwen3.8-27B", apis: ["chat", "messages"], launchable: ["claude", "pi"] }
const ready = Object.assign({}, base, { state: "ready", models: [model], running: { recipeId: "test-a" }, gpus: [gpu(0, 18.5), gpu(1, 0.1)] })
o = M.build(c(ready))
assertEqual(o.hero.tone, "ready"); assertEqual(o.hero.title, "Qwen3.8-27B"); assertEqual(o.hero.sub, "RTX 3090 #0")
const num = o.rows.filter(r => r.type === "num2")[0]
assertEqual(num.a.v, "78"); assertEqual(num.b.v, "412K")
const g = o.rows.filter(r => r.type === "gpu")
assert(g[0].busy && !g[1].busy && g[0].pct === 77 && g[0].used === "19", JSON.stringify(g[0]))
const ag = o.rows.filter(r => r.action === "open-agent")[0]
assert(ag && ag.label === "claude" && ag.small === "~/code/thing", JSON.stringify(ag))
assert(o.rows.some(r => r.action === "stop:test-a" && r.verb === "stop"), "stop on the model row")
assert(o.rows.some(r => r.action === "run:test-a"), "the free card of the same type can run another")

// failed: the reason as text, run again and the log
const failed = Object.assign({}, base, { state: "error", error: "acceptance failed: decode 2 tok/s, the GPU is not being used", selected: { recipeId: "test-a", name: "Qwen3.8-27B" } })
o = M.build(c(failed))
assertEqual(o.hero.tone, "error"); assertEqual(o.hero.eyebrow, "FAILED"); assertEqual(o.hero.sub, "too slow")
assert(o.rows.some(r => r.type === "text" && /GPU is not being used/.test(r.text)), "the reason")
assert(o.rows.some(r => r.action === "run:test-a" && r.verb === "run again"), "run again")
assert(o.rows.some(r => r.action === "log"), "the log")
assertEqual(M.shortError("the password prompt was dismissed; nothing was changed"), "refused")

// unsupported GPU: a status line, no run row
o = M.build(c(Object.assign({}, base, { hardwareId: "", statusText: "Unsupported GPU", helpText: "no validated recipe for NVIDIA GeForce RTX 3050 yet", reason: "no validated recipe for NVIDIA GeForce RTX 3050 yet", recipes: [], cards: [Object.assign({}, card, { hardwareId: "", name: "RTX 3050", recipe: null })] })))
assert(o.rows.some(r => r.type === "text" && /3050/.test(r.text)), "the status")
assert(!o.rows.some(r => /^run:/.test(r.action)), "nothing to run")

// stats: by day with an axis, by model, decode over the day
o = M.build(c(ready, { view: "stats" }))
assertEqual(o.hero.eyebrow, "STATS"); assertEqual(o.hero.rightAction, "back")
assertDeepEqual(types(o).slice(0, 3), ["h", "bars", "axis"])
assertEqual(o.rows[0].right, "392")
assert(o.rows.some(r => r.type === "hbar" && r.label === "Qwen3.8-27B" && r.pct === 100), "by model")
assert(o.rows.some(r => r.type === "spark" && r.values.length === 24), "decode over 24 h")

// open: agents as options, the folder field, the one action
o = M.build(c(ready, { view: "open" }))
assertEqual(o.hero.eyebrow, "OPEN")
const opts = o.rows.filter(r => r.type === "opt")
assert(opts.length === 2 && opts[0].on && opts[0].action === "agent:claude", JSON.stringify(opts))
assert(o.rows.some(r => r.type === "field" && r.value === "/home/u/code/thing"), "the folder field")
assert(o.rows.some(r => r.action === "open-agent" && r.label === "open claude"), "the open row")
assertEqual(M.build(c(base, { view: "open" })).hero.eyebrow, "IDLE")   // nothing to open on: home
JS
