#!/usr/bin/env python3
"""Read all Intel GPUs through Level Zero Sysman, keyed by PCI address."""
import ctypes as C
import json
import sys
import time
import fcntl
import re
import subprocess
from pathlib import Path

U, P = C.c_uint32, C.c_void_p
class PCI(C.Structure):
    _fields_ = [('stype', U), ('next', P), ('address', U * 4), ('gen', C.c_int32),
                ('width', C.c_int32), ('bandwidth', C.c_int64), ('flags', C.c_uint8 * 3)]
class Memory(C.Structure):
    _fields_ = [('stype', U), ('next', P), ('health', U), ('free', C.c_uint64), ('size', C.c_uint64)]

def scan():
    lib = C.CDLL('libze_loader.so.1')
    if lib.zesInit(0):
        return {}
    def handles(name, *args):
        fn = getattr(lib, name); count = U()
        if fn(*args, C.byref(count), None) or not count.value:
            return []
        items = (P * count.value)()
        return [] if fn(*args, C.byref(count), items) else [P(x) for x in items[:count.value]]
    out = {}
    for driver in handles('zesDriverGet'):
        for device in handles('zesDeviceGet', driver):
            pci = PCI(stype=2)
            if lib.zesDevicePciGetProperties(device, C.byref(pci)):
                continue
            key = '%04x:%02x:%02x.%x' % tuple(pci.address)
            mem = []
            for handle in handles('zesDeviceEnumMemoryModules', device):
                state = Memory(stype=0x1e)
                if not lib.zesMemoryGetState(handle, C.byref(state)) and state.size >= state.free and state.size:
                    mem.append(state)
            row = {}
            if mem:
                row.update(totalMiB=sum(m.size for m in mem)/1048576,
                           usedMiB=sum(m.size-m.free for m in mem)/1048576,
                           freeMiB=sum(m.free for m in mem)/1048576)
            out[key] = row
    return out

def clients(text):
    out = {}
    for block in re.split(r"(?m)^pos:", text):
        fields = dict(re.findall(r"(?m)^(drm-[^:]+):\s*([^\n]+)", block))
        if fields.get('drm-driver') != 'xe' or 'drm-pdev' not in fields:
            continue
        key = fields['drm-pdev'] + '/' + fields.get('drm-client-id', '')
        engines = {}
        for name, value in fields.items():
            if name.startswith('drm-cycles-'):
                engine = name.removeprefix('drm-cycles-')
                total = fields.get('drm-total-cycles-' + engine)
                if total:
                    engines[engine] = [int(value), int(total), int(fields.get('drm-engine-capacity-' + engine, '1'))]
        out[key] = engines  # duplicated fd/clients are counted once
    return out


def activity(previous, current):
    grouped = {}
    for client, engines in current.items():
        pci = client.split('/')[0]
        for engine, (active, total, capacity) in engines.items():
            old = previous.get(client, {}).get(engine)
            if old and total > old[1] and active >= old[0]:
                by_engine = grouped.setdefault(pci, {})
                by_engine[engine] = by_engine.get(engine, 0) + 100 * (active-old[0]) / (total-old[1]) / capacity
    return {pci: round(min(100, max(values.values())), 1) for pci, values in grouped.items()}


def sample(state):
    cache = state/'intel-activity.json'
    try:
        saved = json.loads(cache.read_text())
    except (OSError, ValueError):
        saved = {}
    if 0 <= time.monotonic() - saved.get('sampled', 0) < 10:
        return saved['result']
    out = scan()
    current = {}
    for path in Path('/proc').glob('[0-9]*/fdinfo/*'):
        try:
            current.update(clients(path.read_text()))
        except OSError:
            pass
    # Root-owned inference processes are readable inside their existing container.
    try:
        slots = json.loads((state/'ledger.json').read_text()).get('slots', {})
        for slot in slots.values():
            if any(k.startswith('intel-xpu:') for k in slot.get('keys', [])):
                result = subprocess.run(['docker', 'exec', slot['engine'], 'sh', '-c',
                    'cat /proc/[0-9]*/fdinfo/* 2>/dev/null'], capture_output=True, text=True, timeout=2)
                current.update(clients(result.stdout))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    previous = saved.get('clients', {})
    for pci, value in activity(previous, current).items():
        out.setdefault(pci, {})['utilPct'] = value
    temp = cache.with_suffix('.tmp')
    temp.write_text(json.dumps({'sampled': time.monotonic(), 'clients': current, 'result': out})); temp.replace(cache)
    return out


if __name__ == '__main__':
    try:
        state = Path(sys.argv[1]); state.mkdir(parents=True, exist_ok=True)
        with (state/'intel-activity.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            print(json.dumps(sample(state)))
    except (OSError, AttributeError):
        print('{}')
