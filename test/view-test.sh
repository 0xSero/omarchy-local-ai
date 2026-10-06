#!/bin/bash
# The panel's view model, state by state (design/SPEC.md, issues #64-#88): the bands, home (launch, tiers, calendar),
# gpus rows that open in place, the model lists, the pages under a running model, not-ready states; errors leave the
# panel as notifications.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "${MODEL:-$ROOT/Model.js}" "${PANEL:-$ROOT/Panel.qml}" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = {module:{exports:{}}};
vm.runInNewContext(fs.readFileSync(process.argv[2],'utf8'),c);
const m = c.module.exports;
const g3090 = {key:'nvidia:0',hw:'rtx-3090',name:'NVIDIA GeForce RTX 3090',backend:'nvidia',vramGb:24,usedMiB:600,tempC:38};
const b70 = (i, t) => ({key:'intel-xpu:'+i,hw:'b70',name:'Arc Pro B70',backend:'intel-xpu',vramGb:32,usedMiB:null,tempC:t});
const cpu = {key:'cpu:0',hw:'cpu',name:'x86-64 AVX2 CPU',backend:'cpu',vramGb:0,ramGb:64};
const qwen = {id:'q27',name:'Qwen3.8-27B',family:'qwen',cards:1,onDisk:true,sizeGb:14};
const moe = {id:'q35',name:'Qwen3.6-35B-A3B',family:'qwen',cards:1,sizeGb:15};
const big = {id:'flash',name:'Qwen3.8-Flash-Next',family:'qwen',cards:1,needs:{host_ram_gb:75},unfit:'needs 75 GB RAM, you have 41'};
const pair = {id:'pair',name:'Qwen3.8-27B',family:'qwen',cards:2};
const s = {version:'7.1.0',readiness:{state:'ready'},host:{freeRamGb:41,ramGb:64},total:2810000,
  life:{start:1759100000,today:3,days:[1000,0,5000,23000,0]},tailnet:'box.ts.net',agents:['pi','claude'],defaults:{agent:'pi',folder:'/home/u/Work'},folders:['/home/u/notes'],
  gpus:[g3090,b70(0,40),b70(1,52),cpu],
  kinds:[{hw:'rtx-3090',keys:['nvidia:0'],free:['nvidia:0'],taken:[],models:[qwen,moe,big],groups:[]},
    {hw:'b70',keys:['intel-xpu:0','intel-xpu:1'],free:['intel-xpu:1'],taken:[],models:[qwen],groups:[pair]},
    {hw:'cpu',keys:['cpu:0'],free:['cpu:0'],taken:[],models:[{id:'lfm',name:'LFM2.5-2.6B',family:'lfm',cards:1}],groups:[]}],
  deployments:[{...qwen,id:'q27',keys:['intel-xpu:0'],state:'ready',agent:'pi',folder:'/home/u/Work',shared:'',port:12434,startedAt:'2026-10-06T08:00:00Z',
    session:{tokens:4800,all:{decode:88.4,prefill:1900,ttft:400,tokens:1900000,line:[0,10,40,90]}}}]};
let failed = 0;
function test(name, f) { try { f(); console.log('ok - '+name) } catch(e) { failed++; console.error('not ok - '+name+': '+e.message) } }
const items = (st, ui={}) => m.build(st, ui).items;
const row = (st, id, ui={}) => items(st, ui).find(i => i.id === id);

