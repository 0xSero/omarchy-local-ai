# The panel's tree: every screen a person can reach, the screen itself drawn small in each node, and the action that
# leads there written on the line into it. Out = leaves the panel (a terminal); gap = not designed yet.
# Usage: python3 design/rows/tree.py <blobs.json: screen id → uploaded image url> <out.dc.html>
import json, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
BLOB = json.load(open(sys.argv[1]))
H1 = {s["id"]: s["h"] for s in json.load(open(os.path.join(HERE, "out/frame/row.json")))["screens"]}
# (edge label, kind, screen id or title, children)
T = ("", "root", "Local AI panel", [
  ("not set up", "screen", "not-ready-setup", [("Set up", "out", "terminal: Omarchy asks for the password", [("done", "screen", "home-first", [])])]),
  ("Docker stopped", "screen", "not-ready-docker", [("Start Docker", "out", "terminal: sudo systemctl start docker", [])]),
  ("Omarchy too old", "screen", "not-ready-old", [("Update Omarchy", "out", "terminal: omarchy-update", [])]),
  ("no tested card", "screen", "no-supported-gpu", [("See supported cards", "out", "browser: local.sybilsolutions.ai", [])]),
  ("home tab", "screen", "home", [("󰊓 full screen", "screen", "full-home", [])]),
  ("gpus tab", "screen", "gpus", [
    ("open a running row", "screen", "gpus-open-running", [
      ("Open pi", "out", "pi opens on the model", []),
      ("model: change ›", "screen", "config", [("hover a model on disk", "screen", "config-hover-on-disk", [])]),
      ("agent ›", "screen", "agent", []), ("folder ›", "screen", "folder", []), ("share: turn on", "screen", "share", []),
      ("logs", "out", "the log in a terminal", []),
    ]),
    ("open a free row", "screen", "gpus-open-free", [
      ("Run (the picked model)", "screen", "starting-download", [("downloaded", "screen", "starting-load", [])]),
    ]),
    ("open an in-use row", "screen", "gpus-open-in-use", []),
    ("a model stops by itself", "screen", "notification", [("its row, opened", "screen", "stopped", [])]),
    ("󰊓 full screen", "screen", "full-gpus", []),
    ("a one-GPU machine", "screen", "one-gpu", []),
    ("no GPU: the CPU", "screen", "cpu-only", []),
  ]),
])
SC, CW, GAPX, M, TOP = 0.5, 170, 190, 64, 150
def size(kind, ref):
    if kind == "screen": return CW, round(H1[ref] * (CW / 1280 if ref.startswith("full") else SC)) + 24
    if kind == "gap": return CW, 96
    return CW, 44
nodes, lines, labels, cursor = [], [], [], [TOP]
def place(n, d):
    edge, kind, ref, kids = n
    w, h = size(kind, ref)
    ys = [place(k, d + 1) for k in kids]
    x = M + d * (CW + GAPX)
    if ys: cy = (ys[0] + ys[-1]) / 2
    else: cy = cursor[0] + h / 2; cursor[0] += h + 32
    # a node taller than the branch under it keeps its own room: the next sibling starts below it
    cursor[0] = max(cursor[0], cy + h / 2 + 32)
    nodes.append((x, round(cy - h / 2), w, h, kind, ref))
    if ys:
        bus = x + CW + 40
        lines.append((x + CW, cy, bus, cy))
        if len(ys) > 1: lines.append((bus, ys[0], bus, ys[-1]))
        for k, yy in zip(kids, ys):
            lines.append((bus, yy, M + (d + 1) * (CW + GAPX), yy))
            labels.append((bus + 10, yy - 24, k[0]))
    return cy
place(T, 0)
W = M * 2 + max(x + w for x, _, w, *_ in nodes) - M
H = round(cursor[0] + M)
out = []
for x1, y1, x2, y2 in lines:
    x1, y1, x2, y2 = round(x1), round(y1), round(x2), round(y2)
    if y1 == y2:
        n = x2 - x1
        out.append(f'<svg width="{n}" height="8" viewBox="0 0 {n} 8" preserveAspectRatio="none" style="position: absolute; left: {x1}px; top: {y1 - 4}px; width: {n}px; height: 8px; overflow: visible; fill: none; stroke: rgb(110,110,114); stroke-width: 1.5"><path d="M 0 4 L {n} 4"></path></svg>')
    else:
        n = y2 - y1
        out.append(f'<svg width="8" height="{n}" viewBox="0 0 8 {n}" preserveAspectRatio="none" style="position: absolute; left: {x1 - 4}px; top: {y1}px; width: 8px; height: {n}px; overflow: visible; fill: none; stroke: rgb(110,110,114); stroke-width: 1.5"><path d="M 4 0 L 4 {n}"></path></svg>')
for x, y, w, h, kind, ref in nodes:
    if kind == "screen":
        out.append(f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; box-sizing: border-box; font-size: 11px; color: rgb(180,180,181)"><span>{ref}</span><img src="{BLOB[ref]}" alt="{ref}" style="display: block; margin-top: 6px; width: {w}px; height: {h - 24}px; border-radius: 3px; outline: 1px solid rgb(60,60,64)"></div>')
    elif kind == "gap":
        out.append(f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; box-sizing: border-box; padding: 10px; display: flex; align-items: center; justify-content: center; text-align: center; font-size: 11px; color: rgb(140,140,144); font-style: italic; border: 1px dashed rgb(110,110,114); border-radius: 4px"><span>not designed yet<br>{ref}</span></div>')
    elif kind == "out":
        out.append(f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; box-sizing: border-box; padding: 0 12px; display: flex; align-items: center; font-size: 11px; color: rgb(214,214,214); border: 1px solid rgb(140,140,144); border-radius: 22px"><span>↗ {ref}</span></div>')
    else:
        out.append(f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; box-sizing: border-box; padding: 0 12px; display: flex; align-items: center; font-size: 13px; color: #121214; background: rgb(230,230,230); border-radius: 4px"><span>{ref}</span></div>')
for x, y, t in labels:
    out.append(f'<div style="position: absolute; left: {x}px; top: {round(y)}px; width: {GAPX - 60}px; font-size: 11px; line-height: 14px; color: rgb(214,214,214)">{t}</div>')
html = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Panel screens and actions</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&amp;display=swap" rel="stylesheet">
<style>body{{margin:0;background:#121214}}</style>
</helmet>
<div style="position: relative; width: {W}px; height: {H}px; background: #121214; font-family: 'JetBrains Mono', ui-monospace, monospace">
<div style="position: absolute; left: {M}px; top: 48px; font-size: 22px; color: rgb(230,230,230)">Local AI panel: what a person sees, and what leads there</div>
<div style="position: absolute; left: {M}px; top: 86px; font-size: 12px; color: rgb(180,180,181)">each box is the screen at that point · the line into it is the action · ↗ leaves the panel</div>
{chr(10).join(out)}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{W},"height":{H}}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
'''
open(sys.argv[2], "w").write(html)
print(W, H, len(nodes), "nodes")
