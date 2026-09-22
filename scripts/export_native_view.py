#!/usr/bin/env python3
"""Generate Omarchy's native Local AI view from this plugin's own UI.

The native view is this plugin's card drawn inside Omarchy's own Agents panel: it
uses the same row data (`ui/ui.js`), the same row component (`ui/CardRow.qml`) and
the same token bars (`ui/TokenTotal.qml`), and adds only the one thing that is
native to it — resolving the installed plugin's controller (`backendCommand`).

Those three files are therefore copies, and a copy that is edited by hand is a copy
that drifts. This script writes them from the source, so a card change is made once
here and published with one command:

    python3 scripts/export_native_view.py --omarchy ~/omarchy
    python3 scripts/export_native_view.py --omarchy ~/omarchy --check

`--check` writes nothing and exits non-zero when the copy has drifted, which is
what CI runs. The two files that are genuinely native — `LocalAi.qml` (the view
inside the Agents panel) and `manifest.json` — are not generated and not touched.
"""

import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENTS = pathlib.Path("shell/plugins/agents")

# name in Omarchy's tree -> (source here, rewrites, native-only tail)
SHARED = {
    "LocalAi.js": ("ui/ui.js", (("; Panel.qml only draws", "; LocalAi.qml only draws"),), "native/backend-command.js"),
    "LocalAiRow.qml": ("ui/CardRow.qml", (("TokenTotal {", "LocalAiTotal {"),), None),
    "LocalAiTotal.qml": ("ui/TokenTotal.qml", (('import "ui.js" as Ui', 'import "LocalAi.js" as Ui'),), None),
}


def render() -> dict:
    """Return the generated file name -> contents, in a stable order."""
    out = {}
    for name, (source, rewrites, tail) in SHARED.items():
        text = (ROOT / source).read_text()
        for old, new in rewrites:
            if old not in text:
                raise SystemExit(f"export: {source} no longer contains {old!r}")
            text = text.replace(old, new, 1)
        if tail:
            text += (ROOT / tail).read_text()
        out[name] = text
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--omarchy", required=True, help="path to an Omarchy checkout with shell/plugins/agents")
    parser.add_argument("--check", action="store_true", help="verify the copy instead of writing it")
    args = parser.parse_args()

    target = pathlib.Path(args.omarchy).expanduser() / AGENTS
    if not target.is_dir():
        raise SystemExit(f"export: {target} is not a directory; point --omarchy at an Omarchy checkout")

    files = render()
    stale = []
    for name, text in files.items():
        path = target / name
        current = path.read_text() if path.is_file() else None
        if current == text:
            print(f"export: {name} is current")
            continue
        if args.check:
            stale.append(name)
            print(f"export: {name} has drifted", file=sys.stderr)
            continue
        path.write_text(text)
        print(f"export: {name} written")
    if stale:
        print(f"export: {len(stale)} file(s) drifted; run this without --check and commit the result", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
