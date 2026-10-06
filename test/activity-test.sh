#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "$ROOT/Model.js" <<'JS'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const context = {module: {exports: {}}};
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), context);
const s = {gpus: [], kinds: [{keys: [], free: [], groups: [], models: []}], deployments: [], total: 103, life: {
  requests: 1, start: 1777852800, since: 'May 4', today: 3, days: [0, 4, 0, 99, 0, 0, 0]
}};
const v = context.module.exports.build(s, {tab: 'home'}), cal = v.items.find(i => i.type === 'calendar');
// the record ends today: days still to come are not drawn, and today is the last cell drawn
assert.deepEqual(Array.from(v.header.line), [0, 4, 4, 103]);
assert.equal(cal.cells.filter(x => x >= 0).length, 4);
assert.equal(cal.cells[cal.today], 4);
assert.equal(cal.cells.slice(cal.today + 1).filter(x => x >= 0).length, 0);
console.log('ok - usage ends today and ignores future entries, in the line and the calendar');
JS
