#!/usr/bin/env python3
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import os
import unittest
from unittest.mock import patch

ROOT = Path(os.environ.get('OMARCHY_AI_TEST_ROOT', Path(__file__).resolve().parents[1]))
def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT/'lib'/f'{name}.py')
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj)
    return obj
runtime, intel = module('runtime-metrics'), module('intel-metrics')

class Telemetry(unittest.TestCase):
    def test_nonzero_average(self):
        row = {}
        runtime.update_rates(row, 'Avg prompt throughput: 200.0 tokens/s, Avg generation throughput: 20.0 tokens/s\nAvg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s\nAvg prompt throughput: 400.0 tokens/s, Avg generation throughput: 40.0 tokens/s')
        self.assertEqual(row['decodeSum']/row['decodeCount'], 30)
        self.assertEqual(row['prefillSum']/row['prefillCount'], 300)
        runtime.update_rates(row, 'prompt eval time = 100 ms / 100 tokens (1 ms per token, 1000.00 tokens per second)\neval time = 100 ms / 4 tokens (25 ms per token, 40.00 tokens per second)')
        self.assertEqual(row['decodeCount'], 3)
        self.assertEqual(row['prefillCount'], 3)

    def test_token_baseline_reset_and_missing(self):
        row = {}
        for value, instance in [(100, 'a'), (110, 'a'), (110, 'a'), (None, 'a'), (5, 'b'), (3, 'b')]:
            runtime.update_tokens(row, value, instance)
        self.assertEqual(row['tokens'], 18)
        self.assertEqual(runtime.tokens('vllm:generation_tokens_total{engine="0"} 1.1e3\nvllm:generation_tokens_total{engine="1"} 100'), 1200)
        self.assertIsNone(runtime.tokens('unavailable'))

    def test_cache_and_incremental_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state/'slots').mkdir()
            (state/'ledger.json').write_text(json.dumps({'slots': {'model': {'engine': 'owned', 'keys': ['nvidia:0']}}}))
            (state/'slots/model.json').write_text(json.dumps({'engine': 'llama-cpp', 'launch': {'containerPort': 8010}}))
            info = [{'Id': 'id', 'State': {'StartedAt': 'session'}, 'NetworkSettings': {'Networks': {'net': {'IPAddress': '127.0.0.1'}}}}]
            stamp = runtime.datetime.now(runtime.timezone.utc).isoformat().replace('+00:00', 'Z')
            with patch.object(runtime, 'command', return_value=json.dumps(info)), patch.object(runtime.subprocess, 'check_output', return_value=stamp+' eval time = 1 ms (40.00 tokens per second)') as logs, patch.object(runtime.urllib.request, 'urlopen', side_effect=lambda *a, **k: io.BytesIO(b'llamacpp:tokens_predicted_total 100')) as metrics:
                first = runtime.collect(state)
                self.assertEqual(first['model']['decodeTps'], 40)
                self.assertEqual(first['model']['tokensToday'], 0)
                self.assertEqual(runtime.collect(state), first)
                self.assertEqual(logs.call_count, 1)
                self.assertEqual(metrics.call_count, 1)
            saved = json.loads((state/'runtime-metrics.json').read_text())
            saved['day'] = '2000-01-01'; (state/'runtime-metrics.json').write_text(json.dumps(saved))
            with patch.object(runtime, 'command', return_value=json.dumps(info)), patch.object(runtime.subprocess, 'check_output', return_value=''), patch.object(runtime.urllib.request, 'urlopen', return_value=io.BytesIO(b'llamacpp:tokens_predicted_total 125')):
                fresh = runtime.collect(state)['model']
                self.assertEqual(fresh['tokensToday'], 25)
                self.assertIsNone(fresh['decodeTps'])
                history = json.loads((state/'runtime-metrics.json').read_text())['history']
                self.assertEqual(sum(n or 0 for n in history['nvidia:0']['bins']), 25)

    def test_gpu_history_buckets_and_unknown_intervals(self):
        history = {}
        now = runtime.datetime.fromisoformat('2026-09-21T14:16:00+02:00')
        runtime.record_usage(history, ['nvidia:1', 'nvidia:0'], None, now)
        self.assertEqual(history, {})
        for delta in (30, 0, 70):
            runtime.record_usage(history, ['nvidia:1', 'nvidia:0'], delta, now)
        runtime.record_usage(history, ['intel-xpu:0'], 9, now)
        row = history['nvidia:0,nvidia:1']
        self.assertEqual(row['keys'], ['nvidia:0', 'nvidia:1'])
        self.assertEqual(row['bins'][57], 100)
        self.assertIsNone(row['bins'][56])
        self.assertIsNone(row['bins'][58])
        self.assertEqual(len(row['bins']), 96)
        self.assertEqual(history['intel-xpu:0']['bins'][57], 9)

    def test_history_survives_unload_and_resets_at_midnight(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            now = runtime.datetime.now().astimezone()
            history = {}
            runtime.record_usage(history, ['nvidia:0'], 15, now)
            cache = state/'runtime-metrics.json'
            saved = dict(day=now.date().isoformat(), sampled=0, models={}, history=history)
            cache.write_text(json.dumps(saved))
            runtime.collect(state)
            self.assertEqual(json.loads(cache.read_text())['history'], history)
            saved['day'] = '2000-01-01'
            cache.write_text(json.dumps(saved))
            runtime.collect(state)
            self.assertEqual(json.loads(cache.read_text())['history'], {})

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
