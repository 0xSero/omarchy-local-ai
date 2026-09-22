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
  view: 'card', hw: 'b70', count: 2, localError: ''});
const oneRow = result.rows.find(r => r.action === 'run:qwen-tp2:2');
assert(/256K ctx/.test(oneRow.detail), 'the model row carries its context');
assert(/ · video/.test(oneRow.detail), 'the model row carries a capability the recipe passed');
assert(/ · tools\?/.test(oneRow.detail), 'a capability the recipe does not declare stays unknown');
console.log('UI context, video and unknown capability checks passed');

// GPU rows stay navigable while occupied. The model list respects physical
// capacity and never offers a load onto occupied GPUs.
const running = {...recipe, recipeId: recipe.id, state: 'ready', keys: ['intel-xpu:0','intel-xpu:1'], port: 12434, decodeTps: 42};
const snap = {state: 'ready', operation: {}, models: [running], gpus: [],
  cards: [{hardwareId: 'b70', name: 'B70', count: 2, keys: running.keys, vramGb: 32},
    {hardwareId: '3090', name: 'RTX 3090', count: 1, keys: ['nvidia:0'], vramGb: 24}],
  recipes: [recipe, {...recipe, id: 'qwen-single', hardwareId: '3090', cards: 1}]};
const home = ui.build({snap, view: 'home', localError: ''});
const gpuRows = home.rows.filter(r => r.action.startsWith('gpu:'));
assert.equal(gpuRows.length, 2);
assert.equal(gpuRows[0].action, 'gpu:b70');
assert.equal(gpuRows[0].value, 'Models ›');
assert.equal(gpuRows[1].action, 'gpu:3090');
assert.equal(gpuRows[1].value, 'Models ›');
const crashed = ui.build({snap: {...snap, models: [{...running, state: 'error'}]}, view: 'home', localError: ''});
assert.equal(crashed.rows.find(r => r.action === 'gpu:b70').status, 'error');
assert(!crashed.rows.find(r => r.action === 'gpu:b70').devices);
const catalog = ui.build({snap, view: 'card', hw: 'b70', count: 2, localError: ''});
assert(catalog.rows.some(r => r.action === 'model:qwen-tp2'));
assert(catalog.rows.some(r => r.tabs && r.tabs.some(t => t.action === 'count:2')));
assert(!catalog.rows.some(r => r.label.startsWith('2× B70')), 'the GPU page does not repeat the card as a row');
assert(/of 2 free/.test(catalog.sub), 'the card page names its per-card state in the subtitle');
assert.equal(catalog.foot.length, 0);
assert(!catalog.rows.some(r=>r.action.startsWith('run:')), 'a model that would replace the running one is not offered');
const available = ui.build({snap: {...snap, models: []}, view: 'card', hw: 'b70', count: 2, localError: ''});
assert(available.rows.some(r=>r.action==='run:qwen-tp2:2'));
const noFit = ui.build({snap, view: 'card', hw: 'b70', count: 1, localError: ''});
assert(!noFit.rows.some(r => r.action.startsWith('run:')), 'no model fits one GPU of this card');
assert(noFit.rows.some(r => r.action === 'model:qwen-tp2'), 'the running model still opens');
const stats = ui.build({snap, view: 'model', slotSel: recipe.id, localError: ''});
assert(stats.path.some(r => r.action === 'card:b70'));
assert(!stats.rows.some(r=>r.tabs));
const partial = {...snap, models: [{...running, keys: ['intel-xpu:0'], cards: 1}]};
assert.equal(ui.build({snap: partial, view: 'home', localError: ''}).rows.find(r => r.action === 'gpu:b70').status, '1 available');
const multiple = {...snap, models: [
  {...running, recipeId: 'first', keys: ['intel-xpu:0'], cards: 1},
  {...running, recipeId: 'second', keys: ['intel-xpu:1'], cards: 1}
]};
const multipleView = ui.build({snap: multiple, view: 'card', hw: 'b70', count: 1, localError: ''});
assert(multipleView.rows.some(r => r.action === 'model:first'));
assert(multipleView.rows.some(r => r.action === 'model:second'));
console.log('UI GPU status, navigation, capacity and occupied-load checks passed');

