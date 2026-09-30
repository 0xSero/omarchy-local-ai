#!/usr/bin/env python3
"""Render preview.png, the marketplace listing image: Local AI in the middle, the logo of every coding agent it opens
scattered around it, the GPU makers whose cards it runs models on, and an orange line from each to Local AI.
No display and no live machine needed.

  docs/preview/build.py [OUT.png]     render (default: preview.png at the repository root)

The agents come from AGENTS=(...) in bin/omarchy-local-ai. A new agent needs a display name, a logo and a spot in AGENT_SPOTS below and
in docs/preview/logos/, and a spot on the canvas (the build stops until it has all three). The image carries no version and no count, so a release
cannot make it wrong.

Needs: python3; a Chromium-family browser (BROWSER=..., PREVIEW_PROFILE=... to reuse a profile);
JetBrainsMono Nerd Font, which Omarchy ships (FONT_DIR=... for a directory holding the Regular and Bold TTFs).
"""
import math, os, pathlib, re, shutil, signal, struct, subprocess, sys, tempfile, time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
W, H = 1600, 900

# how the README and the panel write each agent, and its logo in docs/preview/logos/ (sources and licences: logos/README.md)
LOGOS = {"pi": ("pi", "pi.svg"), "claude": ("Claude Code", "claude-code.svg"), "codex": ("Codex", "codex.svg"),
         "opencode": ("OpenCode", "opencode.svg"), "omp": ("omp", "omp.svg"), "crush": ("Crush", "crush.png"),
         "grok": ("Grok", "grok.svg"), "copilot": ("Copilot", "copilot.svg"), "hermes": ("Hermes", "hermes.svg")}

# where things sit on the 1600x900 canvas (circle centres); check_geometry stops the build if two touch or a line runs through one
HUB, HUB_R = (780, 470), 132
AGENT_R, MAKER_R = 54, 100
AGENT_SPOTS = {"claude": (980, 153), "codex": (543, 268), "opencode": (264, 248), "grok": (684, 723), "copilot": (280, 745),
               "pi": (715, 180), "omp": (139, 682), "crush": (124, 379), "hermes": (1000, 686)}
MAKERS = [("nvidia.svg", 1262, 196), ("intel.svg", 1430, 460), ("amd.svg", 1240, 710)]
LEFT, TOP, RIGHT, BOTTOM = 64, 64, 1536, 836
ACCENT = "#ff5a36"


def fail(message):
    sys.exit(f"preview: {message}")


def which_any(names, apps=()):
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    for app in apps:
        if pathlib.Path(app).exists():
            return app
    return None


