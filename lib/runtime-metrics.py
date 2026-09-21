#!/usr/bin/env python3
"""Incremental engine telemetry: one shared cache, no daemon or inference requests."""
from datetime import datetime, timezone
from pathlib import Path
import fcntl
import json
import re
import subprocess
import sys
import time
import urllib.request


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True, timeout=6)


def rates(text):
    for line in text.splitlines():
        match = re.search(r'Avg prompt throughput: ([\d.]+).*Avg generation throughput: ([\d.]+)', line)
        if match:
            yield 'prefill', float(match[1])
            yield 'decode', float(match[2])
        else:
            match = re.search(r'(prompt eval|(?<!prompt )eval) time =.*?([\d.]+) tokens per second', line)
            if match:
                yield 'prefill' if match[1] == 'prompt eval' else 'decode', float(match[2])


def update_rates(row, text):
    for kind, value in rates(text):
        if value > 0:
            row[kind+'Sum'] = row.get(kind+'Sum', 0) + value
            row[kind+'Count'] = row.get(kind+'Count', 0) + 1


def tokens(text):
    values = re.findall(r'^(?:vllm:generation_tokens_total|llamacpp:tokens_predicted_total)(?:\{[^\n]*\})?\s+([\d.eE+\-]+)', text, re.M)
    return sum(float(v) for v in values) if values else None


def update_tokens(row, count, instance):
    if count is None:
        return None
    delta = None
    previous = row.get('counter')
    if previous is not None:
        delta = count if row.get('instance') != instance or count < previous else count - previous
        row['tokens'] = row.get('tokens', 0) + delta
    row.update(counter=count, instance=instance)
    return delta


def record_usage(history, keys, delta, now):
    # Keep a day's 15-minute buckets per GPU allocation, even after a model stops.
    # Counts belong to the interval in which they were observed; no backfill.
    if not keys or delta is None:
        return
    key = ",".join(sorted(keys))
    row = history.setdefault(key, dict(keys=sorted(keys), bins=[None]*96, since=now.isoformat()))
    bucket = now.hour*4 + now.minute//15
    row['bins'][bucket] = (row['bins'][bucket] or 0) + delta


def collect(state):
    now = datetime.now().astimezone()
    day, start = now.date().isoformat(), now.replace(hour=0, minute=0, second=0, microsecond=0)
    cache = state/'runtime-metrics.json'
    saved = read_json(cache)
    if saved.get('day') == day and 0 <= time.time()-saved.get('sampled', 0) < 10:
        return saved['result']
    old = saved.get('models', {})
    history = saved.get('history', {}) if saved.get('day') == day else {}
    models, result = {}, {}
    for key, slot in read_json(state/'ledger.json').get('slots', {}).items():
        recipe = read_json(state/'slots'/f'{key}.json')
        if recipe.get('engine') not in ('vllm', 'llamacpp', 'llama.cpp', 'llama-cpp'):
            continue
        row = old.get(key, {}).copy()
        if saved.get('day') != day:
            row = {k: v for k, v in row.items() if k in ('counter', 'instance')}
        row.setdefault('since', start.isoformat() if saved.get('day') and row.get('counter') is not None else now.isoformat())
        try:
            info = json.loads(command('docker', 'inspect', slot['engine']))[0]
            instance = info['Id'] + info['State']['StartedAt']
            if row.get('logInstance') != instance:
                row.pop('cursor', None)
            cursor = row.get('cursor', start.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z'))
            end = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
            logs = subprocess.check_output(['docker', 'logs', '--timestamps', '--since', cursor, '--until', end, slot['engine']], stderr=subprocess.STDOUT, text=True, timeout=6)
            update_rates(row, '\n'.join(line for line in logs.splitlines() if line.split(' ', 1)[0] > cursor))
            row.update(cursor=end, logInstance=instance)
            address = next(n['IPAddress'] for n in info['NetworkSettings']['Networks'].values() if n.get('IPAddress'))
            port = recipe['launch']['containerPort']
            with urllib.request.urlopen(f'http://{address}:{port}/metrics', timeout=2) as response:
                count = tokens(response.read(2*1024*1024).decode())
            delta = update_tokens(row, count, instance)
            record_usage(history, slot.get('keys', []), delta, now)
            row['updated'] = now.isoformat()
        except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError):
            pass
        models[key] = row
        result[key] = {kind+'Tps': round(row[kind+'Sum']/row[kind+'Count'], 1) if row.get(kind+'Count') else None for kind in ('decode', 'prefill')}
        result[key].update(tokensToday=round(row.get('tokens', 0)) if 'counter' in row else None,
                           usageSince=row['since'], statsUpdatedAt=row.get('updated'))
    temp = cache.with_suffix('.tmp')
    temp.write_text(json.dumps(dict(day=day, sampled=time.time(), models=models, result=result, history=history)))
    temp.replace(cache)
    return result


if __name__ == '__main__':
    state = Path(sys.argv[1]); state.mkdir(parents=True, exist_ok=True)
    with (state/'runtime-metrics.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        print(json.dumps(collect(state)))
