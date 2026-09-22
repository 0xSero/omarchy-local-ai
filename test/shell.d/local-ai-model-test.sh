#!/bin/bash
# Model.js under node: every view from fixture snapshots, the way Omarchy tests its own Model.js files.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
if ! command -v node >/dev/null 2>&1; then skip "Model.js under node (node is not installed here; CI runs it)"; exit 0; fi

run_node_test "Model.js builds every view from a snapshot" <<'JS'
const M = requireFromRoot("Model.js")
const gpu = { key: "nvidia:0", backend: "nvidia", index: 0, product: "NVIDIA GeForce RTX 4090", vramGb: 24, hardwareId: "rtx-4090-24gb", chosen: true, usedGb: 0.3 }
const card = { hardwareId: "rtx-4090-24gb", backend: "nvidia", product: gpu.product, name: "RTX 4090", vramGb: 24, count: 1, totalGb: 24, keys: ["nvidia:0"], chosen: true, claimed: 0, idle: 1 }
const recipe = { id: "test-a", name: "Test Model", engine: "llama.cpp", sizeGb: 19, ctxTokens: 131072, kvTokens: 131072, caps: { chat: true, tools: true, vision: false, reasoning: false }, onDisk: false, partialBytes: 0, hardwareId: "rtx-4090-24gb", cards: 1, recommended: true, running: false, gate: "" }
const base = { state: "idle", error: "", statusText: "", helpText: "", operation: { name: "", recipeId: "", detail: "", percent: 0, startedAt: "", expectedSeconds: 0 }, hardwareId: "rtx-4090-24gb", gpus: [gpu], cards: [card], recipes: [recipe], models: [], running: null, agents: { default: "pi", directory: "/home/u", installed: ["pi", "claude"], launchable: [] }, selected: null, reason: "", port: { number: 12434, busy: false, listener: "none" } }
const c = (snap, extra) => Object.assign({ snap, view: "home", hw: "", count: 1, slotSel: "", launcherOpen: false, agentPick: "", agentOpen: false, pending: false, lastVerb: "", elapsed: 0, localError: "" }, extra || {})

// home, idle
let o = M.build(c(base))
assertEqual(o.tone, "idle"); assertEqual(o.title, "Local AI"); assert(o.sub.indexOf("1 cards free") === 0, o.sub)
assert(o.rows.some(r => r.action === "gpu:rtx-4090-24gb"), "a card row opens the card view")
assert(o.rows.some(r => r.label === "open agent" && r.disabled), "no agent without a model")

// card view: one row per recipe, and that row is the action
o = M.build(c(base, { view: "card", hw: "rtx-4090-24gb" }))
assertEqual(o.tone, "idle"); assertEqual(o.title, "RTX 4090")
const load = o.rows.filter(r => r.action === "run:test-a:1")[0]
assert(load, "the recipe row carries the load action"); assertEqual(load.value, "Download & run · 19 GB"); assert(/128K ctx/.test(load.detail), load.detail)
assertDeepEqual(M.loadPlan(base, recipe, card).keys, ["nvidia:0"])

// a gated recipe is not an action
o = M.build(c(Object.assign({}, base, { recipes: [Object.assign({}, recipe, { gate: "needs NVIDIA driver 575.0 or newer" })] }), { view: "card", hw: "rtx-4090-24gb" }))
const gated = o.rows.filter(r => r.label === "Test Model")[0]
assertEqual(gated.action, ""); assert(gated.disabled, "gated row is disabled"); assert(/575/.test(gated.detail), gated.detail)

// working: download in progress
const working = Object.assign({}, base, { state: "download", operation: { name: "download", recipeId: "test-a", detail: "3 / 19 GB · file 1 of 4", percent: 16, startedAt: new Date().toISOString(), expectedSeconds: 0 }, selected: { recipeId: "test-a", name: "Test Model", onDisk: false, keys: ["nvidia:0"] } })
o = M.build(c(working, { elapsed: 42 }))
assertEqual(o.tone, "work"); assertEqual(o.eyebrow, "downloading"); assertEqual(o.title, "Test Model")
assert(o.rows[0].type === "status" && /16%/.test(o.rows[0].value), JSON.stringify(o.rows[0]))
assert(o.rows[1].type === "bar" && o.rows[1].percent === 16, "a bar with the percent")
assert(o.foot.some(r => r.action === "stop-download"), "a download can be stopped")
assert(M.isWorking(c(working)), "working")