test('bands: the header has the total, today and the cumulative line; the footer the machine', () => {
  const v = m.build(s, {});
  assert.equal(v.header.tokens, '2.8M'); assert.equal(v.header.today, 'today 23k'); assert.deepEqual(Array.from(v.header.line), [1000,1000,6000,29000]);
  assert.equal(v.footer, '3 GPUs  ·  1 model running'); assert.equal(v.tab, 'gpus');
  assert(m.build({...s,total:0}, {}).header.empty);
});
test('home: launch each running model in its agent and folder, then tiers and the calendar', () => {
  const h = items(s, {tab:'home'});
  assert.deepEqual(h.map(i => i.type), ['note','launch','tiers','calendar']);
  assert.deepEqual([h[1].agent, h[1].folder, h[1].open, h[1].agentAction, h[1].folderAction], ['pi','~/Work','open|q27','go|agent|q27','go|folder|q27']);
  assert.deepEqual(Array.from(h[2].cells, c => c[0]), ['23k','29k','29k','29k','29k','2.8M']);
  const cal = h[3]; assert.equal(cal.cells.length, 25 * 7); assert.equal(cal.cells[cal.today], 4); assert(cal.labels[cal.today].endsWith('23k tokens'));
  assert.equal(items({...s,total:0}, {tab:'home'}).pop().head, 'No tokens yet');
});
test('gpus: a running row says its speed and card; opened, its figures, settings and buttons', () => {
  const r = row(s, 'd:q27'); assert.equal(r.right, '88 tok/s'); assert(r.live); assert.equal(r.facts, 'Arc Pro B70  ·  32 GB  ·  40°');
  const o = row(s, 'd:q27', {open:'d:q27'}); assert(o.open);
  assert.deepEqual(Array.from(o.detail.cells, c => c[0]), ['88','1.9k','0.4 s','4.8k','1.9M', o.detail.cells[5][0]]);
  assert.deepEqual(Array.from(o.detail.kv, k => k.k + '=' + k.v), ['model=','agent=pi ›','folder=~/Work ›','share=off · turn on']);
  assert.equal(o.detail.button.action, 'open|q27'); assert.deepEqual(Array.from(o.detail.links, l => l.action), ['stop|q27','log']);
});
test('a free row: card facts and memory; opened, every model, the picked one on, Run runs it', () => {
  const r = row(s, 'g:nvidia:0'); assert.equal(r.name, 'GeForce RTX 3090'.replace('GeForce ','')); assert.equal(r.facts, '1 / 24 GB  ·  38°'); assert(r.frac > 0 && r.frac < .1);
  const d = r.detail; assert.equal(d.models.length, 3); assert(d.models[0].on); assert.equal(d.models[0].note, 'on disk'); assert.equal(d.models[0].remove, 'forget|q27');
  assert(d.models[2].off); assert.equal(d.models[2].note, 'needs 75 GB RAM'); assert.equal(d.models[2].action, '');
  assert.equal(d.button.action, 'run|q27|nvidia:0');
  const p = row(s, 'g:nvidia:0', {picks:{'nvidia:0':'q35'}}).detail; assert(p.models[1].on); assert.equal(p.button.action, 'run|q35|nvidia:0'); assert.equal(p.models[1].note, '15 GB download');
});
test('in-use rows open too: what holds the card, the models it could run, read only', () => {
  const held = {...s, kinds: s.kinds.map(k => k.hw === 'rtx-3090' ? {...k, free:[], taken:['nvidia:0']} : k), gpus: [{...g3090, usedMiB: 15872}, ...s.gpus.slice(1)]};
  const r = row(held, 'g:nvidia:0'); assert(r.dim); assert.equal(r.right, 'in use');
  assert(r.detail.lines[0].startsWith('Held by another program, 16 GB')); assert(r.detail.models.every(x => x.off && !x.action && !x.remove));
  const b = row(s, 'b:b70*2'); assert(b.dim); assert(b.detail.lines[0].startsWith('Needs 2 free cards')); assert(b.detail.models.every(x => x.off));
});
test('rows run: models, free cards and builds, a rule, then what cannot be used', () => {
  const ids = items(s).map(i => i.id || i.type);
  assert.deepEqual(ids, ['d:q27','g:nvidia:0','g:intel-xpu:1','g:cpu:0','rule','b:b70*2']);
  assert.equal(row(s, 'g:cpu:0').facts, '41 of 64 GB RAM free');
});
test('starting: its step and progress, stop; stopped: quiet, opened says why with Run again', () => {
  const st = {...s, deployments:[{...s.deployments[0], state:'download', detail:'downloading', percent:42}]};
  const r = row(st, 'd:q27'); assert.equal(r.right, 'downloading 42%'); assert.equal(r.progress, 42); assert.deepEqual(Array.from(r.detail.links, l => l.action), ['stop|q27']);
  const er = row({...s, deployments:[{...s.deployments[0], state:'error', error:'the engine stopped'}]}, 'd:q27');
  assert(er.quiet); assert.equal(er.right, 'stopped'); assert.equal(er.detail.lines[0], 'the engine stopped');
  assert.equal(er.detail.button.action, 'again|q27|intel-xpu:0');
});
test('model page: every model for the running cards, switch stops and runs the pick', () => {
  const big3090 = {...s, deployments:[{...s.deployments[0], keys:['nvidia:0']}], kinds: s.kinds.map(k => k.hw === 'rtx-3090' ? {...k, free:[]} : k)};
  assert.equal(row(big3090, 'd:q27', {open:'d:q27'}).detail.kv[0].action, 'go|model|q27');
  const it = items(big3090, {view:'model', id:'q27'});
  assert.equal(it[0].type, 'back'); assert.equal(it[1].models[0].note, 'running'); assert(!it.some(i => i.type === 'button'));
  const sw = items(big3090, {view:'model', id:'q27', picks:{'nvidia:0':'q35'}});
  assert.equal(sw[2].action, 'switch|q27|q35|nvidia:0');
});
test('agent, folder and share pages set and come back', () => {
  const ag = items(s, {view:'agent', id:'q27'}).filter(i => i.type === 'opt');
  assert.deepEqual(ag.map(a => a.name), ['pi','Claude Code']); assert(ag[0].on); assert.equal(ag[1].action, 'set|agent|claude|q27');
  const fo = items(s, {view:'folder', id:'q27'}).filter(i => i.type === 'opt');
  assert.deepEqual(fo.map(f => f.name), ['~/Work','~/notes','choose another…']);
  const shared = {...s, deployments:[{...s.deployments[0], shared:'https://box.ts.net:12434'}]};
  assert.equal(row(shared, 'd:q27').detail.kv[3].action, 'go|share|q27');
  const sh = items(shared, {view:'share', id:'q27'}); assert.equal(sh[1].value, 'box.ts.net:12434'); assert.equal(sh[3].action, 'share|q27|off');
  assert.equal(m.build(s, {view:'agent', id:'gone'}).page, 'main');
});
test('not ready: one message, the one fix; running models stay reachable; nothing tested: where the list is', () => {
  for (const [state, label, action] of [['needs-setup','Set up','setup'],['docker-down','Start Docker','docker'],['unsupported','Update Omarchy','omarchy-update']]) {
    const it = items({...s, readiness:{state}});
    assert.equal(it[0].type, 'msg'); assert.equal(it[0].button.label, label); assert.equal(it[0].button.action, action);
    assert(it.some(i => i.id === 'd:q27'));
  }
  assert(items({...s, kinds:[], deployments:[]})[0].head.startsWith('No tested model for'));
  assert.equal(m.build({...s, readiness:{state:'docker-down'}}, {}).footer, '3 GPUs  ·  Docker stopped');
});
test('what newly went wrong becomes a notification, once; the panel draws no errors', () => {
  const er = {...s, deployments:[{...s.deployments[0], state:'error', error:'the engine stopped'}]};
  assert.deepEqual(m.problems(s, er), [{title:'Qwen3.8-27B stopped', body:'the engine stopped'}]); assert.deepEqual(m.problems(er, er), []);
  const qml = fs.readFileSync(process.argv[3], 'utf8');
  assert(!/alertTone|type: "error"/.test(qml));
  for (const fn of ['polled','finished']) assert(new RegExp('function ' + fn + '[^]*?notify\\(').test(qml), fn + ' notifies');
});
test('the poll keeps the last snapshot when one cannot be read, and says so once', () => {
  const qml = fs.readFileSync(process.argv[3], 'utf8'), sent = [];
  const fn = qml.match(/function polled\(code, text\) \{[^]*?\n  \}/)[0];
  const ctx = {Model:m, snap:s, reachable:true, notify:(t) => sent.push(t)}; vm.createContext(ctx); vm.runInContext(fn, ctx);
  ctx.polled(1,''); ctx.polled(0,'broken'); assert.equal(ctx.snap, s); assert.equal(sent.length, 1);
  ctx.polled(0, JSON.stringify(s)); assert(ctx.reachable);
});
test('every mark a row can ask for is shipped', () => {
  const root = require('path').dirname(process.argv[2]);
  for (const f of ['qwen','gemma','deepseek','glm','lfm','hf']) assert(fs.existsSync(root + '/logos/' + f + '.svg'), f);
  for (const v of ['nvidia','intel','amd']) assert(fs.existsSync(root + '/logos/' + v + '-hw.svg'), v);
});
process.exitCode = failed ? 1 : 0;
JS