def find_tools():
    browser = os.environ.get("BROWSER") or which_any(
        ["chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "brave", "brave-browser", "microsoft-edge"],
        ["/Applications/Brave Browser.app/Contents/MacOS/Brave Browser", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"],
    )
    fonts = os.environ.get("FONT_DIR")
    if not fonts:
        home = pathlib.Path.home()
        for base in ["/usr/share/fonts", home / ".local/share/fonts", home / "Library/Fonts", "/Library/Fonts"]:
            base = pathlib.Path(base)
            hit = next(base.rglob("JetBrainsMonoNerdFont-Regular.ttf"), None) if base.is_dir() else None
            if hit:
                fonts = str(hit.parent)
                break
    for what, value, hint in [("a Chromium-family browser", browser, "BROWSER="), ("JetBrainsMono Nerd Font", fonts, "FONT_DIR=")]:
        if not value:
            fail(f"{what} not found; set {hint}")
    for face in ("Regular", "Bold"):
        if not (pathlib.Path(fonts) / f"JetBrainsMonoNerdFont-{face}.ttf").is_file():
            fail(f"{fonts} has no JetBrainsMonoNerdFont-{face}.ttf")
    return browser, str(pathlib.Path(fonts).resolve())


def browse(browser, args, stdout=subprocess.DEVNULL):
    """Run the browser headless in a private profile so it never attaches to a browser you are using.
    PREVIEW_PROFILE=<dir> keeps one profile between runs (a first run on a brand-new Brave profile can stall on macOS)."""
    kept = os.environ.get("PREVIEW_PROFILE")
    profile = kept or tempfile.mkdtemp(prefix="local-ai-preview-profile-")
    cmd = [browser, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1", "--no-first-run",
           "--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-extensions",
           "--no-default-browser-check", "--use-mock-keychain", "--password-store=basic",
           f"--user-data-dir={profile}", "--allow-file-access-from-files", *args]
    proc = subprocess.Popen(cmd, stdout=stdout, stderr=subprocess.DEVNULL, process_group=0)
    return proc, (None if kept else profile)


def stop(proc, profile):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
    if profile:
        shutil.rmtree(profile, ignore_errors=True)


def screenshot(browser, page, out):
    out.unlink(missing_ok=True)
    proc, profile = browse(browser, [f"--window-size={W},{H}", f"--screenshot={out}", page.as_uri()])
    try:
        deadline, last = time.time() + 120, -1
        while time.time() < deadline:  # the browser may linger after writing the file: wait for it to settle, then stop it
            size = out.stat().st_size if out.exists() else 0
            if size and size == last:
                return
            last = size
            time.sleep(1)
        fail("the browser wrote no screenshot")
    finally:
        stop(proc, profile)


def layout_check(browser, page):
    # --dump-dom prints the page and then the browser lingers: read the file until the document ends, then stop it
    with tempfile.TemporaryFile() as dom:
        proc, profile = browse(browser, ["--virtual-time-budget=3000", "--dump-dom", page.as_uri()], stdout=dom)
        try:
            text, deadline = "", time.time() + 90
            while time.time() < deadline and "</html>" not in text:
                time.sleep(0.5)
                dom.seek(0)
                text = dom.read().decode("utf-8", "replace")
        finally:
            stop(proc, profile)
    hit = re.search(r'data-check="([^"]*)"', text)
    return hit.group(1) if hit else "no result"


def agents():
    text = (ROOT / "bin" / "omarchy-local-ai").read_text()
    hit = re.search(r"^AGENTS=\(([^)]*)\)", text, re.M)
    if not hit:
        fail("bin/omarchy-local-ai has no AGENTS=(...) list")
    ids = hit.group(1).split()
    unknown = [a for a in ids if a not in LOGOS or a not in AGENT_SPOTS]
    if unknown:
        fail(f"no name, logo and spot for {', '.join(unknown)}; add them to LOGOS and AGENT_SPOTS in docs/preview/build.py and the logo to docs/preview/logos/")
    return [(*LOGOS[a], *AGENT_SPOTS[a]) for a in ids]


def logo(name, logo_dir):
    """A logo as HTML. SVGs are inlined without their own size or colour so the page sets both; the PNG is an image."""
    path = logo_dir / name
    if not path.is_file():
        fail(f"missing logo {path}")
    if path.suffix == ".png":
        return f'<span class="logo"><img src="{path.as_uri()}" alt=""></span>'
    text = re.sub(r"<title>.*?</title>", "", path.read_text(), flags=re.S)
    root = re.search(r"<svg[^>]*>", text)
    if not root:
        fail(f"{path} is not an SVG")
    text = text[root.start():]  # no XML prolog or doctype inside an HTML page
    fresh = re.sub(r'\s(?:width|height|role)="[^"]*"', "", root.group(0))
    fresh = re.sub(r'\sstyle="(?![^"]*fill-rule)[^"]*"', "", fresh)  # keep a style that carries fill-rule, drop the rest
    if " fill=" not in fresh:
        fresh = fresh.replace("<svg", '<svg fill="currentColor"', 1)
    text = text.replace(root.group(0), fresh, 1)
    text = re.sub(r"fill:\s*(?:black|#000(?:000)?|rgb\([^)]*\))", "fill:currentColor", text)  # a logo that paints itself black would vanish on the dark disc
    return f'<span class="logo">{text}</span>'


def check_geometry(circles):
    """circles: (name, cx, cy, r, label_rect). Stop when two circles touch, a line to Local AI crosses another circle,
    or anything leaves the canvas."""
    hx, hy = HUB
    for name, cx, cy, r, label in circles:
        rects = [(cx - r, cy - r, cx + r, cy + r)] + ([label] if label else [])
        for x0, y0, x1, y1 in rects:
            if x0 < LEFT or y0 < TOP or x1 > RIGHT or y1 > BOTTOM:
                fail(f"{name} leaves the canvas ({x0:.0f},{y0:.0f},{x1:.0f},{y1:.0f})")
        if math.hypot(cx - hx, cy - hy) < HUB_R + r + 60:
            fail(f"{name} sits too close to Local AI")
    for i, (a, ax, ay, ar, alabel) in enumerate(circles):
        for b, bx, by, br, blabel in circles[i + 1:]:
            if math.hypot(ax - bx, ay - by) < ar + br + 36:
                fail(f"{a} and {b} are too close")
        for b, bx, by, br, blabel in circles:
            if b == a:
                continue
            # distance from b's centre to the segment a -> hub
            dx, dy = hx - ax, hy - ay
            t = max(0, min(1, ((bx - ax) * dx + (by - ay) * dy) / (dx * dx + dy * dy)))
            if math.hypot(ax + t * dx - bx, ay + t * dy - by) < br + 14:
                fail(f"the line from {a} to Local AI runs through {b}")
            if blabel:
                x0, y0, x1, y1 = blabel
                for k in range(21):
                    px, py = ax + dx * k / 20, ay + dy * k / 20
                    if x0 - 6 < px < x1 + 6 and y0 - 6 < py < y1 + 6:
                        fail(f"the line from {a} to Local AI runs through the name of {b}")


def diagram(items):
    """The circles, the names and the lines, as HTML and SVG."""
    logo_dir = HERE / "logos"
    hx, hy = HUB
    circles, html, lines = [], [], []

    def spoke(cx, cy, r, width):
        d = math.hypot(hx - cx, hy - cy)
        ux, uy = (hx - cx) / d, (hy - cy) / d
        x1, y1, x2, y2 = cx + ux * r, cy + uy * r, hx - ux * HUB_R, hy - uy * HUB_R
        lines.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{ACCENT}" stroke-width="{width}" stroke-opacity="{1 if width > 2 else .7}"/>')
        lines.append(f'<circle cx="{x2:.1f}" cy="{y2:.1f}" r="5" fill="{ACCENT}"/>')

    for name, file, cx, cy in items:
        above = cy < hy - 40  # the name goes on the side away from Local AI, so no line crosses it
        label_w = max(80, round(len(name) * 13.6 + 16))
        top = cy - AGENT_R - 34 if above else cy + AGENT_R + 6
        label = (cx - label_w / 2, top, cx + label_w / 2, top + 28)
        circles.append((name, cx, cy, AGENT_R, label))
        html.append(f'<div class="box agent" style="left:{cx - AGENT_R}px;top:{cy - AGENT_R}px;width:{2 * AGENT_R}px;height:{2 * AGENT_R}px">{logo(file, logo_dir)}</div>'
                    f'<div class="box name fit" style="left:{label[0]:.0f}px;top:{top:.0f}px;width:{label_w}px;height:28px">{name}</div>')
        spoke(cx, cy, AGENT_R, 2)
    for file, cx, cy in MAKERS:
        circles.append((file, cx, cy, MAKER_R, None))
        html.append(f'<div class="box maker" style="left:{cx - MAKER_R}px;top:{cy - MAKER_R}px;width:{2 * MAKER_R}px;height:{2 * MAKER_R}px">{logo(file, logo_dir)}</div>')
        spoke(cx, cy, MAKER_R, 3)
    check_geometry(circles)

    halo = f'<circle cx="{hx}" cy="{hy}" r="{HUB_R + 26}" fill="none" stroke="{ACCENT}" stroke-opacity=".35" stroke-width="2"/>'
    hub = (f'<div class="box hub fit" style="left:{hx - HUB_R}px;top:{hy - HUB_R}px;width:{2 * HUB_R}px;height:{2 * HUB_R}px">'
           '<div class="big">Local AI</div><div class="ip">127.0.0.1</div><div class="sub">keyed gateway</div></div>')
    return "".join(html) + hub, halo + "".join(lines)


def render(out):
    browser, fonts = find_tools()
    nodes, lines = diagram(agents())
    with tempfile.TemporaryDirectory(prefix="local-ai-preview-") as tmp:
        page = pathlib.Path(tmp) / "preview.html"
        page.write_text((HERE / "preview.html").read_text()
                        .replace("{{FONT_DIR}}", fonts).replace("{{NODES}}", nodes).replace("{{LINES}}", lines)
                        .replace("{{EYEBROW_LOGO}}", logo("omarchy.svg", HERE / "logos")))
        screenshot(browser, page, out)
        verdict = layout_check(browser, page)
    if verdict != "OK":
        fail(f"layout check: {verdict}")
    with open(out, "rb") as f:
        head = f.read(24)
    width, height = struct.unpack(">II", head[16:24])
    if head[:8] != b"\x89PNG\r\n\x1a\n" or (width, height) != (W, H):
        fail(f"{out} is not a {W}x{H} PNG ({width}x{height})")
    print(f"preview: {out} {width}x{height}, layout OK")


if __name__ == "__main__":
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    render(pathlib.Path(sys.argv[1] if len(sys.argv) == 2 else ROOT / "preview.png").resolve())
