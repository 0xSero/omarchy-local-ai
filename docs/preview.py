#!/usr/bin/env python3
"""Build the marketplace preview (1600x900) from a live panel capture.

The marketplace renders one image per listing, scaled to 1600 px on the detail page and 720 px on
the browse card, and reads it from `preview.png` in the repository root at the listed commit. This
script cuts the panel out of a screenshot of the running plugin, puts the brand mark and the card's
own words beside it, and writes that file. Nothing here runs at plugin runtime.

    python3 docs/preview.py --shot shot.png --out preview.png

`shot` must be a full-screen capture of the panel open on the desktop (test/visual captures one over
SSH). The panel is found by its own background colour, so the crop does not depend on the display
resolution. Needs Pillow and numpy.
"""

import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1600, 900
BG = (10, 10, 10)
INK = (245, 245, 245)
DIM = (150, 150, 150)
FAINT = (110, 110, 110)
FRAME = (58, 58, 58)
CELL = (22, 22, 22)

FONT_CANDIDATES = (
    ("bold", "~/Library/Fonts/CaskaydiaMonoNerdFont-Bold.ttf"),
    ("light", "~/Library/Fonts/CaskaydiaMonoNerdFont-Light.ttf"),
    ("bold", "/System/Library/Fonts/Menlo.ttc"),
    ("light", "/System/Library/Fonts/Menlo.ttc"),
    ("bold", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"),
    ("light", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
)

HEADLINE = ("Validated local models, several at once,", "each on its own cards.")
STEPS = (
    ("Start", "downloads the pinned weights and proves the model answers,", "then serves it on loopback behind a key"),
    ("Open agent", "claude, codex, pi, omp, opencode, crush… open on it;", "nothing is written to your config"),
    ("Share", "the same keyed endpoint on your tailnet,", "one click, no root"),
)
FOOTER = ("256K context on verified TP2 recipes · NVIDIA + Intel Arc", "Docker without the docker group: one password prompt per action")


def font(weight, size):
    for want, path in FONT_CANDIDATES:
        if want == weight and Path(path).expanduser().exists():
            return ImageFont.truetype(str(Path(path).expanduser()), size)
    return ImageFont.load_default(size)


def orb(size, cells=15, pad=0.08, field=0.08):
    """The card's orb: a field of rounded pixels with a circle lit inside, brightest at the centre."""
    im = Image.new("RGBA", (size, size), BG + (255,))
    d = ImageDraw.Draw(im)
    inner = size * (1 - 2 * pad)
    px, gap, off = inner / cells, inner / cells * 0.28, size * pad
    half, radius = cells / 2, cells / 2 * 0.86
    for row in range(cells):
        for col in range(cells):
            dist = math.hypot(col + 0.5 - half, row + 0.5 - half)
            if dist > radius + 0.5:
                a = field
            else:
                a = max(0.92 * (1 - (dist / (radius + 0.5)) ** 2 * 0.55), field)
                if dist > radius - 0.5:
                    a *= 0.5 + 0.5 * (radius + 0.5 - dist)
            x, y = off + col * px + gap / 2, off + row * px + gap / 2
            side = px - gap
            fill = tuple(int(BG[i] + (INK[i] - BG[i]) * a) for i in range(3))
            d.rounded_rectangle([x, y, x + side, y + side], radius=side * 0.28, fill=fill + (255,))
    return im


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def panel_crop(shot):
    """The panel plus the desktop immediately around it, found by the panel's own background colour."""
    a = np.array(shot.convert("L")).astype(int)
    interior = (a >= 12) & (a <= 45)
    cols = np.nonzero(interior.mean(axis=0) > 0.5)[0]
    if not len(cols):
        sys.exit("no panel found in the capture: is the plugin open?")
    band = (a[:, cols.min() : cols.max() + 1] > 8).mean(axis=1)
    rows = np.nonzero(band > 0.5)[0]
    return shot.crop(
        (
            max(cols.min() - 10, 0),
            max(rows.min() - 10, 0),
            min(cols.max() + 10, shot.width),
            min(rows.max() + 10, shot.height),
        )
    )


def fitted(text, face, limit):
    if face.getlength(text) > limit:
        sys.exit(f"text does not fit the column at {face.size}px: {text!r}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--shot", type=Path, required=True, help="full-screen capture of the open panel")
    p.add_argument("--out", type=Path, required=True, help="where to write preview.png")
    a = p.parse_args()

    card = panel_crop(Image.open(a.shot).convert("RGB"))
    scale = min(780 / card.height, 1.0)   # near 1:1: the panel's own text must stay readable
    card = card.resize((round(card.width * scale), round(card.height * scale)), Image.LANCZOS)

    pv = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(pv)
    for y in range(0, H, 22):
        for x in range(0, W, 22):
            d.rounded_rectangle([x + 8, y + 8, x + 13, y + 13], radius=1.5, fill=CELL)

    left, right = 110, 1010
    column = right - left
    mark = orb(84, pad=0.0, field=0.0)
    mark.putalpha(rounded_mask((84, 84), 16))
    pv.paste(mark, (left, 96), mark)
    f_name, f_sub, f_head = font("bold", 54), font("light", 21), font("light", 28)
    f_step, f_body, f_foot, f_num = font("bold", 25), font("light", 21), font("light", 19), font("bold", 20)
    d.text((left + 106, 98), "Local AI", font=f_name, fill=INK)
    d.text((left + 110, 162), "for Omarchy", font=f_sub, fill=DIM)

    y = 258
    for line in HEADLINE:
        fitted(line, f_head, column)
        d.text((left, y), line, font=f_head, fill=INK)
        y += 38

    y = 372
    for i, (head, line1, line2) in enumerate(STEPS, 1):
        d.rounded_rectangle([left, y, left + 36, y + 36], radius=6, fill=INK)
        d.text((left + 18, y + 19), str(i), font=f_num, fill=BG, anchor="mm")
        d.text((left + 56, y), head, font=f_step, fill=INK)
        for line in (line1, line2):
            fitted(line, f_body, column - 56)
            d.text((left + 56, y + 36), line, font=f_body, fill=DIM)
            y += 30
        y += 62

    for i, line in enumerate(FOOTER):
        fitted(line, f_foot, column)
        d.text((left, 782 + i * 26), line, font=f_foot, fill=FAINT)

    cx, cy = W - 88 - card.width, (H - card.height) // 2
    glow = Image.new("RGB", (W, H), BG)
    ImageDraw.Draw(glow).rounded_rectangle(
        [cx - 30, cy - 30, cx + card.width + 30, cy + card.height + 30], radius=30, fill=(44, 44, 44)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    pv.paste(Image.blend(pv.crop((cx - 90, cy - 90, cx + card.width + 90, cy + card.height + 90)),
                         glow.crop((cx - 90, cy - 90, cx + card.width + 90, cy + card.height + 90)), 0.5),
             (cx - 90, cy - 90))
    pv.paste(card, (cx, cy))
    d.rounded_rectangle([cx - 1, cy - 1, cx + card.width, cy + card.height], radius=15, outline=FRAME, width=1)

    pv.save(a.out, optimize=True)
    print(f"{a.out}: {pv.size[0]}x{pv.size[1]} from {a.shot} card {card.size[0]}x{card.size[1]}")


if __name__ == "__main__":
    main()