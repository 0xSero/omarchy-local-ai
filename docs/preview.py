#!/usr/bin/env python3
"""Build the marketplace preview (1600x900) from the Local AI banner and live panel captures.

The marketplace renders one image per listing, scaled to 1600 px on the detail page and 720 px on
the browse card, and reads it from `preview.png` in the repository root at the listed commit. This
script composes the dove banner, the supported-hardware facts, and three real panel captures into
that one file. Nothing here runs at plugin runtime.

    python3 docs/preview.py --banner media/banner.png --home home.png --nvidia nvidia.png \\
        --intel intel.png --out preview.png

Every capture must be a full-screen capture of the panel open on the desktop (test/visual captures
one over SSH). The panel is found by its own background colour, so the crop does not depend on the
display resolution. Needs Pillow and numpy.
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1600, 900
BG = (10, 10, 10)
INK = (245, 245, 245)
DIM = (168, 168, 168)
FAINT = (118, 118, 118)
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

HEADLINE = ("Local models on your own GPUs,", "from the Omarchy bar.")
FACTS = (
    ("GPUs", "NVIDIA RTX 30 / 40 / 50, RTX Ada,", "RTX Pro Blackwell, Intel Arc Pro B70"),
    ("Recipes", "67 validated model recipes across", "34 cards, up to 256K context"),
    ("Agents", "claude, codex, pi, omp, opencode,", "crush, grok, copilot, hermes"),
    ("Share", "the same keyed endpoint on your", "tailnet in one click, no root"),
)
CAPTIONS = ("Qwen3.8-27B on 2x RTX 3090", "Qwen3.8-27B on 2x Arc Pro B70")


def font(weight, size):
    for want, path in FONT_CANDIDATES:
        if want == weight and Path(path).expanduser().exists():
            return ImageFont.truetype(str(Path(path).expanduser()), size)
    return ImageFont.load_default(size)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def panel_crop(shot):
    """The panel itself, found by its own background colour.

    The wallpaper is black with white dots, the panel is a solid grey rectangle. A row belongs to
    the panel where an unbroken stretch of grey is at least 300 px wide; the panel's columns are
    the widest such stretch, and its rows are the longest run of rows that keep those columns grey."""
    a = np.array(shot.convert("L")).astype(int)
    interior = (a >= 12) & (a <= 45)
    best = None
    for y in range(0, shot.height, 4):
        hit = np.nonzero(interior[y])[0]
        if not len(hit):
            continue
        for run in np.split(hit, np.nonzero(np.diff(hit) > 1)[0] + 1):
            if len(run) >= 300 and (best is None or len(run) > len(best)):
                best = run
    if best is None:
        sys.exit("no panel found in the capture: is the plugin open?")
    x0, x1 = best.min(), best.max() + 1
    row_hit = np.nonzero(interior[:, x0:x1].mean(axis=1) > 0.6)[0]
    rows = max(np.split(row_hit, np.nonzero(np.diff(row_hit) > 1)[0] + 1), key=len)
    return shot.crop((x0, rows.min(), x1, rows.max() + 1))


def fitted(text, face, limit):
    if face.getlength(text) > limit:
        sys.exit(f"text does not fit at {face.size}px: {text!r}")


def banner_strip(banner, size):
    """The sky fills the strip edge to edge; the wordmark is laid over it at full size, then the
    strip fades into the page below."""
    target_w, target_h = size
    sky_scale = max(target_w / banner.width, target_h / banner.height)
    sky = banner.resize((round(banner.width * sky_scale), round(banner.height * sky_scale)), Image.LANCZOS)
    sky = sky.crop((0, 0, target_w, target_h)).filter(ImageFilter.GaussianBlur(3))
    mark_scale = target_h / (banner.height * 0.30)
    mark = banner.resize((round(banner.width * mark_scale), round(banner.height * mark_scale)), Image.LANCZOS)
    mark = mark.crop((0, round(mark.height * 0.49), mark.width, round(mark.height * 0.49) + target_h))
    mark_fade = Image.new("L", mark.size, 0)
    d = ImageDraw.Draw(mark_fade)
    edge = 120
    for x in range(mark.width):
        alpha = 255
        if x < edge:
            alpha = round(255 * x / edge)
        elif x > mark.width - edge:
            alpha = round(255 * (mark.width - x) / edge)
        d.line([(x, 0), (x, mark.height)], fill=alpha)
    sky.paste(mark, ((target_w - mark.width) // 2, 0), mark_fade)
    fade = Image.new("L", size, 255)
    d = ImageDraw.Draw(fade)
    for y in range(target_h):
        t = y / target_h
        alpha = 255 if t < 0.7 else round(255 * (1 - (t - 0.7) / 0.3) ** 1.4)
        d.line([(0, y), (target_w, y)], fill=alpha)
    return sky, fade


def place_shot(pv, d, shot, box, scale):
    """A panel capture at one shared scale, top-aligned in its box, with the desktop trimmed off."""
    x, y, w, h = box
    im = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    im = im.crop((0, 0, min(im.width, w), min(im.height, h)))
    glow = Image.new("RGB", (im.width + 80, im.height + 80), BG)
    ImageDraw.Draw(glow).rounded_rectangle([20, 20, im.width + 60, im.height + 60], radius=22, fill=(40, 40, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    region = pv.crop((x - 40, y - 40, x + im.width + 40, y + im.height + 40))
    pv.paste(Image.blend(region, glow, 0.6), (x - 40, y - 40))
    im.putalpha(rounded_mask(im.size, 12))
    pv.paste(im, (x, y), im)
    d.rounded_rectangle([x - 1, y - 1, x + im.width, y + im.height], radius=13, outline=FRAME, width=1)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--banner", type=Path, required=True, help="the Local AI dove banner")
    p.add_argument("--nvidia", type=Path, required=True, help="capture of a model card on NVIDIA")
    p.add_argument("--intel", type=Path, required=True, help="capture of a model card on Intel Arc")
    p.add_argument("--out", type=Path, required=True, help="where to write preview.png")
    a = p.parse_args()

    pv = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(pv)
    for y in range(0, H, 22):
        for x in range(0, W, 22):
            d.rounded_rectangle([x + 8, y + 8, x + 13, y + 13], radius=1.5, fill=CELL)

    strip, fade = banner_strip(Image.open(a.banner).convert("RGB"), (W, 250))
    pv.paste(strip, (0, 0), fade)

    left, top = 80, 318
    f_head, f_key, f_val, f_cap = font("bold", 31), font("bold", 20), font("light", 20), font("light", 17)
    column = 620
    y = top
    for line in HEADLINE:
        fitted(line, f_head, column)
        d.text((left, y), line, font=f_head, fill=INK)
        y += 42

    y += 30
    for key, line1, line2 in FACTS:
        d.text((left, y), key, font=f_key, fill=INK)
        for line in (line1, line2):
            fitted(line, f_val, column - 120)
            d.text((left + 120, y), line, font=f_val, fill=DIM)
            y += 29
        y += 22

    shots = (Image.open(a.nvidia).convert("RGB"), Image.open(a.intel).convert("RGB"))
    cards = [panel_crop(shot) for shot in shots]
    gap = 28
    height = H - top - 60
    avail = W - left - (left + column + 60) - gap
    scale = min(height / max(c.height for c in cards), avail / sum(c.width for c in cards))
    widths = [round(c.width * scale) for c in cards]
    x = W - left - sum(widths) - gap
    for card, caption, width in zip(cards, CAPTIONS, widths):
        place_shot(pv, d, card, (x, top, width, height), scale)
        fitted(caption, f_cap, width)
        d.text((x, top + round(card.height * scale) + 14), caption, font=f_cap, fill=FAINT)
        x += width + gap

    pv.save(a.out, optimize=True)
    print(f"{a.out}: {pv.size[0]}x{pv.size[1]}")


if __name__ == "__main__":
    main()
