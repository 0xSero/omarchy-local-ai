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
test('a shared model offers stop sharing', () => assert(m.build(s,{view:'run',id:'test',details:true}).rows
  .some(r=>(r.items||[]).some(a=>a.action==='share|test|off'))));
test('no Refresh button anywhere: new models arrive by themselves', () => {
  for (const [st, view] of [[{gpus:[],kinds:[]},'home'],[s,'home'],[s,'models']])
    assert(!m.build(st,{view}).rows.some(r=>(r.items||[]).some(a=>a.action==='registry')));
});
test('failed and malformed polls retain the last snapshot, show a problem, and recover', () => {
  const qml=fs.readFileSync(process.argv[3],'utf8');
  const fn=qml.match(/function polled\(code, text\) \{([\s\S]*?)\n  \}/);
  assert(fn, 'poll handler missing');
  const ctx={Model:m,snap:s,ui:{problem:'an action failed'},autoRefresh(){},autoOutdated(){}};
  vm.createContext(ctx); vm.runInContext('function polled(code,text) {'+fn[1]+'}',ctx);
  for (const [code,text] of [[124,''],[1,JSON.stringify(s)],[0,'broken'],[0,'{}']]) {
    ctx.polled(code,text); assert.equal(ctx.snap,s); assert(ctx.ui.pollProblem); assert.equal(ctx.ui.problem,'an action failed');
  }
  ctx.polled(0,JSON.stringify(s)); assert.equal(ctx.ui.pollProblem,''); assert.equal(ctx.snap.gpus[0].name,gpu.name);
});
test('a held Intel card with unknown VRAM has no run action', () => {
  const held={...s,gpus:[{...gpu,usedMiB:null}],deployments:[],kinds:[{...s.kinds[0],free:[],taken:[gpu.key]}]};
  assert(m.build(held,{view:'gpus'}).rows.some(r=>r.warn&&/in use$/.test(r.value)));
  const rows=m.build(held,{view:'kind',id:'test',key:gpu.key,details:true}).rows;
  assert(rows.some(r=>r.status==='in use by another program'));
  assert.equal(rows.find(r=>r.type==='links').note,'its Test GPU is in use by another program');
  assert(!rows.some(r=>(r.items||[]).some(a=>a.action.startsWith('run|'))));
});
test('stopped model details offer recovery without live reach or uptime', () => {
  const rows=m.build({...s,deployments:[{...s.deployments[0],state:'error',error:'the engine stopped'}]}, {view:'run',id:'test',details:true}).rows;
  assert(!rows.some(r=>r.label==='REACH'||r.icon==='machine'||r.icon==='tailnet'));
  assert(!rows.some(r=>(r.cells||[]).some(c=>c.k==='up')));
  const actions=rows.filter(r=>r.type==='acts').flatMap(r=>r.items||[]);
  assert.deepEqual(Array.from(actions,a=>a.label),['Run again ›','Dismiss']);
  assert(actions[0].primary); assert.equal(actions[0].action,'again|test|nvidia:0');
  assert.equal(actions[1].action,'stop|test');
  assert(rows.some(r=>(r.items||[]).some(a=>a.action==='log')));
});
test('ready model details open the selected agent without returning home', () => {
  assert(m.build(s,{view:'run',id:'test'}).rows.some(r=>(r.items||[]).some(a=>a.action==='open|test'&&a.primary)));
  for(const state of ['loading','error']) assert(!m.build({...s,deployments:[{...s.deployments[0],state}]},{view:'run',id:'test'}).rows.some(r=>(r.items||[]).some(a=>a.action==='open|test')));
});
test('agents: each once, the chosen one checked; choosing on the agents page sets the default; Update only when there is one', () => {
  const st={...s,agents:['pi','claude'],defaults:{agent:'claude'}};
  const rows=m.build(st,{view:'run',id:'test',open:'agent',details:true}).rows.filter(r=>r.type==='agent');
  assert.deepEqual(rows.map(r=>[r.agent,!!r.on,r.action]),[['pi',true,'pick|agent'],['claude',false,'set|agent|claude|test']]);
  assert(!m.build(st,{view:'run',id:'test',details:true}).rows.some(r=>(r.items||[]).some(a=>/^(update|default)\|/.test(a.action))));
  const up=m.build({...st,updates:{pi:{current:'0.3',latest:'0.4'}}},{view:'run',id:'test',details:true}).rows;
  assert(up.some(r=>(r.items||[]).some(a=>a.label==='Update to 0.4'&&a.action==='update|pi')));
  const ag=m.build({...st,updates:{claude:{current:'2.1.270',latest:'2.1.292'}}},{view:'agents'}).rows;
  assert.deepEqual(ag.filter(r=>r.type==='agent').map(r=>[r.agent,!!r.on,r.action]),[['pi',false,'default|pi'],['claude',true,'']]);
  assert(ag.some(r=>r.type==='field'&&r.label==='Claude Code'&&r.value==='2.1.270 → 2.1.292'));
});
test('folder row opens a picker with the model id and encoded current path', () => {
  const folder='/home/test/Work #1|two';
  const rows=m.build({...s,deployments:[{...s.deployments[0],folder}]},{view:'run',id:'test',details:true}).rows;
  assert(rows.some(r=>r.action==='folder|test|'+encodeURIComponent(folder)));
});
test('CPU hardware shows system RAM without a GPU memory bar', () => {
  const cpu={key:'cpu:0',hw:'cpu',backend:'cpu',name:'CPU (AVX2)',ramGb:8,vramGb:0};
  const state={...s,gpus:[cpu],deployments:[],host:{ramGb:8.5,freeRamGb:6.2},kinds:[{...s.kinds[0],hw:'cpu',keys:[cpu.key],free:[cpu.key]}]};
  assert(m.build(state,{view:'home'}).rows.some(r=>r.label==='RAM'&&r.value==='6 / 8 GB free'));
  const rows=m.build(state,{view:'kind',id:'cpu',key:cpu.key,details:true}).rows;
  assert(rows.some(r=>r.label==='CPU'));
  assert(rows.some(r=>r.cpu&&r.mem==='8 GB RAM'&&!r.bar));
});
test('the catalog refreshes by itself; it says so only when it brought new models, and a failure says nothing', () => {
  const qml=fs.readFileSync(process.argv[3],'utf8');
  const ctx={Model:m,snap:{...s,catalog:{commit:'1234567890',at:''}},ui:{},queue:[],opened:true,autoBusy:true,autoRefresh(){},next(){},root:null}; ctx.root=ctx;
  vm.createContext(ctx);
  const fn=qml.match(/function finished\([^]*?\n  \}/); vm.runInContext(fn[0],ctx);
  ctx.finished(0,'registry','models up to date · 12345678',''); assert(!ctx.ui.notice); assert.equal(ctx.autoBusy,false);
  ctx.autoBusy=true; ctx.finished(0,'registry','models up to date · abcdef12',''); assert.equal(ctx.ui.notice,'new models from the registry');
  ctx.ui={}; ctx.autoBusy=true; ctx.finished(1,'registry','','local-ai: could not check the registry'); assert(!ctx.ui.problem && !ctx.ui.notice);
});
test('a model page: name, one line of state, one action (Open and Stop when it runs), the rest under details', () => {
  const run=m.build(s,{view:'run',id:'test'}).rows;
  assert.deepEqual(run.map(r=>r.type),['links','acts','field']);
  assert.deepEqual(run[1].items.map(a=>a.label),['Open pi ›','Stop']);
  assert.equal(run[2].label,'details');
  const free=m.build({...s,deployments:[]},{view:'kind',id:'test',key:gpu.key}).rows;
  assert.deepEqual(free[1].items.map(a=>[a.label,a.action]),[['Start ›','run|test|nvidia:0']]);
  assert.equal(free[0].note,'starts with a 0 GB download');
});
test('back and forward step through the views, as in a browser', () => {
  const qml=fs.readFileSync(process.argv[3],'utf8');
  const ctx={ui:{view:'home',id:'',key:'',open:''},past:[],ahead:[],topTick:0,revealed:false}; vm.createContext(ctx);
  for (const name of ['here','back','forward','go','nav']) { const fn=qml.match(new RegExp('function '+name+'\\([^)]*\\) \\{[^]*?\\n  \\}|function '+name+'\\([^)]*\\) \\{.*\\}')); assert(fn,name+' missing'); vm.runInContext(fn[0],ctx); }
  ctx.nav({view:'models',id:''}); ctx.nav({view:'kind',id:'hw',model:'x'});
  assert.deepEqual(ctx.past.map(p=>p.view),['home','models']);
  ctx.back(); assert.equal(ctx.ui.view,'models'); ctx.back(); assert.equal(ctx.ui.view,'home');
  ctx.forward(); assert.equal(ctx.ui.view,'models'); ctx.forward(); assert.deepEqual([ctx.ui.view,ctx.ui.model],['kind','x']);
  ctx.back(); ctx.nav({view:'gpus',id:''}); assert.equal(ctx.ahead.length,0);
});
process.exitCode = failed ? 1 : 0;
JS
