"""Logo and marketplace preview for Local AI. Monochrome, pixel field with a lit circle: the card's own orb."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np

S = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1]
BG = (10, 10, 10)
INK = (245, 245, 245)
DIM = (150, 150, 150)
MONO_B = "/Users/sero/Library/Fonts/CaskaydiaMonoNerdFont-Bold.ttf"
MONO = "/Users/sero/Library/Fonts/CaskaydiaMonoNerdFont-Light.ttf"
if not os.path.exists(MONO_B):
    MONO_B = MONO = "/System/Library/Fonts/Menlo.ttc"


def orb(size, cells=15, bg=BG, pad=0.08, field=0.08):
    """The card's orb: a square field of rounded pixels, a circle lit inside, brightest at the centre."""
    im = Image.new("RGBA", (size, size), bg + (255,))
    d = ImageDraw.Draw(im)
    inner = size * (1 - 2 * pad)
    px = inner / cells
    gap = px * 0.28
    off = size * pad
    half = cells / 2
    radius = half * 0.86
    for row in range(cells):
        for col in range(cells):
            dx, dy = col + 0.5 - half, row + 0.5 - half
            dist = math.hypot(dx, dy)
            if dist > radius + 0.5:
                a = field
            else:
                glow = 1 - (dist / (radius + 0.5)) ** 2 * 0.55
                a = 0.92 * glow
                if dist > radius - 0.5:
                    a *= 0.5 + 0.5 * (radius + 0.5 - dist)
                a = max(a, field)
            x, y = off + col * px + gap / 2, off + row * px + gap / 2
            side = px - gap
            c = tuple(int(bg[i] + (INK[i] - bg[i]) * a) for i in range(3))
            d.rounded_rectangle([x, y, x + side, y + side], radius=side * 0.28, fill=c + (255,))
    return im


def rounded_mask(size, r):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return m


# ---------------------------------------------------------------- logo: 1024 px, rounded square
logo = orb(1024, cells=15)
logo.putalpha(rounded_mask(1024, 180))
logo.save(f"{OUT}/logo.png")
logo.resize((256, 256), Image.LANCZOS).save(f"{OUT}/logo-256.png")

# ---------------------------------------------------------------- the card, cropped from the live capture
hero = Image.open(f"{S}/card-hero.png").convert("RGB")
a = np.array(hero.convert("L"))
# the card's frame is a mid-grey 1px line (the wallpaper dots above it are white): find rows and columns
# on the right third of the screen that are long runs of frame-grey
g = (a > 70) & (a < 200)
W0 = 1280
row_runs = [(y, g[y, W0:].sum()) for y in range(300, 1079)]
frame_rows = [y for y, n in row_runs if n > 200]
y0, y1 = frame_rows[0], frame_rows[-1]
col_runs = [(x, g[y0:y1, x].sum()) for x in range(W0, 1920)]
frame_cols = [x for x, n in col_runs if n > (y1 - y0) * 0.8]
x0, x1 = frame_cols[0], frame_cols[-1]
card = hero.crop((x0 - 2, y0 - 2, x1 + 4, y1 + 4))
card.save(f"{OUT}/card-crop.png")

# ---------------------------------------------------------------- preview: 1600 x 900
W, H = 1600, 900
pv = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(pv)
# a faint pixel field across the whole canvas, like the card's own backdrop
for y in range(0, H, 22):
    for x in range(0, W, 22):
        d.rounded_rectangle([x + 8, y + 8, x + 13, y + 13], radius=1.5, fill=(22, 22, 22))

# left column: mark, wordmark, tagline, features
mark = orb(150, cells=15, pad=0.0, field=0.0)
mark.putalpha(rounded_mask(150, 28))
pv.paste(mark, (96, 96), mark)
f_title = ImageFont.truetype(MONO_B, 74)
f_sub = ImageFont.truetype(MONO, 27)
f_feat = ImageFont.truetype(MONO, 25)
f_small = ImageFont.truetype(MONO, 20)
d.text((272, 104), "Local AI", font=f_title, fill=INK)
d.text((276, 192), "for Omarchy", font=f_sub, fill=DIM)

d.text((96, 300), "The model validated for your GPU,\none button on the bar.", font=f_sub, fill=INK, spacing=10)
feats = [
    "Start downloads it, proves it works, serves it",
    "Open any coding agent on it: claude, codex, pi…",
    "Share on your tailnet, keyed, in one click",
    "Every detected GPU listed; pick the one you want",
    "Docker containers only this plugin touches",
]
y = 420
for t in feats:
    d.rounded_rectangle([98, y + 9, 108, y + 19], radius=2, fill=INK)
    d.text((126, y), t, font=f_feat, fill=INK)
    y += 48
d.text((96, 800), "34 validated GPU recipes · NVIDIA and Intel Arc · verified listing", font=f_small, fill=DIM)

# right: the card, scaled, with a soft glow behind it
cw, ch = card.size
scale = 600 / ch
card_s = card.resize((int(cw * scale), 600), Image.LANCZOS)
cx = W - card_s.width - 96
cy = (H - card_s.height) // 2
glow = Image.new("RGB", (W, H), BG)
ImageDraw.Draw(glow).rounded_rectangle([cx - 30, cy - 30, cx + card_s.width + 30, cy + card_s.height + 30], radius=30, fill=(40, 40, 40))
glow = glow.filter(ImageFilter.GaussianBlur(40))
pv = Image.composite(glow, pv, Image.new("L", (W, H), 255)) if False else pv
pv.paste(Image.blend(pv.crop((0, 0, W, H)), glow, 0.5).crop((cx - 90, cy - 90, cx + card_s.width + 90, cy + card_s.height + 90)), (cx - 90, cy - 90))
pv.paste(card_s, (cx, cy))
pv.save(f"{OUT}/preview.png", optimize=True)
print("logo", logo.size, "card", card.size, "preview", pv.size)
