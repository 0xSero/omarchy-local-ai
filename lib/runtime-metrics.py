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


def log_usage(source, text, interval=10):
    """Replay timestamped engine output; retain a cursor so each sample counts once.

    llama.cpp reports exact completion counts. vLLM reports rounded rates, so
    rate * log interval is an estimate. Idle log suppression must not turn a
    long quiet gap into generated tokens.
    """
    for line in text.splitlines():
        try:
            at = datetime.fromisoformat(line.split(' ', 1)[0].replace('Z', '+00:00')).astimezone()
        except ValueError:
            continue
        source.setdefault('firstAt', at.timestamp())
        match = re.search(r'(?<!prompt )eval time =.*? /\s*(\d+) tokens', line)
        count = int(match[1]) if match else None
        rate = re.search(r'Avg generation throughput: ([\d.]+)', line)
        if rate:
            engine = re.search(r'Engine (\d+)', line)
            engine = engine[1] if engine else '0'
            previous = source.setdefault('lastLog', {}).get(engine)
            elapsed = at.timestamp() - previous if previous else interval
            # A missing idle line, a restart or a clock jump is not a long sample.
            seconds = elapsed if interval * .5 <= elapsed <= interval * 1.5 else interval
            count = float(rate[1]) * seconds
            source['lastLog'][engine] = at.timestamp()
            source['estimated'] = True
        if count is not None:
            day = at.date().isoformat()
            source.setdefault('days', {})[day] = source.get('days', {}).get(day, 0) + count


def archive_usage(state, history, saved):
    """Import attributable gateway receipts before retained engine log coverage.

    Rebuild this small legacy archive only when the file or coverage changes.
    Request receipts overlapping engine logs must never be added a second time.
    """
    path = state/'usage.jsonl'
    try:
        stat = path.stat()
    except OSError:
        return None
    starts = {}
    for h in history.values():
        if h.get('firstAt'):
            recipe = h['recipe']
            starts[recipe] = min(starts.get(recipe, h['firstAt']), h['firstAt'])
    stamp = [stat.st_mtime_ns, stat.st_size, starts]
    if saved.get('archiveStamp') == stamp:
        return stamp
    hardware = {}
    for hw, entry in read_json(state/'recipes.json').get('hardware', {}).items():
        for recipe in [entry.get('recipe', {})] + entry.get('recipes', []):
            if recipe.get('id'):
                hardware[recipe['id']] = hw
    for key in list(history):
        if key.startswith('archive:'):
            del history[key]
    for line in path.read_text().splitlines():
        try:
            receipt = json.loads(line)
            recipe, stamp_s = receipt.get('recipe'), float(receipt['t'])
            count = float(receipt.get('completion', 0))
            if recipe not in hardware or count < 0 or stamp_s >= starts.get(recipe, float('inf')):
                continue
            at = datetime.fromtimestamp(stamp_s).astimezone()
            source = history.setdefault('archive:'+recipe, dict(recipe=recipe, hardwareId=hardware[recipe], days={}, since=at.isoformat()))
            day = at.date().isoformat()
            source['days'][day] = source['days'].get(day, 0) + count
        except (ValueError, KeyError, TypeError, OverflowError):
            continue
    return stamp


def collect(state):
    now = datetime.now().astimezone()
    day, start = now.date().isoformat(), now.replace(hour=0, minute=0, second=0, microsecond=0)
    cache = state/'runtime-metrics.json'
    saved = read_json(cache)
    if saved.get('usageVersion') == 2 and saved.get('day') == day and 0 <= time.time()-saved.get('sampled', 0) < 10:
        return saved['result']
    old = saved.get('models', {})
    history = saved.get('history', {})
    if saved.get('usageVersion') != 2 and saved.get('day') != day:
        history = {}
    models, result = {}, {}
    for key, slot in read_json(state/'ledger.json').get('slots', {}).items():
        recipe = read_json(state/'slots'/f'{key}.json')
        if recipe.get('engine') not in ('vllm', 'llamacpp', 'llama.cpp', 'llama-cpp'):
            continue
        row = old.get(key, {}).copy()
        if saved.get('day') != day or saved.get('usageVersion') != 2:
            row = {}
        try:
            info = json.loads(command('docker', 'inspect', slot['engine']))[0]
            source_id = 'logs:' + info['Id']
            source = history.get(source_id, dict(recipe=key, keys=slot.get('keys', []), days={}, since=info['State']['StartedAt']))
            cursor = source.get('cursor', '1970-01-01T00:00:00Z')
            end = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
            logs = subprocess.check_output(['docker', 'logs', '--timestamps', '--since', cursor, '--until', end, slot['engine']], stderr=subprocess.STDOUT, text=True, timeout=6)
            logs = '\n'.join(line for line in logs.splitlines() if line.split(' ', 1)[0] > cursor)
            midnight = start.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')
            update_rates(row, '\n'.join(line for line in logs.splitlines() if line.split(' ', 1)[0] >= midnight))
            env = dict(e.split('=', 1) for e in info.get('Config', {}).get('Env', []) if '=' in e)
            interval = float(env.get('VLLM_LOG_STATS_INTERVAL', 10))
            log_usage(source, logs, interval if interval > 0 else 10)
            source['cursor'] = end
            history[source_id] = source
            # Replace the old post-install counter buckets only after replay succeeds.
            history.pop(','.join(sorted(slot.get('keys', []))), None)
            row['updated'] = now.isoformat()
        except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError):
            pass
        models[key] = row
    archive_stamp = archive_usage(state, history, saved)
    for key, row in models.items():
        result[key] = {kind+'Tps': round(row[kind+'Sum']/row[kind+'Count'], 1) if row.get(kind+'Count') else None for kind in ('decode', 'prefill')}
        sources = [h for h in history.values() if h.get('recipe') == key]
        result[key].update(tokensToday=round(sum(h.get('days', {}).get(day, 0) for h in sources)) if sources else None,
                           usageEstimated=any(h.get('estimated') for h in sources),
                           usageSince=start.isoformat() if sources else '', statsUpdatedAt=row.get('updated'))
    temp = cache.with_suffix('.tmp')
    temp.write_text(json.dumps(dict(usageVersion=2, archiveStamp=archive_stamp, day=day, sampled=time.time(), models=models, result=result, history=history)))
    temp.replace(cache)
    return result


if __name__ == '__main__':
    state = Path(sys.argv[1]); state.mkdir(parents=True, exist_ok=True)
    with (state/'runtime-metrics.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        print(json.dumps(collect(state)))
