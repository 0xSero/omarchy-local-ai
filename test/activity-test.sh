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
const it = context.module.exports.build(s, {tab: 'home'}).items;
const bars = it.find(i => i.type === 'bars'), top = it.find(i => i.type === 'top');
assert.equal(bars.values.length, 3);
assert.equal(bars.labels.length, 3);
assert.equal(bars.values[1], 4);
assert.deepEqual(Array.from(top.line), [0, 4, 4]);
console.log('ok - usage ends today and ignores future entries, as bars and as the cumulative line');
JS
