const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ui = {};
vm.runInNewContext(fs.readFileSync(__dirname + '/../ui.js', 'utf8').replace(/^\.pragma library\s*/, ''), ui);
const chips = ui.capabilities({chat: true, vision: true, video: true, tools: false}).chips;
assert.equal(chips.find(x => x.text === 'video').off, false);
assert.equal(chips.find(x => x.text === 'tools').off, true);
assert(chips.some(x => x.text === 'reasoning ?'));
const recipe = {id: 'qwen-tp2', name: 'Qwen', hardwareId: 'b70', cards: 2, ctxTokens: 262144, caps: {vision: true, video: true}};
const result = ui.build({snap: {state: 'idle', operation: {}, models: [], gpus: [],
  cards: [{hardwareId: 'b70', name: 'B70', count: 2, keys: ['intel-xpu:0','intel-xpu:1'], vramGb: 32}], recipes: [recipe]},
  view: 'card', hw: 'b70', count: 2, pick: 'qwen-tp2', localError: ''});
assert(result.rows.some(r => r.label === 'context' && r.value === '256K per request'));
assert(result.rows.some(r => r.chips && r.chips.some(c => c.text === 'video' && !c.off)));
console.log('UI context, video and unknown capability checks passed');