// The update row is the only way an update happens from the card: something staged is the update
// verb, nothing staged is a plain check, and a disabled check leaves the card alone.
const staged = ui.build({snap: {...snap, update: {enabled: true, plugin: {current: '5.0.0', latest: '5.1.0'}, recipes: {new: 2, relevant: 1}}}, view: 'home', localError: ''});
assert.equal(staged.foot.length, 1);
assert.equal(staged.foot[0].action, 'update');
assert.equal(staged.foot[0].kind, 'primary');
assert(/v5\.1\.0/.test(staged.foot[0].value) && /1 for your card/.test(staged.foot[0].value));
const registryOnly = ui.build({snap: {...snap, update: {enabled: true, plugin: {current: '5.0.0', latest: ''}, recipes: {staged: true, new: 0, relevant: 0}}}, view: 'home', localError: ''});
assert.equal(registryOnly.foot[0].action, 'update');
assert.equal(registryOnly.foot[0].kind, 'primary');
assert(/^registry ›/.test(registryOnly.foot[0].value));
const current = ui.build({snap: {...snap, update: {enabled: true, plugin: {current: '5.0.0', latest: ''}, recipes: {new: 0, relevant: 0}}, registryFile: {checkedAt: Math.floor(Date.now() / 1000) - 300}}, view: 'home', localError: ''});
assert.equal(current.foot[0].action, 'update-check');
assert(/^current · checked \d+m ago/.test(current.foot[0].value));
assert.equal(ui.build({snap: {...snap, update: {enabled: false}}, view: 'home', localError: ''}).foot.length, 0);
assert.equal(ui.build({snap, view: 'card', hw: 'b70', count: 1, localError: ''}).foot.some(r => r.action === 'update'), false);
console.log('UI update row checks passed');

// Meter data must retain missing sensors and reflect per-device readings.
const sensors = {...snap, gpus: [{key: 'intel-xpu:0', tempC: 41, utilPct: null, usedGb: null, vramGb: 32},
  {key: 'nvidia:0', tempC: 72, utilPct: 0, usedGb: 18, vramGb: 24}]};
const overview = ui.build({snap: sensors, view: 'home', localError: ''});
assert(overview.rows.filter(r => r.action.startsWith('gpu:')).every(r => r.compact && !r.devices && !r.cells));
const meters = sensors.cards.map(c => ({devices: ui.devices(sensors, c.keys)}));
assert.equal(meters[0].devices[0].meters[0].fraction, 0.41);
assert.equal(meters[0].devices[0].meters[1].fraction, null);
assert.equal(meters[0].devices[0].meters[2].value, 'N/A');
assert.equal(meters[1].devices[0].meters[1].value, '0%');
assert.equal(meters[1].devices[0].meters[2].fraction, 0.75);
assert.equal(meters[1].devices[0].meters[2].value, '18/24 GB');
assert.equal(ui.meter('Usage', 110, 100, '%').fraction, 1);
assert.equal(ui.meter('Temp', -1, 100, '°C').fraction, null);
const launch = ui.build({snap: {...sensors, agents: {default: 'omp'}, models: [{...running, launchable: ['pi', 'omp']}]}, view: 'model', slotSel: recipe.id, localError: ''});
const index = action => launch.rows.findIndex(r => r.action === action);
assert(index('agent-toggle') < index('open-agent:omp:qwen-tp2'));
assert(index('open-agent:omp:qwen-tp2') < launch.rows.findIndex(r => r.type === 'stat'));
assert(!launch.foot.some(r => r.action.startsWith('open-agent:')));
assert(launch.rows.some(r => r.devices && r.devices.length === running.keys.length));
console.log('GPU meter accuracy, missing sensors and top agent controls passed');

