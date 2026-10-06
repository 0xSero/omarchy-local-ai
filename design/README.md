# The Local AI panel, as a design

Every state the panel can be in, drawn as it should be built: `rows/frame.mjs`. Each screen is the popup (340 px) in
one frame: a header band (tabs, tokens generated, today, the line, the full-screen door) and a footer band (the machine
in one line, logs · refresh) in one surface tone, at fixed heights, so the top and the bottom never move. The
full-screen view is the same frame at 1280 px.

```
make design      # draw every state: design/rows/out/frame (SVG + PNG) and design/screens (the PNGs, tracked)
python3 design/rows/tree.py <blobs.json> <out.dc.html>   # the tree of states and the actions between them
```

- `SPEC.md`: what each part does and why.
- `screens/`: one PNG per state, numbered in the order of the tree; the GitHub issues show these.
- `logos/`: lab and card marks (sources and licences in `logos/README.md`).
- `rows/kit.mjs`: the drawing surface (the panel's tones from `Model.js`, its font, its gutter); `panel.mjs`,
  `fixtures.mjs`, `tokens.json`: the palette, the sample machines and the design tokens it reads.

Values in the drawings (temperatures, speeds, history) are samples.
