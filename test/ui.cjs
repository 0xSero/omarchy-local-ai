const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ui = {};
vm.runInNewContext(fs.readFileSync((process.argv[2] || __dirname + '/..') + '/ui/ui.js', 'utf8').replace(/^\.pragma library\s*/, ''), ui);
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

// Models are children of the GPU group they use; free groups remain selectable.
const running = {...recipe, recipeId: recipe.id, state: 'ready', keys: ['intel-xpu:0','intel-xpu:1'], port: 12434, decodeTps: 42};
const snap = {state: 'ready', operation: {}, models: [running], gpus: [],
  cards: [{hardwareId: 'b70', name: 'B70', count: 2, keys: running.keys},
    {hardwareId: '3090', name: 'RTX 3090', count: 1, keys: ['nvidia:0']}],
  recipes: [recipe, {...recipe, id: 'qwen-single', hardwareId: '3090', cards: 1}]};
const home = ui.build({snap, view: 'home', localError: ''});
assert.equal(home.rows[0].label, 'gpus');
assert.equal(home.rows[1].label, '2× B70');
assert.equal(home.rows[2].action, 'model:qwen-tp2');
assert.equal(home.rows[2].child, true);
assert.equal(home.rows[3].label, '1× RTX 3090');
const locked = home.rows.find(r => r.label === '2× B70');
assert.equal(locked.value, '2 locked');
assert.equal(locked.action, '');
assert(locked.cells.every(c => /locked/.test(c.text)));
assert.equal(home.rows.find(r => r.label === '1× RTX 3090').action, 'card:3090');
const idle = ui.build({snap: {...snap, models: []}, view: 'home', localError: ''});
assert.equal(idle.rows[0].label, 'gpus');
assert.equal(idle.rows.find(r => r.label === '2× B70').action, 'card:b70');
const second = {...running, recipeId: 'qwen-single', keys: ['nvidia:0'], cards: 1, port: 12435};
const two = ui.build({snap: {...snap, models: [second, running]}, view: 'home', localError: ''});
assert.equal(two.rows[2].action, 'model:qwen-tp2');
assert.equal(two.rows[4].action, 'model:qwen-single');
assert.equal(two.rows.filter(r => r.child).length, 2);
const crashed = ui.build({snap: {...snap, models: [{...running, state: 'error'}]}, view: 'home', localError: ''});
assert.equal(crashed.rows[2].value, 'crashed ›');
assert(crashed.rows[1].cells.every(c => c.mark === 'crashed'));
console.log('UI GPU grouping, model ownership and lock checks passed');