// The home launcher targets a ready model explicitly and shares the detail launcher.
const first = {...running, launchable: ['pi', 'opencode', 'crush']};
const second = {...first, recipeId: 'other', keys: ['nvidia:0'], launchable: ['pi', 'crush']};
const launchSnap = {...snap, models: [first, second], running: {recipeId: first.recipeId}, agents: {default: 'opencode'}};
const main = extra => ui.build({snap: launchSnap, view: 'home', localError: '', launcherOpen: true, ...extra});
assert(main().rows.some(r => r.action === 'open-agent:opencode:qwen-tp2'));
assert(main({launchPick: 'other', agentPick: 'crush'}).rows.some(r => r.action === 'open-agent:crush:other'));
assert(main({launchPick: 'other'}).rows.some(r => r.action === 'open-agent:pi:other'));
assert(main({launchPick: 'gone'}).rows.some(r => r.action === 'open-agent:opencode:qwen-tp2'));
assert(main({launchModelOpen: true}).rows.some(r => r.action === 'launch-model:other'));
assert(main({agentOpen: true}).rows.some(r => r.action === 'agent:crush'));
assert(!ui.build({snap: {...launchSnap, models: [{...first, state: 'error'}]}, view: 'home', localError: ''}).rows.some(r => r.action.startsWith('open-agent:')));
console.log('Main-screen agent selection, model routing and stale selection checks passed');

assert(main({launcherOpen: false}).rows.some(r => r.action === 'launcher-toggle'));
assert(main({launcherOpen: false}).rows.some(r => r.action === 'open-agent:opencode:qwen-tp2'));

// Totals include prior days and unloaded models, counting a multi-GPU allocation once.
const usage = {gpuUsage: [
  {keys:['nvidia:0','nvidia:1'], days:{'2026-09-19':100}, estimated:true, since:'2026-09-19'},
  {keys:['nvidia:1'], days:{'2026-09-20':70}, since:'2026-09-20'},
  {hardwareId:'rtx', days:{'2026-09-18':30}, since:'2026-09-18'},
  {keys:['intel-xpu:0'], days:{'2026-09-20':900}, since:'2026-09-20'}
]};
const totals = ui.gpuUsage(usage, {keys:['nvidia:0','nvidia:1'],hardwareId:'rtx'});
assert.equal(totals.total,200);
assert.equal(totals.estimated,true);
assert.equal(totals.since,'2026-09-18');
assert.equal(ui.gpuUsage({}, {keys:['nvidia:0']}).total,0);
assert(home.rows.filter(r=>r.action.startsWith('gpu:')).every(r=>r.type==='row' && !r.history));
console.log('Historical GPU totals, archive attribution and allocation deduplication passed');
const historySnap = {...snap,gpuUsage:[{keys:['nvidia:0'],days:{'2026-09-20':100},since:'2026-09-20'}]};
const ranked = ui.usageRows(historySnap);
assert.equal(ranked[1].label,'1× RTX 3090');
assert.equal(ranked[1].share,1);
assert.equal(ranked[2].share,0);
assert(ranked.every(r=>!r.action));
assert.equal(ui.usageRows(snap).length,0);
const controls = ui.cardRows({snap:historySnap},false);
assert.equal(controls[1].action,'gpu:b70'); // control order never follows token rank
assert.equal(controls[1].detail,'Running · Qwen');
assert.equal(controls[2].detail,'Available · no model loaded');
const separated = ui.build({snap:historySnap,view:'home',localError:''}).rows;
assert(separated.findIndex(r=>r.label==='deployments') < separated.findIndex(r=>r.label==='tokens by gpu'));
assert(separated.filter(r=>r.type==='usage').every(r=>!r.action));
console.log('Deployment controls stay distinct from read-only usage and useful without history');

// Every breadcrumb has a destination, including current GPU counts and running work.
assert.equal(JSON.stringify(catalog.path.map(p=>p.action)), JSON.stringify(['home','card:b70','count:2']));
const modelPath = ui.build({snap,view:'model',slotSel:recipe.id,localError:''}).path;
assert.equal(JSON.stringify(modelPath.map(p=>p.action)), JSON.stringify(['home','card:b70','model:qwen-tp2']));
for (const state of ['download','starting','unload','share']) {
  const busy = {...snap,state,operation:{recipeId:recipe.id}};
  const work = ui.build({snap:busy,view:'home',localError:''});
  assert(work.path.every(p=>p.action));
  assert.equal(work.path.at(-1).action,'work');
  const browse = ui.build({snap:busy,view:'model',slotSel:recipe.id,localError:'',browseWhileWorking:true});
  assert.equal(browse.rows[0].action,'work');
  assert(browse.foot.find(r=>r.action==='stop:'+recipe.id).disabled);
  assert.equal(browse.path.at(-1).action,'model:'+recipe.id);
}
console.log('Direct breadcrumbs and browsing during deployment work passed');

