#!/bin/bash
# View8.js: pages from a real snapshot say only what the snapshot holds.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v node >/dev/null || { echo 'ok - View8 pages # SKIP node is not installed'; exit 0; }
node - "$ROOT/View8.js" "$ROOT/test/fixtures/snapshot-2xb70.json" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = { module: { exports: {} } }
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), c)
const v = c.module.exports, base = JSON.parse(fs.readFileSync(process.argv[3]))
const clone = (x) => JSON.parse(JSON.stringify(x))
let failed = 0
const test = (n, f) => { try { f(); console.log('ok - ' + n) } catch (e) { failed++; console.error('not ok - ' + n + ': ' + e.message) } }
const rows = (p) => p.cards.flatMap((c) => c.rows)
const qwen = base.kinds[0].models[0]
test('the hands are the 178 × 24 brand grid, drawn in from the edges', () => {
  const first = v.hands(0).split('\n'), done = v.hands(200).split('\n')
  assert.equal(done.length, 24); assert(done.every((l) => l.length === 178))
  assert(first.every((l) => !/[●·]/.test(l))); assert(done.join('').includes('●'))
})
test('connect shows the cards found and Continue once the hands are drawn', () => {
  const r = rows(v.build(base, { page: 'connect' }))
  assert(r.some((x) => x.afterDrawn && x.text === '2 × B70'))
  assert(r.some((x) => x.type === 'buttons' && x.items[0].action === 'page|main'))
})
test('setup needed: every page becomes connect with Set up Local AI', () => {
  const s = clone(base); s.readiness = { state: 'needs-setup' }
  const p = v.build(s, { page: 'main' })
  assert.equal(p.name, 'connect'); assert(rows(p).some((x) => x.type === 'buttons' && x.items[0].action === 'setup'))
})
test('the tree: a set of two B70s has a both-cards branch and a branch per card; the one in use says so', () => {
  const r = rows(v.build(base, { page: 'tree' }))
  assert(r.some((x) => x.label === 'both cards')); assert(r.some((x) => x.label === 'B70 #1'))
  assert(r.some((x) => x.label === 'B70 #2' && x.mid === 'in use'))
})
test('the tree tells recipes of one model apart', () => {
  const r = rows(v.build(base, { page: 'tree', more: { 'intel-arc-pro-b70-32gb/intel-xpu:0': true } }))
  const flash = r.filter((x) => (x.label || '').startsWith('Qwen3.8-Flash-Next'))
  assert(flash.length > 1); assert.equal(new Set(flash.map((x) => x.label)).size, flash.length, flash.map((x) => x.label).join(' / '))
})
test('a model page shows no speed it did not measure', () => {
  const p = v.build(base, { page: 'model', id: qwen.id, keys: 'intel-xpu:0' })
  assert(!rows(p).some((x) => x.type === 'figs' || x.type === 'bars'))
  assert.equal(p.foot.items[0].action, 'run|' + qwen.id + '|intel-xpu:0')
})
test('a model on a card in use cannot be loaded there', () => {
  const p = v.build(base, { page: 'model', id: qwen.id, keys: 'intel-xpu:1' })
  assert.equal(p.foot.items.length, 0); assert(/in use/.test(p.foot.note))
})
test('first time: the best model for each card set', () => {
  const s = clone(base); s.life = { days: [], today: 0, requests: 0 }
  const p = v.build(s, { page: 'main' })
  assert.equal(rows(p)[0].text, 'Ready'); assert(rows(p).some((x) => x.button && x.button.label === 'Load'))
})
test('several running: one card per model, a stopped one says why', () => {
  const s = clone(base)
  s.deployments = [Object.assign({}, qwen, { keys: ['intel-xpu:0'], state: 'ready', session: { all: { decode: 40 } } }),
    Object.assign({}, qwen, { id: qwen.id + '--2', keys: ['intel-xpu:1'], state: 'error', error: 'out of memory' })]
  const p = v.build(s, { page: 'main' })
  assert.equal(p.cards.filter((c) => c.rows[0].type === 'block').length, 2)
  assert(rows(p).some((x) => x.error === 'out of memory')); assert.equal(p.mark, 'failed')
})
test('settings: usage counts switch, agent updates listed, Report a bug', () => {
  const p = v.build(base, { page: 'settings' })
  assert(rows(p).some((x) => x.label === 'usage counts' && x.button.action === 'set|ping|on'))
  assert(rows(p).some((x) => x.label === 'Claude Code' && /→/.test(x.value)))
  assert.equal(p.foot.items[0].action, 'report')
})
process.exit(failed ? 1 : 0)
JS
