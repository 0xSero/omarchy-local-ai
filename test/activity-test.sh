#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "$ROOT/Model.js" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const context = {module: {exports: {}}};
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), context);
const s = {gpus: [], kinds: [{keys: [], free: [], groups: [], models: []}], deployments: [], total: 4, life: {
  requests: 1, start: 1777852800, since: 'May 4', today: 2, days: [0, 4, 0, 99, 0, 0, 0]
}};
const row = context.module.exports.build(s, {view: 'home'}).rows.find(r => r.type === 'life');
// three days of history, after 19 empty weeks so the grid is always 20 weeks
assert.equal(row.cells.length, 19 * 7 + 3);
assert.equal(row.labels.length, 19 * 7 + 3);
assert.deepEqual(row.cells.slice(-3), [0, 4, 0]);
assert(/  4 tokens$/.test(row.labels[19 * 7 + 1]));
console.log('ok - activity ends today and ignores future entries when shading history');
const empty = context.module.exports.build({...s, total: 0, life: {requests: 0, days: []}}, {view: 'home'}).rows.find(r => r.type === 'life');
assert.equal(empty.type, 'life');
assert.equal(Math.ceil(empty.cells.length / 7), 20);
assert(empty.cells.every(c => c === 0));
assert.equal(empty.since, 'nothing run yet');
console.log('ok - before any use the grid is there, empty, 20 weeks ending today');
assert.equal(Math.ceil(context.module.exports.build({...s, total: 0, life: {requests: 0, days: []}}, {view: 'home', wide: true}).rows.find(r => r.type === 'life').cells.length / 7), 53);
console.log('ok - full screen shows a year');
for (const state of ['needs-setup', 'docker-down', 'unsupported']) assert.equal(context.module.exports.build({...s, readiness: {state}}, {view: 'home'}).rows[0].type, 'life');
const soon = context.module.exports.build({...s, kinds: [], gpus: [{name: 'Arc Pro B70'}, {name: 'Arc Pro B70'}, {name: 'RTX 3090'}]}, {view: 'home'}).rows;
assert.equal(soon[0].type, 'life');
assert.deepEqual(soon.filter(r => r.type === 'field').map(r => r.label + '=' + r.value), ['2 × Arc Pro B70=no tested model yet', 'RTX 3090=no tested model yet']);
console.log('ok - setup and no-tested-model screens are home too, with the grid on top');
JS
