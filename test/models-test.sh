#!/bin/bash
# Two tabs. Home: activity, what runs (with Stop), pinned models (else the recommended ones). Models: every model this
# machine can run, whatever card it lands on, to search, start, download, remove and pin in place; those too big.
# A model's page: one line of state, one action, the rest under details.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
node - "$ROOT/Model.js" <<'JS'
const assert = require('assert'), fs = require('fs'), vm = require('vm'), c = {module: {exports: {}}};
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), c);
const m = c.module.exports;
const gpu = (key, hw, name, extra) => ({key, hw, name, backend: key.split(':')[0], vramGb: 24, usedMiB: 500, tempC: 40, ...extra});
const rec = (id, name, extra) => ({id, name, family: 'qwen', cards: 1, format: 'EXL3 · 3 bpw', sizeGb: 14, ctx: 131072, engine: 'sglang', ...extra});
const base = {readiness: {state: 'ready'}, host: {freeRamGb: 40, ramGb: 64}, total: 0, life: {requests: 0, days: []}, agents: ['pi'],
  defaults: {agent: 'pi', folder: '/home/u'}, deployments: [], pins: []};
// a 3090, two B70s (one held by another program), a CPU
const s = {...base,
  gpus: [gpu('nvidia:0', 'rtx-3090-24gb', 'RTX 3090'), gpu('intel-xpu:0', 'b70', 'Arc Pro B70'), gpu('intel-xpu:1', 'b70', 'Arc Pro B70'),
    {key: 'cpu:0', hw: 'cpu', name: 'x86-64 AVX2 CPU', backend: 'cpu', ramGb: 64}],
  kinds: [
    {hw: 'rtx-3090-24gb', keys: ['nvidia:0'], free: ['nvidia:0'], taken: [], groups: [],
      models: [rec('q27.3090', 'Qwen3.8-27B'), rec('gemma.3090', 'Gemma 4 26B A4B', {family: 'gemma', engine: 'tabbyapi', format: 'EXL3 · 5.1 bpw'}),
        rec('flash.3090', 'Qwen3.8-Flash-Next', {needs: {host_ram_gb: 75, disk_gb: 85, fast_storage: 'nvme'}, unfit: 'needs 75 GB RAM, you have 40'})]},
    {hw: 'b70', keys: ['intel-xpu:0', 'intel-xpu:1'], free: ['intel-xpu:0'], taken: ['intel-xpu:1'],
      models: [rec('q27.b70', 'Qwen3.8-27B', {format: 'GGUF · Q4_K_M', engine: 'llama.cpp'})],
      groups: [rec('q35.b70x2', 'Qwen3.6-35B-A3B', {cards: 2, format: 'FP8'})]},
    {hw: 'cpu', keys: ['cpu:0'], free: ['cpu:0'], taken: [], groups: [], models: [rec('lfm.cpu', 'LFM2.5-2.6B', {family: 'lfm', format: 'GGUF · Q4_K_M'})]}]};
const home = (st, ui = {}) => m.build(st, {view: 'home', ...ui}).rows;
const tab = (st, ui = {}) => m.build(st, {view: 'models', ...ui}).rows;
const table = rows => rows.filter(r => r.type === 'trow').map(r => r.cells.join(' | '));
const sec = rows => rows.filter(r => r.type === 'sec').map(r => r.label);
let failed = 0;
function test(name, f) { try { f(); console.log('ok - ' + name) } catch (e) { failed++; console.error('not ok - ' + name + ': ' + e.message) } }

