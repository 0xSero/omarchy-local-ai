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
const row = context.module.exports.build(s, {view: 'home'}).rows[0];
assert.equal(row.cells.length, 3);
assert.equal(row.labels.length, 3);
assert.equal(row.cells[1], 4);
assert.equal(row.months.length, 1);
console.log('ok - activity ends today and ignores future entries when shading history');
JS
