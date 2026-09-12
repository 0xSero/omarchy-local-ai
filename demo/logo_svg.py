"""The Local AI mark as vector: the same 15x15 pixel orb as demo/brand.py, as SVG. Usage: python3 demo/logo_svg.py media/"""
import math, sys, os
OUT = sys.argv[1]
BG, INK = (10, 10, 10), (245, 245, 245)
def orb_svg(size=512, cells=15, pad=0.0, field=0.08, background=True, corner=0.18):
    inner = size * (1 - 2 * pad); px = inner / cells; gap = px * 0.28; off = size * pad
    half = cells / 2; radius = half * 0.86; side = px - gap
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    if background:   # a rounded tile; the pixel field is clipped to it so corners stay clean
        parts.append(f'<clipPath id="tile"><rect width="{size}" height="{size}" rx="{size*corner:.1f}"/></clipPath><g clip-path="url(#tile)">')
        parts.append(f'<rect width="{size}" height="{size}" rx="{size*corner:.1f}" fill="rgb{BG}"/>')
    for row in range(cells):
        for col in range(cells):
            dx, dy = col + 0.5 - half, row + 0.5 - half; dist = math.hypot(dx, dy)
            if dist > radius + 0.5: a = field
            else:
                a = 0.92 * (1 - (dist / (radius + 0.5)) ** 2 * 0.55)
                if dist > radius - 0.5: a *= 0.5 + 0.5 * (radius + 0.5 - dist)
                a = max(a, field)
            if not background and a <= field: continue   # transparent variant: only the lit circle
            c = tuple(int(BG[i] + (INK[i] - BG[i]) * a) for i in range(3))
            x, y = off + col * px + gap / 2, off + row * px + gap / 2
            parts.append(f'<rect x="{x:.2f}" y="{y:.2f}" width="{side:.2f}" height="{side:.2f}" rx="{side*0.28:.2f}" fill="rgb{c}"/>')
    if background: parts.append('</g>')
    parts.append('</svg>'); return "\n".join(parts)
open(f"{OUT}/logo.svg", "w").write(orb_svg())
open(f"{OUT}/logo-mark.svg", "w").write(orb_svg(background=False))
print("wrote logo.svg (dark tile) and logo-mark.svg (circle only, transparent)")