test('every model the machine can run, on any of its hardware, groups across cards included', () => {
  const all = m.catalog(s);
  assert.deepEqual(all.map(x => x.name + '@' + x.on), ['Qwen3.8-27B@RTX 3090', 'Gemma 4 26B A4B@RTX 3090', 'Qwen3.8-Flash-Next@RTX 3090',
    'Qwen3.8-27B@B70', 'Qwen3.6-35B-A3B@2× B70', 'LFM2.5-2.6B@CPU']);
  // a setup across more cards than the machine has is listed as too big, saying so, and opens nothing
  const one = m.catalog({...s, kinds: s.kinds.map(k => k.hw === 'b70' ? {...k, keys: ['intel-xpu:0']} : k)}).filter(x => x.n > 1);
  assert.deepEqual(one.map(x => [x.fits, x.unfit, x.action]), [[false, 'needs 2 × Arc Pro B70, this machine has 1', '']]);
});
test('home: tabs, the grid, recommended models as a table, the machine; no search, no Refresh', () => {
  const r = home(s);
  assert.deepEqual(r[0].items.map(t => t.label + (t.on ? '*' : '')), ['home*', 'models']);
  assert.equal(r[1].type, 'life');
  assert.deepEqual(sec(r), ['RECOMMENDED', 'THIS MACHINE']);
  assert.deepEqual(r.find(x => x.type === 'thead').cells, ['MODEL', 'FORMAT', 'ON']);
  assert.deepEqual(table(r), ['Qwen3.8-27B | EXL3 3 bpw | RTX 3090', 'Qwen3.8-27B | GGUF Q4_K_M | B70', 'Qwen3.6-35B-A3B | FP8 | 2× B70', 'LFM2.5-2.6B | GGUF Q4_K_M | CPU']);
  assert(r.filter(x => x.type === 'trow')[2].dim);
  assert(!r.some(x => x.type === 'search' || x.type === 'slot' || (x.items || []).some(a => a.action === 'registry')));
});
test('pinned models lead home, latest first; a running one has a dot, its card Stop', () => {
  const st = {...s, pins: ['gemma.3090', 'lfm.cpu'], deployments: [{id: 'lfm.cpu', name: 'LFM2.5-2.6B', keys: ['cpu:0'], state: 'ready', agent: 'pi', session: {}}]};
  const r = home(st);
  assert.deepEqual(sec(r), ['PINNED', 'THIS MACHINE']);
  assert.deepEqual(table(r), ['Gemma 4 26B A4B | EXL3 5.1 bpw | RTX 3090', 'LFM2.5-2.6B | GGUF Q4_K_M | CPU']);
  assert.equal(r.filter(x => x.type === 'trow')[1].mark, '●');
  const card = r.find(x => x.type === 'run');
  assert.deepEqual([card.primary.action, card.more, card.stop], ['open|lfm.cpu', 'more|lfm.cpu', 'stop|lfm.cpu']);
});
test('models tab: search line, what is on this machine, the rest that fits, too big folded', () => {
  const st = {...s, kinds: s.kinds.map(k => k.hw === 'cpu' ? {...k, models: [{...k.models[0], downloaded: true}]} : k),
    downloads: [{id: 'gemma.3090', state: 'download', detail: '3 of 20 GB', percent: 15}]};
  const r = tab(st);
  assert.deepEqual(r[0].items.map(t => t.label + (t.on ? '*' : '')), ['home', 'models*']);
  assert.equal(r[1].hint, 'type to search 6 models');
  assert.deepEqual(sec(r), ['ON THIS MACHINE', 'MORE THAT FIT']);
  const rows = r.filter(x => x.type === 'trow');
  assert.deepEqual(rows.slice(0, 2).map(x => x.mark + x.cells[0]), ['↓Gemma 4 26B A4B', '✓LFM2.5-2.6B']);
  assert.equal(r.find(x => x.label === 'too big for this machine').value, '1');
  assert(tab(st, {big: true}).some(x => x.type === 'trow' && x.cells[0] === 'Qwen3.8-Flash-Next' && x.dim));
});
test('a model row opens in place: its state and Start, Download, Pin, Details', () => {
  const r = tab(s, {open: 'm:q27.3090'});
  const i = r.findIndex(x => x.type === 'trow' && x.open);
  const box = r[i + 1];
  assert.equal(box.note, 'not downloaded · 14 GB');
  assert.deepEqual(box.items.map(a => a.label + '=' + a.action), ['Start ›=run|q27.3090|nvidia:0', 'Download=download|q27.3090', 'Pin=pin|q27.3090',
    'Details ›=kind|rtx-3090-24gb|nvidia:0|q27.3090']);
});
test('downloaded, downloading, running and pinned rows offer what fits their state', () => {
  const st = {...s, pins: ['lfm.cpu'], kinds: s.kinds.map(k => k.hw === 'cpu' ? {...k, models: [{...k.models[0], downloaded: true}]} : k),
    downloads: [{id: 'gemma.3090', state: 'download', detail: '3 of 20 GB', percent: 15}],
    deployments: [{id: 'q27.b70', name: 'Qwen3.8-27B', keys: ['intel-xpu:0'], state: 'ready', agent: 'pi', session: {}}]};
  const box = id => { const r = tab(st, {open: 'm:' + id}); return r[r.findIndex(x => x.type === 'trow' && x.open) + 1] };
  assert.deepEqual(box('lfm.cpu').items.map(a => a.label), ['Start ›', 'Remove download', 'Unpin', 'Details ›']);
  assert.equal(box('gemma.3090').note, 'downloading · 3 of 20 GB · 15%');
  assert.deepEqual(box('gemma.3090').items.map(a => a.action), ['run|gemma.3090|nvidia:0', 'download|gemma.3090|off', 'pin|gemma.3090', 'kind|rtx-3090-24gb|nvidia:0|gemma.3090']);
  assert.deepEqual(box('q27.b70').items.map(a => a.label), ['Open ›', 'Stop', 'Pin', 'Details ›']);
  assert.equal(box('q27.b70').note, 'running on B70');
});
test('search matches name, format, family and hardware, every word; typing lands on the models tab', () => {
  assert.deepEqual(table(tab(s, {query: 'qwen b70'})), ['Qwen3.8-27B | GGUF Q4_K_M | B70', 'Qwen3.6-35B-A3B | FP8 | 2× B70']);
  assert.deepEqual(table(tab(s, {query: 'GEMMA'})), ['Gemma 4 26B A4B | EXL3 5.1 bpw | RTX 3090']);
  const none = tab(s, {query: 'llama'});
  assert(/No model here matches “llama”/.test(none.find(x => x.type === 'links').note));
});
test('a model page: what it needs, under details', () => {
  const p = m.build(s, {view: 'kind', id: 'rtx-3090-24gb', key: 'nvidia:0', model: 'gemma.3090', details: true});
  assert.equal(p.hero.name, 'Gemma 4 26B A4B');
  assert.deepEqual(p.rows.filter(x => x.type === 'trow' && x.pair).map(x => x.cells.join('=')),
    ['format=EXL3 5.1 bpw', 'engine=tabbyapi', 'GPU=RTX 3090 · 24 GB', 'RAM=–', 'disk=14 GB', 'NVMe=no', 'context=128K tokens']);
  assert(!p.rows.some(x => (x.items || []).some(a => /^(pin|download|forget)\|/.test(a.action))));
});
test('one too big for the machine says why, with no Start', () => {
  const p = m.build(s, {view: 'kind', id: 'rtx-3090-24gb', key: 'nvidia:0', model: 'flash.3090'});
  assert.equal(p.rows[0].label, 'needs 75 GB RAM, you have 40');
  assert(!p.rows.some(x => (x.items || []).some(a => a.label === 'Start ›')));
});
test('a CPU-only machine, one where nothing fits, and one with only multi-card recipes all get a list', () => {
  const cpu = {...base, gpus: [s.gpus[3]], kinds: [s.kinds[2]]};
  assert.deepEqual(table(home(cpu)), ['LFM2.5-2.6B | GGUF Q4_K_M | CPU']);
  const small = {...base, gpus: [s.gpus[0]], kinds: [{...s.kinds[0], models: [s.kinds[0].models[2]]}]};
  assert(/Nothing fits this machine yet/.test(home(small).find(x => x.type === 'links').note));
  assert.equal(tab(small).find(x => x.label === 'too big for this machine').value, '1');
  const pair = {...base, gpus: [s.gpus[1], {...s.gpus[2]}], kinds: [{...s.kinds[1], models: [], free: ['intel-xpu:0', 'intel-xpu:1'], taken: []}]};
  assert.deepEqual(table(home(pair)), ['Qwen3.6-35B-A3B | FP8 | 2× B70']);
});
test('full screen: the same tables with engine, context, download, RAM and NVMe columns', () => {
  const r = tab(s, {wide: true, big: true});
  assert.deepEqual(r.find(x => x.type === 'thead').cells, ['MODEL', 'FORMAT', 'ENGINE', 'ON', 'CONTEXT', 'DOWNLOAD', 'RAM', 'NVMe']);
  assert.deepEqual(r.filter(x => x.type === 'trow').pop().cells, ['Qwen3.8-Flash-Next', 'EXL3 3 bpw', 'sglang', 'RTX 3090', '128K', '14 GB', '75 GB', 'yes']);
});
test('a stale NVIDIA device list is a small banner under this machine, its Fix running setup; never on top', () => {
  const r = home({...s, cdi: {spec: '/etc/cdi/nvidia.yaml', why: '/dev/nvidia1 is gone'}});
  const b = r.find(x => x.type === 'banner');
  assert.deepEqual([b.text, b.alert, b.action], ['NVIDIA device list is out of date (/dev/nvidia1 is gone)', true, 'setup']);
  assert(r.indexOf(b) > r.findIndex(x => x.label === 'THIS MACHINE'));
  assert(!r.some(x => x.type === 'error'));
});
test('the registry line on the models tab is a small banner', () => {
  assert.equal(tab({...s, catalog: {commit: 'a9f394a7658d', at: ''}}).pop().text, 'models from the registry at a9f394a7');
});
test('a running model page hides its address until clicked; full screen shows its model card', () => {
  const st = {...s, deployments: [{id: 'lfm.cpu', name: 'LFM2.5-2.6B', keys: ['cpu:0'], state: 'ready', agent: 'pi', port: 12434, session: {all: {decode: 40}}}]};
  const p = m.build(st, {view: 'run', id: 'lfm.cpu', details: true});
  assert.equal(p.rows[0].note, 'running · 40 tok/s');
  const f = p.rows.find(x => x.icon === 'machine'); assert(f.secret); assert.equal(f.action, 'copy|http://127.0.0.1:12434');
  const w = m.build(st, {view: 'run', id: 'lfm.cpu', wide: true, cards: {'lfm.cpu': '---\nlicense: x\n---\n# LFM\n![x](https://a/b.png)<img src=x><style>.a{b:c}</style><!-- n -->Hi'}});
  assert.equal(w.cardFor, 'lfm.cpu');
  assert.equal(w.rows.find(x => x.type === 'card').text, '# LFM\nHi');
  assert(!m.build(st, {view: 'run', id: 'lfm.cpu'}).rows.some(x => x.type === 'card'));
});
test('hardware: the machine in figures, then each card with its maker, memory, temperature and what is on it', () => {
  const st = {...s, host: {freeRamGb: 40, ramGb: 64, cpus: 48, cpuName: 'AMD EPYC 7413', diskFreeGb: 781, disk: 'nvme'},
    deployments: [{id: 'q27.b70', name: 'Qwen3.8-27B', keys: ['intel-xpu:0'], state: 'ready', agent: 'pi', session: {}}]};
  const r = m.build(st, {view: 'gpus'}).rows;
  assert.deepEqual(r[1].cells.map(c => c.v + c.u + ' ' + c.k), ['3 GPUs', '1/72GB VRAM used', '1 running', '40/64GB RAM free', '48 CPU threads', '781GB NVMe free']);
  const cards = r.filter(x => x.type === 'gpu' && !x.cpu);
  assert.deepEqual(cards.map(c => [c.vendor, c.name, c.status, c.temp]), [['nvidia', 'RTX 3090', 'free', '40°'], ['intel', 'Arc Pro B70', 'running Qwen3.8-27B', '40°'], ['intel', 'Arc Pro B70', 'in use by another program', '40°']]);
  assert.deepEqual(cards.map(c => c.action), ['find|RTX 3090', 'more|q27.b70', 'find|B70']);
  const cpu = r.find(x => x.cpu);
  assert.deepEqual([cpu.name, cpu.mem], ['AMD EPYC 7413', '48 threads · 64 GB RAM']);
});
test('full screen opens a model page with its details shown', () => {
  const w = m.build(s, {view: 'kind', id: 'rtx-3090-24gb', key: 'nvidia:0', model: 'gemma.3090', wide: true});
  assert(!w.rows.some(x => x.label === 'details'));
  assert(w.rows.some(x => x.pair && x.cells[0] === 'engine'));
});
process.exitCode = failed ? 1 : 0;
JS