// starting: the claimed card is marked
const starting = Object.assign({}, working, { state: "starting", operation: Object.assign({}, working.operation, { name: "starting", detail: "loading the model", percent: 0 }) })
o = M.build(c(starting))
assertEqual(o.eyebrow, "starting")
assert(o.rows.some(r => r.cells && r.cells.some(x => x.mark === "claimed")), "the card shows as claimed")

// ready: a model runs
const model = { recipeId: "test-a", baseRecipeId: "test-a", name: "Test Model", port: 12434, endpoint: "http://127.0.0.1:12434/v1", keys: ["nvidia:0"], cards: 1, state: "ready", note: "", servedModel: "Test-Model", apis: ["chat", "messages"], caps: recipe.caps, ctxTokens: 131072, kvTokens: 131072, acceptedAt: "2026-09-22T10:00:00Z", startedAt: "", launchable: ["pi", "claude"] }
const ready = Object.assign({}, base, { state: "ready", models: [model], running: { recipeId: "test-a", name: "Test Model", cards: 1, port: 12434, state: "ready" }, recipes: [Object.assign({}, recipe, { onDisk: true, running: true })] })
o = M.build(c(ready))
assertEqual(o.tone, "ready"); assertEqual(o.title, "Test Model"); assertEqual(o.sub, "on 1 of 1 cards")
assert(o.rows.some(r => r.action === "open-agent:pi:test-a"), "the default agent opens on the model")
o = M.build(c(ready, { view: "model", slotSel: "test-a" }))
assertEqual(o.eyebrow, "ready"); assert(o.foot.some(r => r.action === "stop:test-a"), "stop in the footer")
assert(o.rows.some(r => r.type === "stat" && r.stat[0].k === "context"), "context and kv figures")
assert(o.rows.some(r => r.chips && r.chips.some(x => x.text === "tools" && !x.off)), "capabilities as chips")
o = M.build(c(ready, { view: "card", hw: "rtx-4090-24gb" }))
const reload = o.rows.filter(r => r.action === "run:test-a:1")[0]
assertEqual(reload.value, "Reload · 19 GB")
assert(o.rows.some(r => r.action === "model:test-a"), "the running model row opens the model view")

// error after a failed start
const failed = Object.assign({}, base, { state: "error", error: "chat acceptance failed", selected: { recipeId: "test-a", name: "Test Model", onDisk: true, keys: [] } })
o = M.build(c(failed))
assertEqual(o.tone, "error"); assertEqual(o.title, "acceptance failed")
assert(o.rows.some(r => r.action === "run-again" && !r.disabled), "run again is offered")
assert(o.rows.some(r => r.action === "log"), "the log is offered")
assertEqual(M.shortError(c(Object.assign({}, base, { error: "decode 2 tok/s: the GPU is not being used" }))), "too slow")
assertEqual(M.shortError(c(Object.assign({}, base, { error: "the password prompt was dismissed; nothing was changed" }))), "refused")

// unsupported GPU: a status line, not an error
const unsupported = Object.assign({}, base, { hardwareId: "", statusText: "Unsupported GPU", helpText: "no validated recipe for NVIDIA GeForce RTX 3050 yet", reason: "no validated recipe for NVIDIA GeForce RTX 3050 yet", recipes: [], cards: [Object.assign({}, card, { hardwareId: "", name: "RTX 3050", recipe: null })] })
o = M.build(c(unsupported))
assertEqual(o.tone, "error"); assertEqual(o.title, "no recipe")

// working: navigation is not offered; the card shows the operation
o = M.build(c(starting, { view: "card", hw: "rtx-4090-24gb" }))
assertEqual(o.tone, "work"); assert(!o.rows.some(r => /^run:/.test(r.action)), "no loads while working")
JS
