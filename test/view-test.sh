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
for (const state of [{gpus:[],kinds:[]},{...s,relogin:true},{...s,setupNeeded:true}]) test('setup, relogin and unsupported pages retain errors', () => {
  assert(m.build(state,{view:'home',problem:'refresh failed'}).rows.some(r=>r.label==='refresh failed'));
});
test('setup terminal failures remain visible after the terminal closes', () => {
  const v=m.build({...s,setupError:'Setup did not finish'},{view:'home'});
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
process.exitCode = failed ? 1 : 0;
JS
