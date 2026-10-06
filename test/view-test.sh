#!/bin/bash
# The panel's view model, path by path (design/SPEC.md): tabs, GPU lines and their drawers, builds, config, ⋯, and
# not-ready states; errors leave the panel as notifications.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "${MODEL:-$ROOT/Model.js}" "${PANEL:-$ROOT/Panel.qml}" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = {module:{exports:{}}};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const m = c.module.exports;
const g3090 = {key:'nvidia:0',hw:'rtx-3090',name:'NVIDIA GeForce RTX 3090',backend:'nvidia',vramGb:24,usedMiB:600,tempC:38};
const b70 = (i, t) => ({key:'intel-xpu:'+i,hw:'b70',name:'Arc Pro B70',backend:'intel-xpu',vramGb:32,usedMiB:null,tempC:t});
const cpu = {key:'cpu:0',hw:'cpu',name:'x86-64 AVX2 CPU',backend:'cpu',vramGb:0,ramGb:64};
const qwen = {id:'q27',name:'Qwen3.8-27B',family:'qwen',cards:1,onDisk:true};
const moe = {id:'q35',name:'Qwen3.6-35B-A3B',family:'qwen',cards:1};
const big = {id:'flash',name:'Qwen3.8-Flash-Next',family:'qwen',cards:1,needs:{host_ram_gb:75},unfit:'needs 75 GB RAM, you have 41'};
const pair = {id:'pair',name:'Qwen3.8-27B',family:'qwen',cards:2};
const s = {version:'7.0.0',readiness:{state:'ready'},host:{freeRamGb:41},total:2810000,
  life:{start:1759100000,today:3,days:[1000,0,5000,23000,0]},tailnet:'box.ts.net',agents:['pi','claude'],defaults:{agent:'pi',folder:'/home/u/Work'},folders:['/home/u/notes'],
  gpus:[g3090,b70(0,40),b70(1,52),cpu],
  kinds:[{hw:'rtx-3090',keys:['nvidia:0'],free:['nvidia:0'],taken:[],models:[qwen,moe,big],groups:[]},
    {hw:'b70',keys:['intel-xpu:0','intel-xpu:1'],free:['intel-xpu:1'],taken:[],models:[qwen],groups:[pair]},
    {hw:'cpu',keys:['cpu:0'],free:['cpu:0'],taken:[],models:[{id:'lfm',name:'LFM2.5-2.6B',family:'lfm',cards:1}],groups:[]}],
  deployments:[{...qwen,id:'q27',keys:['intel-xpu:0'],state:'ready',agent:'pi',folder:'/home/u/Work',shared:'',port:12434,session:{all:{decode:88.4}}}]};
let failed = 0;
function test(name, f) { try { f(); console.log('ok - '+name) } catch(e) { failed++; console.error('not ok - '+name+': '+e.message) } }
const lines = (st, ui={}) => m.build(st, ui).items.filter(i=>i.type==='line');
const acts = l => (l.drawer||[]).filter(Boolean).map(a=>a.action);

