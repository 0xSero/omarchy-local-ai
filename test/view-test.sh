#!/bin/bash
# Errors belong to every page, and sharing can be undone where it was enabled.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "${MODEL:-$ROOT/Model.js}" "${PANEL:-$ROOT/Panel.qml}" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = {module:{exports:{}}};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const m = c.module.exports;
const gpu = {key:'nvidia:0',hw:'test',name:'Test GPU',vramGb:24};
const recipe = {id:'test',name:'Test model',cards:1,weights:[]};
const s = {gpus:[gpu],kinds:[{hw:'test',keys:[gpu.key],free:[gpu.key],taken:[],models:[recipe],groups:[]}],
  deployments:[{...recipe,keys:[gpu.key],state:'ready',agent:'pi',shared:'https://test:12434',session:{}}],tailnet:'test'};
let failed = 0;
function test(name, f) { try { f(); console.log('ok - '+name) } catch(e) { failed++; console.error('not ok - '+name+': '+e.message) } }
for (const view of ['home','run','kind','gpus']) test('action errors are visible once on '+view, () => {
  const v=m.build(s,{view,id:'test',problem:'could not change the share'});
  assert.equal(v.rows.filter(r=>r.type==='error'&&r.label==='could not change the share').length,1);
});
for (const state of [{gpus:[],kinds:[]},{...s,readiness:{state:'needs-setup'}},{...s,readiness:{state:'docker-down',message:'Docker is not running'}},{...s,readiness:{state:'unsupported'}}]) test('setup, docker-down and unsupported pages retain errors', () => {
  assert(m.build(state,{view:'home',problem:'refresh failed'}).rows.some(r=>r.label==='refresh failed'));
});
test('a card kind with only multi-card models renders instead of breaking the panel', () => {
  const v=m.build({...s,deployments:[],kinds:[{...s.kinds[0],models:[]}]},{view:'home'});
  assert(!v.rows.some(r=>r.type==='error'));
});
test('a model running while setup is needed stays on the setup page', () => {
  const v=m.build({...s,readiness:{state:'needs-setup'}},{view:'home'});
  assert(v.rows.some(r=>r.type==='run'&&r.name==='Test model'));
});
test('setup terminal failures remain visible after the terminal closes', () => {
  const v=m.build({...s,setupError:'Setup did not finish',readiness:{state:'needs-setup'}},{view:'home'});
  assert(v.rows.some(r=>r.type==='error'&&r.label==='Setup did not finish')); assert.equal(v.mark,'failed');
  assert(v.rows.some(r=>(r.items||[]).some(a=>a.action==='setup')));
});
test('a failed model shows its reason without expanding its GPU row', () => {
  const failedState={...s,deployments:[{...s.deployments[0],state:'error',error:'the engine stopped'}]};
  const rows=m.build(failedState,{view:'home'}).rows;
  assert.equal(rows.filter(r=>r.type==='error'&&r.label==='the engine stopped').length,1);
});
test('a shared model offers stop sharing', () => assert(m.build(s,{view:'run',id:'test'}).rows
  .some(r=>(r.items||[]).some(a=>a.action==='share|test|off'))));
