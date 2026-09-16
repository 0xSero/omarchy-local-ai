#!/usr/bin/env python3
"""Render the wiki pages into one self-contained HTML file.

    python3 wiki/build.py            # writes wiki/index.html

Reads every wiki/*.md in the order below, converts with python-markdown, and writes a single
index.html: sidebar navigation, hash routing, one section per page. Links between pages
(`03-recipes.md`) are rewritten to `#03-recipes`. No network is needed to read the result; mermaid
is loaded from a CDN only for the pages that contain a diagram, and the diagram source stays
readable if it never loads.
"""
from pathlib import Path
import html
import re
import sys

import markdown

HERE = Path(__file__).resolve().parent
OUT = HERE / "index.html"

ORDER = [
    "README.md",
    "01-architecture.md",
    "02-install-and-layout.md",
    "03-recipes.md",
    "04-state.md",
    "05-start-path.md",
    "06-weights.md",
    "07-containers.md",
    "08-acceptance.md",
    "09-agents.md",
    "10-sharing.md",
    "11-panel.md",
    "12-cli.md",
    "13-tests.md",
    "14-troubleshooting.md",
    "15-registry-and-ci.md",
    "16-history.md",
]

CSS = """
:root {
  --bg: #121212; --panel: #1a1a1a; --line: #2e2e2e; --ink: #f5f5f5; --fg: #bebebe;
  --dim: #8a8a8d; --faint: #555; --urgent: #D35F5F; --accent: #e68e0d; --fill: rgba(255,255,255,.04);
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg);
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: 15px; line-height: 1.65; }
#shell { display: flex; min-height: 100vh; }
#side { width: 300px; flex: 0 0 300px; background: var(--panel); border-right: 1px solid var(--line);
  position: sticky; top: 0; height: 100vh; overflow-y: auto; padding: 20px 0 40px; }
#side h1 { font-size: 15px; color: var(--ink); margin: 0 20px 2px; letter-spacing: -.2px; }
#side .sub { margin: 0 20px 16px; color: var(--faint); font-size: 12px; }
#filter { margin: 0 16px 14px; width: calc(100% - 32px); background: var(--fill); color: var(--ink);
  border: 1px solid var(--line); border-radius: 2px; padding: 7px 9px; font: inherit; font-size: 12px; }
#filter:focus { outline: none; border-color: var(--faint); }
#toc a { display: block; color: var(--dim); text-decoration: none; padding: 7px 20px 7px 20px; font-size: 12.5px;
  border-left: 2px solid transparent; }
#toc a:hover { background: var(--fill); color: var(--ink); }
#toc a.on { color: var(--ink); border-left-color: var(--accent); background: var(--fill); }
#toc a .n { color: var(--faint); display: inline-block; min-width: 22px; }
#main { flex: 1 1 auto; min-width: 0; padding: 34px 46px 90px; max-width: 1080px; }
section.page { display: none; }
section.page.on { display: block; }
h1, h2, h3, h4 { color: var(--ink); font-weight: 700; letter-spacing: -.2px; }
h1 { font-size: 25px; margin: 0 0 18px; }
h2 { font-size: 18px; margin: 34px 0 10px; padding-top: 10px; border-top: 1px solid var(--line); }
h3 { font-size: 15px; margin: 24px 0 8px; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
p { margin: 10px 0; }
ul, ol { padding-left: 22px; }
li { margin: 4px 0; }
code { background: var(--fill); padding: 1px 5px; border-radius: 2px; font-size: .93em; color: var(--ink); }
pre { background: var(--panel); border: 1px solid var(--line); border-radius: 3px; padding: 13px 15px;
  overflow-x: auto; }
pre code { background: none; padding: 0; color: var(--fg); font-size: 12.7px; line-height: 1.55; }
table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 13px; display: block; overflow-x: auto; }
th, td { border: 1px solid var(--line); padding: 7px 10px; text-align: left; vertical-align: top; }
th { background: var(--fill); color: var(--ink); font-weight: 700; white-space: nowrap; }
tr:nth-child(even) td { background: rgba(255,255,255,.015); }
blockquote { margin: 12px 0; padding: 2px 14px; border-left: 2px solid var(--faint); color: var(--dim); }
hr { border: 0; border-top: 1px solid var(--line); margin: 28px 0; }
.mermaid { background: var(--panel); border: 1px solid var(--line); border-radius: 3px; padding: 14px; margin: 14px 0; overflow-x: auto; }
.mermaid svg { max-width: none; height: auto; }
.hint { color: var(--faint); font-size: 12px; margin-top: 46px; border-top: 1px solid var(--line); padding-top: 12px; }
@media (max-width: 900px) { #shell { display: block; } #side { position: static; width: 100%; height: auto; }
  #main { padding: 20px; } }
"""