// Model selection keeps its action directly after its details, before the next recipe.
const idle = {...snap,models:[],recipes:[recipe,{...recipe,id:'second-choice'}]};
const free = ui.build({snap:idle,view:'card',hw:'b70',count:2,localError:''});
const runs = free.rows.filter(r => r.action.startsWith('run:'));
assert.equal(runs.length, 2, 'each free model is one row');
assert(runs.every(r => /Download & run/.test(r.value)), 'the row itself is the action');
assert(/^Download & run/.test(runs[0].value), 'the action names what it will do');
assert.equal(free.foot.length, 0, 'no action waits at the bottom');
assert(!free.rows.some(r => r.action.startsWith('pick:')), 'no model row needs a selection first');
const occupied = ui.build({snap:{...snap,recipes:idle.recipes},view:'card',hw:'b70',count:2,localError:''});
const swapAt = occupied.rows.findIndex(r => r.action === 'run:second-choice:2');
assert(swapAt >= 0, 'a model that needs occupied GPUs is still one row');
assert(/replaces .*Qwen/.test(occupied.rows[swapAt].detail), 'that row names what it replaces before the click');
assert.equal(occupied.rows.filter(r => r.action.startsWith('run:')).length, 1, 'the running recipe is not offered twice');
assert.equal(catalog.rows.filter(r=>r.action==='model:qwen-tp2').length,1);
console.log('One row per model, that row is the action, and the GPU page repeats no card row');

// Allocation preview follows the controller: chosen GPU first, then device order.
const group={hardwareId:'test',keys:['nvidia:0','nvidia:1','nvidia:2']};
const allocation={cards:[group],gpus:group.keys.map(key=>({key,hardwareId:'test',vramGb:24,usedGb:0})),models:[
 {recipeId:'old',name:'Old',keys:['nvidia:0'],state:'ready'},
 {recipeId:'unrelated',name:'Other',keys:['intel-xpu:0'],state:'ready'}]};
let plan=ui.loadPlan(allocation,{id:'new',cards:1},group);
assert.equal(plan.gpu,'nvidia:1'); assert.equal(plan.replaces.length,0);
plan=ui.loadPlan(allocation,{id:'new',cards:2},group);
assert.equal(JSON.stringify(plan.keys),JSON.stringify(['nvidia:1','nvidia:0']));
assert.equal(JSON.stringify(plan.replaces.map(m=>m.recipeId)),JSON.stringify(['old']));
const full={...allocation,models:[{...allocation.models[0],keys:group.keys},allocation.models[1]]};
assert.equal(ui.loadPlan(full,{id:'new',cards:1},group).replaces[0].recipeId,'old');
const busySwap=ui.build({snap:{...snap,state:'starting',operation:{recipeId:'second-choice'},recipes:idle.recipes},view:'card',hw:'b70',count:2,localError:'',browseWhileWorking:true});
assert(busySwap.rows.find(r=>r.action==='run:second-choice:2').disabled);
console.log('Swap targets match controller allocation; unrelated models and busy guards retained');

// A running one-GPU recipe remains loadable on the other physical GPU.
const single={...recipe,id:'qwen-one',cards:1,onDisk:true};
const oneBusy={...snap,recipes:[single],models:[{...running,recipeId:single.id,keys:['intel-xpu:0'],cards:1}]};
const another=ui.build({snap:oneBusy,view:'card',hw:'b70',count:1,localError:''});
assert(another.rows.some(r=>/^Load another/.test(r.value) && r.action==='run:qwen-one:1'), 'a second instance is one row that says so');
assert.equal(ui.loadPlan(oneBusy,single,oneBusy.cards[0]).gpu,'intel-xpu:1');
assert.equal(ui.loadPlan(oneBusy,single,oneBusy.cards[0]).replaces.length,0);
const twoBusy={...oneBusy,models:[...oneBusy.models,{...oneBusy.models[0],recipeId:'qwen-one-instance-2',baseRecipeId:single.id,keys:['intel-xpu:1']}]};
assert(!ui.build({snap:twoBusy,view:'card',hw:'b70',count:1,localError:''}).rows.some(r=>r.action==='run:qwen-one:1'), 'a third instance is not offered while both GPUs are taken');
console.log('Duplicate recipe stays launchable on a free GPU and never replaces the first instance');
