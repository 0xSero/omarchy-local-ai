#!/usr/bin/env bash
# bash design/rows/render.sh design/rows/NN-name.mjs
# Draws the row (render.mjs), rasterises each screen at 2x in the bar's Nerd Font, and writes one strip,
# design/rows/out/<id>/strip.png, every screen side by side: that is the image to look at.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$HOME/.local/share/mise/installs/node/26.7.0/bin:$PATH"
row=$1
id=$(perl -e 'alarm 60; exec @ARGV' node -e 'import(require("url").pathToFileURL(require("path").resolve(process.argv[1])).href).then(m=>console.log(m.ROW.id))' "$row")
out="$here/out/$id"
perl -e 'alarm 60; exec @ARGV' node "$here/render.mjs" "$row" "$out"
tmp=$(mktemp -t rowsvg)
for f in "$out"/*.svg; do
  sed 's/font-family="[^"]*"/font-family="CaskaydiaMono Nerd Font"/' "$f" >"$tmp"
  rsvg-convert -z 2 "$tmp" -o "${f%.svg}.png"
done
/bin/rm -f "$tmp"
python3 -I - "$out" <<'PY'
import sys, glob
from PIL import Image
d = sys.argv[1]
ims = [Image.open(p) for p in sorted(glob.glob(d + "/[0-9]*.png"))]
gap = 40
strip = Image.new("RGB", (sum(i.width for i in ims) + gap * (len(ims) + 1), max(i.height for i in ims) + 2 * gap), (60, 60, 66))
x = gap
for i in ims:
    strip.paste(i, (x, gap)); x += i.width + gap
strip.save(d + "/strip.png")
print(d + "/strip.png", strip.size)
PY