JS = """
const pages = Array.from(document.querySelectorAll('section.page'));
const links = Array.from(document.querySelectorAll('#toc a'));
// diagrams are drawn when their page becomes visible: a hidden element gives mermaid nothing to size
function drawMermaid() {
  if (!window.mermaid) return;
  const on = document.querySelector('section.page.on');
  if (!on) return;
  const nodes = Array.from(on.querySelectorAll('.mermaid:not([data-processed])'));
  if (nodes.length) { try { window.mermaid.run({ nodes }); } catch (e) {} }
}
window.__drawMermaid = drawMermaid;
function show(id) {
  if (!id) id = 'README';
  let hit = false;
  pages.forEach(p => { const on = p.id === id; p.classList.toggle('on', on); if (on) hit = true; });
  if (!hit) { pages[0].classList.add('on'); id = pages[0].id; }
  links.forEach(a => a.classList.toggle('on', a.getAttribute('href') === '#' + id));
  window.scrollTo(0, 0);
  drawMermaid();
}
function go() { show(decodeURIComponent(location.hash.replace(/^#/, ''))); }
window.addEventListener('hashchange', go);
document.getElementById('filter').addEventListener('input', e => {
  const q = e.target.value.toLowerCase();
  links.forEach(a => { a.style.display = a.textContent.toLowerCase().includes(q) ? 'block' : 'none'; });
});
go();
"""


def convert(text: str) -> str:
    md = markdown.Markdown(
        extensions=["tables", "fenced_code", "toc", "sane_lists", "attr_list", "md_in_html", "def_list"],
        extension_configs={"toc": {"permalink": False}},
    )
    body = md.convert(text)
    # fenced mermaid → a div mermaid understands. python-markdown escapes a fenced block
    # (`-->` becomes `--&gt;`), so the body must be unescaped exactly once: mermaid reads the
    # element's text and needs the original source back, entities and all.
    body = re.sub(
        r'<pre><code class="language-mermaid">(.*?)</code></pre>',
        lambda m: '<div class="mermaid">' + html.unescape(m.group(1)) + "</div>",
        body,
        flags=re.S,
    )
    # links between pages
    body = re.sub(r'href="(\d\d-[a-z0-9-]+|README)\.md"', r'href="#\1"', body)
    return body


def title_of(text: str, fallback: str) -> str:
    m = re.search(r"^#\s+(.*)$", text, flags=re.M)
    return m.group(1).strip() if m else fallback


def main() -> int:
    missing = [p for p in ORDER if not (HERE / p).exists()]
    if missing:
        print("missing pages: " + ", ".join(missing), file=sys.stderr)
        return 1
    extra = sorted(p.name for p in HERE.glob("*.md") if p.name not in ORDER)
    if extra:
        print("warning: not in ORDER, not rendered: " + ", ".join(extra), file=sys.stderr)

    nav, sections = [], []
    for i, name in enumerate(ORDER):
        text = (HERE / name).read_text(encoding="utf-8")
        pid = name[:-3]
        label = title_of(text, pid)
        # the sidebar reads as a table of contents, not as repeated titles
        label = re.sub(r"^\d+\s+—\s+", "", label)
        nav.append(
            f'<a href="#{pid}"><span class="n">{"" if i == 0 else pid.split("-")[0]}</span>'
            f"{html.escape(label)}</a>"
        )
        sections.append(f'<section class="page" id="{pid}">{convert(text)}</section>')

    OUT.write_text(
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>omarchy-local-ai — wiki</title>\n"
        f"<style>{CSS}</style>\n</head>\n<body>\n<div id=\"shell\">\n<aside id=\"side\">\n"
        "<h1>omarchy-local-ai</h1>\n<p class=\"sub\">the plugin, page by page</p>\n"
        "<input id=\"filter\" placeholder=\"filter pages\" autocomplete=\"off\">\n"
        f"<nav id=\"toc\">{''.join(nav)}</nav>\n</aside>\n<main id=\"main\">{''.join(sections)}"
        "<p class=\"hint\">Generated by <code>wiki/build.py</code> from the markdown pages beside it. "
        "The source is the authority: when this page and the code disagree, the code is right.</p>"
        "</main>\n</div>\n"
        "<script type=\"module\">\n"
        "const s = document.createElement('script');\n"
        "s.src = 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js';\n"
        "s.onload = () => { try { mermaid.initialize({ startOnLoad: false, theme: 'dark',"
        " themeVariables: { background: '#1a1a1a', primaryColor: '#1a1a1a', primaryTextColor: '#f5f5f5',"
        " primaryBorderColor: '#2e2e2e', lineColor: '#8a8a8d', fontFamily: 'monospace' } });"
        " window.mermaid = mermaid; window.__drawMermaid && window.__drawMermaid(); }"
        " catch (e) {} };\n"
        "document.head.appendChild(s);\n"
        f"</script>\n<script>{JS}</script>\n</body>\n</html>\n",
        encoding="utf-8",
    )
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {len(ORDER)} pages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())