test('unsupported GPUs show refresh progress and disable a duplicate refresh', () => {
  const rows=m.build({gpus:[],kinds:[]},{view:'home',registryBusy:true}).rows;
  assert(rows.some(r=>(r.items||[]).some(a=>a.label==='Refreshing models…'&&a.action==='')));
});
test('failed and malformed polls retain the last snapshot, show a problem, and recover', () => {
  const qml=fs.readFileSync(process.argv[3],'utf8');
  const fn=qml.match(/function polled\(code, text\) \{([\s\S]*?)\n  \}/);
  assert(fn, 'poll handler missing');
  const ctx={Model:m,snap:s,ui:{problem:'an action failed'}};
  vm.createContext(ctx); vm.runInContext('function polled(code,text) {'+fn[1]+'}',ctx);
  for (const [code,text] of [[124,''],[1,JSON.stringify(s)],[0,'broken'],[0,'{}']]) {
    ctx.polled(code,text); assert.equal(ctx.snap,s); assert(ctx.ui.pollProblem); assert.equal(ctx.ui.problem,'an action failed');
  }
  ctx.polled(0,JSON.stringify(s)); assert.equal(ctx.ui.pollProblem,''); assert.equal(ctx.snap.gpus[0].name,gpu.name);
});
test('a held Intel card with unknown VRAM has no run action', () => {
  const held={...s,gpus:[{...gpu,usedMiB:null}],deployments:[],kinds:[{...s.kinds[0],free:[],taken:[gpu.key]}]};
  assert(m.build(held,{view:'gpus'}).rows.some(r=>r.note==='in use by another program'));
  const rows=m.build(held,{view:'kind',id:'test',key:gpu.key}).rows;
  assert(rows.some(r=>r.status==='in use by another program'));
  assert(!rows.some(r=>(r.items||[]).some(a=>a.action.startsWith('run|'))));
});
test('stopped model details offer recovery without live reach or uptime', () => {
  const rows=m.build({...s,deployments:[{...s.deployments[0],state:'error',error:'the engine stopped'}]}, {view:'run',id:'test'}).rows;
  assert(!rows.some(r=>r.label==='REACH'||r.icon==='machine'||r.icon==='tailnet'));
  assert(!rows.some(r=>(r.cells||[]).some(c=>c.k==='up')));
  const actions=rows.filter(r=>r.type==='acts').flatMap(r=>r.items||[]);
  assert.deepEqual(Array.from(actions,a=>a.label),['Run again ›','View logs','Dismiss']);
  assert(actions[0].primary); assert.equal(actions[0].action,'again|test|nvidia:0');
  assert.equal(actions[2].action,'stop|test');
});
test('refresh completion survives polls until the next action', () => {
  const qml=fs.readFileSync(process.argv[3],'utf8');
  const ctx={Model:m,snap:s,ui:{registryBusy:true},queue:[],opened:true,next(){},root:null}; ctx.root=ctx;
  vm.createContext(ctx);
  for (const name of ['finished','polled','activate']) {
    const fn=qml.match(new RegExp('function '+name+'\\([^]*?\\n  \\}'));
    assert(fn, name+' missing'); vm.runInContext(fn[0],ctx);
  }
  ctx.finished(0,'registry','models up to date · 12345678','');
  assert.equal(ctx.ui.registryBusy,false); assert.equal(ctx.ui.notice,'models up to date · 12345678');
  ctx.polled(0,JSON.stringify(s));
  assert(m.build(s,ctx.ui).rows.some(r=>r.note===ctx.ui.notice));
  ctx.activate(''); assert.equal(ctx.ui.notice,'');
  ctx.finished(1,'registry','','local-ai: refresh failed');
  assert.equal(ctx.ui.problem,'refresh failed'); assert(!ctx.ui.notice);
});
test('ready model details open the selected agent without returning home', () => {
  assert(m.build(s,{view:'run',id:'test'}).rows.some(r=>(r.items||[]).some(a=>a.action==='open|test'&&a.primary)));
  for(const state of ['loading','error']) assert(!m.build({...s,deployments:[{...s.deployments[0],state}]},{view:'run',id:'test'}).rows.some(r=>(r.items||[]).some(a=>a.action==='open|test')));
});
test('agent choice is a named row with explicit default and update controls', () => {
  const rows=m.build({...s,agents:['pi','claude'],defaults:{agent:'claude'}},{view:'run',id:'test',open:'agent'}).rows;
  assert(rows.some(r=>r.type==='agent'&&r.agent==='pi'&&r.label==='pi'));
  assert(rows.some(r=>r.type==='agent'&&r.agent==='claude'&&r.label==='Claude Code'));
  assert(rows.some(r=>(r.items||[]).some(a=>a.action==='default|pi')));
  assert(rows.some(r=>(r.items||[]).some(a=>a.action==='update|pi')));
});
test('folder row opens a picker with the model id and encoded current path', () => {
  const folder='/home/test/Work #1|two';
  const rows=m.build({...s,deployments:[{...s.deployments[0],folder}]},{view:'run',id:'test'}).rows;
  assert(rows.some(r=>r.action==='folder|test|'+encodeURIComponent(folder)));
});
process.exitCode = failed ? 1 : 0;
JS
