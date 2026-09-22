#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import os
import time
import unittest
from unittest.mock import patch

ROOT = Path(os.environ.get('OMARCHY_AI_TEST_ROOT', Path(__file__).resolve().parents[1]))
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'lib'/f'{name}.py')
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj)
    return obj
runtime, intel = module('runtime-metrics'), module('intel-metrics')

class Telemetry(unittest.TestCase):
    @unittest.skipUnless(hasattr(time, 'tzset'), 'requires local timezone control')
    def test_daily_rates_use_local_midnight_on_dst_transition_days(self):
        original_datetime = runtime.datetime
        for month, day, offset, log_hour in [(3, 8, '-05:00', 5), (11, 1, '-04:00', 4)]:
            with self.subTest(month=month), tempfile.TemporaryDirectory() as directory:
                class Clock(original_datetime):
                    @classmethod
                    def now(cls, tz=None):
                        value = cls(2026, month, day, 12, tzinfo=runtime.timezone.utc)
                        return value.astimezone(tz) if tz else value.astimezone().replace(tzinfo=None)
                state = Path(directory); (state/'slots').mkdir()
                (state/'ledger.json').write_text(json.dumps({'slots': {'model': {'engine': 'owned'}}}))
                (state/'slots/model.json').write_text(json.dumps({'engine': 'llama-cpp'}))
                info = [{'Id': 'fixture', 'State': {'StartedAt': 'session'}}]
                stamp = f'2026-{month:02d}-{day:02d}T{log_hour:02d}:30:00Z'
                logs = stamp+' eval time = 1 ms / 3 tokens (30.00 tokens per second)'
                try:
                    with patch.dict(os.environ, {'TZ': 'EST5EDT,M3.2.0,M11.1.0'}):
                        time.tzset()
                        with patch.object(runtime, 'datetime', Clock), patch.object(runtime, 'command', return_value=json.dumps(info)), patch.object(runtime.subprocess, 'check_output', return_value=logs):
                            result = runtime.collect(state)['model']
                        self.assertEqual(result['usageSince'], f'2026-{month:02d}-{day:02d}T00:00:00{offset}')
                        self.assertEqual(result['decodeTps'], 30)
                finally:
                    time.tzset()

    def test_nonzero_average(self):
        row = {}
        runtime.update_rates(row, 'Avg prompt throughput: 200.0 tokens/s, Avg generation throughput: 20.0 tokens/s\nAvg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s\nAvg prompt throughput: 400.0 tokens/s, Avg generation throughput: 40.0 tokens/s')
        self.assertEqual(row['decodeSum']/row['decodeCount'], 30)
        self.assertEqual(row['prefillSum']/row['prefillCount'], 300)
        runtime.update_rates(row, 'prompt eval time = 100 ms / 100 tokens (1 ms per token, 1000.00 tokens per second)\neval time = 100 ms / 4 tokens (25 ms per token, 40.00 tokens per second)')
        self.assertEqual(row['decodeCount'], 3)
        self.assertEqual(row['prefillCount'], 3)

    def test_timestamped_history_and_rate_estimates(self):
        source = {'days': {}}
        # Local timestamps keep the test independent of the machine timezone.
        at = runtime.datetime.now().astimezone().replace(hour=9, minute=0, second=0, microsecond=0)
        day = at.date().isoformat()
        def line(minutes, text):
            return runtime.datetime.fromtimestamp(at.timestamp()+minutes*60).astimezone().isoformat()+' '+text
        logs = '\n'.join([
            line(0, 'Engine 000: Avg generation throughput: 20.0'),
            line(30, 'Engine 000: Avg generation throughput: 2.0'),
            line(30, 'prompt eval time = 10 ms / 1000 tokens'),
            line(30, 'eval time = 10 ms / 13 tokens'),
            'not-a-time eval time = 10 ms / 999 tokens'])
        runtime.log_usage(source, logs)
        self.assertEqual(source['days'][day], 233)  # idle gap is NOT 30 minutes of output
        self.assertTrue(source['estimated'])
        runtime.log_usage(source, line(31, 'Engine 001: Avg generation throughput: 3.0'), 5)
        self.assertEqual(source['days'][day], 248)

    def test_backfill_migration_cache_and_incremental_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state/'slots').mkdir()
            (state/'ledger.json').write_text(json.dumps({'slots': {'model': {'engine': 'owned', 'keys': ['nvidia:0', 'nvidia:1']}}}))
            (state/'slots/model.json').write_text(json.dumps({'engine': 'llama-cpp'}))
            info = [{'Id': 'id', 'State': {'StartedAt': 'session'}}]
            now = runtime.datetime.now().astimezone()
            stamp = now.replace(hour=0, minute=0, second=1).astimezone(runtime.timezone.utc).isoformat().replace('+00:00', 'Z')
            cache = state/'runtime-metrics.json'
            cache.write_text(json.dumps(dict(day=now.date().isoformat(), sampled=runtime.time.time(), result={}, models={'model': {'decodeSum': 99, 'decodeCount': 1}}, history={'nvidia:0,nvidia:1': {'keys': ['nvidia:0','nvidia:1'], 'bins':[25]+[None]*95}})))
            with patch.object(runtime, 'command', return_value=json.dumps(info)), patch.object(runtime.subprocess, 'check_output', return_value=stamp+' eval time = 1 ms / 123 tokens (40.00 tokens per second)') as logs:
                first = runtime.collect(state)
                self.assertEqual(first['model']['decodeTps'], 40)
                self.assertEqual(first['model']['tokensToday'], 123)
                self.assertFalse(first['model']['usageEstimated'])
                self.assertEqual(runtime.collect(state), first)
                self.assertEqual(logs.call_count, 1)
            saved = json.loads(cache.read_text())
            self.assertEqual(len(saved['history']), 1)  # replaces old 25, never adds it twice
            self.assertEqual(sum(next(iter(saved['history'].values()))['days'].values()), 123)
            cursor = next(iter(saved['history'].values()))['cursor']
            saved['sampled'] = 0; cache.write_text(json.dumps(saved))
            with patch.object(runtime, 'command', return_value=json.dumps(info)), patch.object(runtime.subprocess, 'check_output', return_value=cursor+' eval time = 1 ms / 123 tokens (40.00 tokens per second)'):
                self.assertEqual(runtime.collect(state)['model']['tokensToday'], 123)
            # Unloading and midnight both retain accumulated historical totals.
            (state/'ledger.json').write_text('{}')
            saved = json.loads(cache.read_text()); saved['sampled'] = 0; cache.write_text(json.dumps(saved))
            runtime.collect(state)
            self.assertEqual(json.loads(cache.read_text())['history'], saved['history'])
            saved['day'] = '2000-01-01'; cache.write_text(json.dumps(saved))
            runtime.collect(state)
            self.assertEqual(json.loads(cache.read_text())['history'], saved['history'])

    def test_legacy_receipts_only_before_log_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state/'recipes.json').write_text(json.dumps({'hardware':{'rtx':{'recipe':{'id':'model'},'recipes':[{'id':'older'}]}}}))
            (state/'usage.jsonl').write_text('\n'.join(json.dumps(r) for r in [
                {'recipe':'model','t':100,'completion':20},
                {'recipe':'model','t':200,'completion':30},  # already covered by logs
                {'recipe':'older','t':100,'completion':10},
                {'t':100,'completion':99}]))
            history = {'logs:id':{'recipe':'model','firstAt':150,'days':{}}}
            stamp = runtime.archive_usage(state, history, {})
            self.assertEqual(sum(history['archive:model']['days'].values()), 20)
            self.assertEqual(sum(history['archive:older']['days'].values()), 10)
            self.assertEqual(history['archive:older']['hardwareId'], 'rtx')
            self.assertEqual(len(history), 3)
            runtime.archive_usage(state, history, {'archiveStamp':stamp})
            self.assertEqual(sum(history['archive:model']['days'].values()), 20)

    def test_failed_replay_preserves_old_history(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state/'slots').mkdir()
            (state/'ledger.json').write_text(json.dumps({'slots': {'model': {'engine': 'owned', 'keys': ['nvidia:0']}}}))
            (state/'slots/model.json').write_text(json.dumps({'engine': 'vllm'}))
            history = {'nvidia:0': {'keys':['nvidia:0'], 'bins':[100]+[None]*95}}
            cache = state/'runtime-metrics.json'
            cache.write_text(json.dumps(dict(day=runtime.datetime.now().astimezone().date().isoformat(), history=history)))
            with patch.object(runtime, 'command', side_effect=OSError):
                runtime.collect(state)
            self.assertEqual(json.loads(cache.read_text())['history'], history)

    def test_amd_sysfs_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            device = Path(directory)/'bus/pci/devices/0000:03:00.0'
            (device/'hwmon/hwmon7').mkdir(parents=True)
            for name, value in {'mem_info_vram_used': 3*1048576, 'mem_info_vram_total': 8*1048576, 'gpu_busy_percent': 73, 'hwmon/hwmon7/temp1_input': 62500}.items():
                (device/name).write_text(str(value))
            script = '''source "$1/lib/hardware.sh"; amd_render_node_for_bdf() { return 1; }; amd_gpus_resolve_render_nodes '[{"index":0,"bdf":"0000:03:00.0","renderNode":null}]' '''
            result = subprocess.check_output(['bash', '-c', script, '_', str(ROOT)], env=dict(os.environ, OMARCHY_AI_SYSFS_ROOT=directory), text=True)
            gpu = json.loads(result)[0]
            self.assertEqual((gpu['usedMiB'], gpu['freeMiB'], gpu['utilPct'], gpu['tempC']), (3, 5, 73, 62.5))

    def test_intel_client_dedup_and_activity(self):
        block = 'pos: 0\ndrm-driver: xe\ndrm-client-id: 4\ndrm-pdev: 0000:84:00.0\ndrm-cycles-ccs: 20\ndrm-total-cycles-ccs: 100\n'
        previous = intel.clients(block + block)
        self.assertEqual(len(previous), 1)
        current = intel.clients(block.replace('ccs: 20', 'ccs: 70').replace('ccs: 100', 'ccs: 200'))
        self.assertEqual(intel.activity(previous, current), {'0000:84:00.0': 50})
        self.assertEqual(intel.activity(previous, previous), {})
        self.assertEqual(intel.activity(current, previous), {})

if __name__ == '__main__':
    unittest.main()