test('two tabs, gpus first; home is usage only', () => {
  assert.deepEqual(m.build(s,{}).items[0], {type:'tabs',on:'gpus'});
  const h = m.build(s,{tab:'home'}).items;
  assert.deepEqual(h.map(i=>i.type), ['tabs','top','note','bars']);
  assert.equal(h[1].tokens,'2.8M'); assert.deepEqual(Array.from(h[1].line),[1000,1000,6000,29000]);
  assert.equal(h[3].values.length,4); assert(h[3].labels[3].endsWith('23k'));
  assert.deepEqual(m.build({...s,total:0},{tab:'home'}).items[1].head,'No tokens yet');
});
test('a running model is one line: lab mark, speed, drawer Open · stop · ⋯', () => {
  const l = lines(s)[0];
  assert.equal(l.name,'Qwen3.8-27B'); assert.deepEqual(l.logo,{kind:'lab',name:'qwen'}); assert.equal(l.info,' 88 tok/s');
  assert.deepEqual(acts(l),['open|q27','stop|q27','more|q27']); assert.equal(l.drawer[0].label,'Open pi');
});
test('a free card: maker mark, temperature and free memory padded, hover names what Run starts', () => {
  const l = lines(s).find(l=>l.id==='g:nvidia:0');
  assert.equal(l.name,'3090'); assert.deepEqual(l.logo,{kind:'hw',name:'nvidia'}); assert.equal(l.info,'38°  23 GB free');
  assert.equal(l.next.name,'Qwen3.8-27B'); assert.deepEqual(acts(l),['run|q27|nvidia:0','config|nvidia:0']);
  assert.equal(lines(s).find(l=>l.id==='g:intel-xpu:1').info,'52°  32 GB free');
  assert.equal(lines(s).find(l=>l.id==='g:cpu:0').info,'41 GB RAM free');
});
test('a build of two cards is its own line, dim and without a drawer while a card is busy', () => {
  const b = lines(s).find(l=>l.id==='b:b70*2');
  assert.equal(b.name,'2 × B70'); assert(b.dim); assert.equal(b.info,'in use'); assert(!b.drawer);
  const free = lines({...s,deployments:[],kinds:s.kinds.map(k=>k.hw==='b70'?{...k,free:['intel-xpu:0','intel-xpu:1']}:k)}).find(l=>l.id==='b:b70*2');
  assert(!free.dim); assert.deepEqual(acts(free),['run|pair|intel-xpu:0,intel-xpu:1','config|b70*2']); assert.equal(free.info,'40°  64 GB free');
});
test('lines run: models, then free cards and builds, then what cannot be used', () => {
  const ids = lines(s).map(l=>l.id);
  assert.deepEqual(ids,['d:q27','g:nvidia:0','g:intel-xpu:1','g:cpu:0','b:b70*2']);
  const held = {...s,kinds:s.kinds.map(k=>k.hw==='rtx-3090'?{...k,free:[],taken:['nvidia:0']}:k)};
  const h = lines(held).find(l=>l.id==='g:nvidia:0'); assert(h.dim); assert.equal(h.info,'in use'); assert(!h.drawer);
  const none = lines({...s,gpus:[...s.gpus,{key:'amd:0',hw:'rx',name:'AMD Radeon RX 7600',backend:'amd',vramGb:8}]}).find(l=>l.id==='g:amd:0');
  assert.equal(none.info,'no model yet'); assert.deepEqual(none.logo,{kind:'hw',name:'amd'}); assert.equal(none.name,'RX 7600');
});
test('starting shows its step and progress, with stop; a stopped model is quiet, Run again · dismiss', () => {
  const st = {...s,deployments:[{...s.deployments[0],state:'download',detail:'downloading',percent:42}]};
  const l = lines(st)[0]; assert.equal(l.info,'downloading 42%'); assert.equal(l.progress,42); assert.deepEqual(acts(l),['stop|q27']);
  const er = lines({...s,deployments:[{...s.deployments[0],state:'error',error:'the engine stopped'}]})[0];
  assert(er.quiet); assert.equal(er.info,'stopped'); assert.deepEqual(acts(er),['again|q27|intel-xpu:0','stop|q27']);
  assert(!m.build({...s,deployments:[{...s.deployments[0],state:'error',error:'x'}]},{}).items.some(i=>JSON.stringify(i).includes('the engine stopped')));
});
test('config is one list: chosen dotted, on disk and RAM noted, unfit dim with its reason; Run runs the pick', () => {
  const it = m.build(s,{view:'config',id:'nvidia:0'}).items;
  assert.equal(it[1].type,'back'); assert.equal(it[1].label,'3090');
  const picks = it.filter(i=>i.type==='pick');
  assert.deepEqual(picks.map(p=>p.name),['Qwen3.8-27B','Qwen3.6-35B-A3B','Qwen3.8-Flash-Next']);
  assert(picks[0].on); assert.equal(picks[0].note,'on disk'); assert.deepEqual(acts(picks[0]),['run|q27|nvidia:0','forget|q27']);
  assert(picks[2].off); assert.equal(picks[2].note,'needs 75 GB RAM'); assert.equal(picks[2].action,'');
  assert.equal(it[it.length-1].action,'run|q27|nvidia:0');
  const chose = m.build(s,{view:'config',id:'nvidia:0',picks:{'nvidia:0':'q35'}}).items;
  assert.equal(chose[chose.length-1].action,'run|q35|nvidia:0');
  assert.equal(lines(s,{picks:{'nvidia:0':'q35'}}).find(l=>l.id==='g:nvidia:0').next.name,'Qwen3.6-35B-A3B');
  assert.equal(m.build(s,{view:'config',id:'b70*2'}).items[1].label,'2 × B70');
});
test('⋯: agent, folder, share; each a page that sets and comes back', () => {
  const it = m.build(s,{view:'more',id:'q27'}).items;
  assert.deepEqual(it.filter(i=>i.type==='kv').map(i=>i.k+'='+i.v),['agent=pi ›','folder=~/Work ›','share=off · turn on']);
  assert.equal(it.find(i=>i.k==='share').action,'share|q27');
  const ag = m.build(s,{view:'agent',id:'q27'}).items.filter(i=>i.type==='opt');
  assert.deepEqual(ag.map(a=>a.name),['pi','Claude Code']); assert(ag[0].on); assert.equal(ag[0].note,'default');
  assert.equal(ag[1].action,'set|agent|claude|q27');
  const fo = m.build(s,{view:'folder',id:'q27'}).items.filter(i=>i.type==='opt');
  assert.deepEqual(fo.map(f=>f.name),['~/Work','~/notes','choose another…']); assert(fo[2].action.startsWith('folder|q27|'));
  const shared = {...s,deployments:[{...s.deployments[0],shared:'https://box.ts.net:12434'}]};
  assert.equal(m.build(shared,{view:'more',id:'q27'}).items.find(i=>i.k==='share').action,'go|share|q27');
  const sh = m.build(shared,{view:'share',id:'q27'}).items;
  assert.equal(sh[2].value,'box.ts.net:12434'); assert.equal(sh[4].action,'share|q27|off');
});
test('not ready: one message and the one action that fixes it', () => {
  for (const [state,label,action] of [['needs-setup','Set up','setup'],['docker-down','Start Docker','docker'],['unsupported','Update Omarchy','omarchy-update']]) {
    const it = m.build({...s,readiness:{state}},{}).items;
    assert.equal(it[1].type,'msg'); assert.equal(it[1].button.label,label); assert.equal(it[1].button.action,action);
    assert(it.some(i=>i.id==='d:q27'), 'a running model stays reachable');
  }
  const none = m.build({...s,kinds:[],deployments:[]},{}).items[1]; assert(none.head.startsWith('No tested model for'));
});
test('a page whose subject is gone falls back to the lines', () => {
  assert.equal(m.build(s,{view:'more',id:'gone'}).page,'main');
});
test('what newly went wrong becomes a notification, once', () => {
  const er = {...s,deployments:[{...s.deployments[0],state:'error',error:'the engine stopped'}]};
  assert.deepEqual(m.problems(s,er),[{title:'Qwen3.8-27B stopped',body:'the engine stopped'}]);
  assert.deepEqual(m.problems(er,er),[]);
  const qml = fs.readFileSync(process.argv[3],'utf8');
  assert(!/type: "error"/.test(qml) && !/alertTone/.test(qml), 'the panel draws no errors');
  for (const fn of ['polled','finished']) assert(new RegExp('function '+fn+'[^]*?notify\\(').test(qml), fn+' notifies');
});
test('the poll keeps the last snapshot when one cannot be read, and says so once', () => {
  const qml = fs.readFileSync(process.argv[3],'utf8'), sent = [];
  const fn = qml.match(/function polled\(code, text\) \{[^]*?\n  \}/)[0];
  const ctx = {Model:m,snap:s,reachable:true,notify:(t)=>sent.push(t)}; vm.createContext(ctx); vm.runInContext(fn,ctx);
  ctx.polled(1,''); ctx.polled(0,'broken'); assert.equal(ctx.snap,s); assert.equal(sent.length,1);
  ctx.polled(0,JSON.stringify(s)); assert(ctx.reachable); assert.equal(ctx.snap.gpus.length,4);
});
test('every mark a line can ask for is shipped', () => {
  const root = require('path').dirname(process.argv[2]);
  for (const f of ['qwen','gemma','deepseek','glm','lfm','hf']) assert(fs.existsSync(root+'/logos/'+f+'.svg'), f);
  for (const v of ['nvidia','intel','amd']) assert(fs.existsSync(root+'/logos/'+v+'-hw.svg'), v);
});
process.exitCode = failed ? 1 : 0;
JS
