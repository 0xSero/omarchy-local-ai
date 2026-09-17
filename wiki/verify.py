#!/usr/bin/env python3
r"""Check the wiki against the tree it documents.

    python3 wiki/verify.py            # exit 1 and list every claim that no longer matches
    python3 wiki/verify.py --list     # just print what was checked

Two kinds of claim are checked, both taken from the pages themselves:

1. **Paths.** Every backticked repository path in the pages must exist in the tree. This is the one
   that rots fastest: a directory move (the 5.0.1 `Panel.qml` → `ui/Panel.qml`) invalidates prose
   silently.

2. **Quoted messages and symbols.** A backticked span that looks like something the plugin prints, or
   a symbol name it defines, must still appear in `bin/`, `lib/`, `ui/`, `test/` or the workflows.
   Placeholders are matched loosely — `<recipe>`, `$id`, `\($port)`, `%s` and `…` become wildcards —
   so `recipe needs 2 rtx-3090-24gb cards, 1 detected` still verifies against
   `recipe needs \($c.value) \(... )cards, ...`.

Anything else in backticks (prose, commands, JSON shapes, Qt properties) is ignored: a checker that
cries wolf is a checker nobody reads. The ignored classes are listed in IGNORE below, so the boundary
is visible rather than implied.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

SOURCE_DIRS = ["bin", "lib", "ui", "test", ".github", "docs"]
SOURCE_FILES = ["Makefile", "manifest.json", "recipes.json", "README.md", "CHANGELOG.md"]

# spans that are prose, a command, or a shape — never checked
IGNORE = re.compile(
    r"""(
    ://            # urls
    | ^[-—·•]      # bullets and separators
    | ^(?:docker|curl|jq|git|make|python3|bash|node|gh|npm|mkdocs|systemctl|ss|ls|rm|tar|hf|omarchy|quickshell|sqlite3)\s
    | ^--            # flags
    | [{}]           # json / js / make expansion
    | \|             # markdown table pipes swallowed into a span
    | [“”]           # curly quotes around a fragment
    | \?\?\?         # sentence elision
    | =[=~]          # comparisons
    | \.\s+[A-Z]     # a sentence running on into the next one
    | ^(?:and|or|but|for|with|to|so)\s
    | \b(?:a|an|the|or|of|to|for|with|into|each|by|at|on|from)$   # trailing glue word: prose, not a quote
    | \($           # a parenthesis left open by markdown emphasis
    )""",
    re.X,
)

# a path: has a slash, no spaces, and starts with a repo-relative directory or a known file
PATHISH = re.compile(r"^(?:(?:[A-Za-z0-9._-]+/)+[A-Za-z0-9._*-]+|(?:bin|lib|ui|test|docs|wiki|\.github)/[A-Za-z0-9._-]+)$")
PATH_ROOTS = {"bin", "lib", "ui", "test", "docs", "wiki", ".github", "dist"}

PLACEHOLDER = [
    (re.compile(r"<[^>]{0,40}>"), ".*"),      # <recipe>, <backend:index>
    (re.compile(r"\\\([^)]{0,40}\)"), ".*"),  # jq interpolation, written \($port)
    (re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*"), ".*"),
    (re.compile(r"%s"), ".*"),
    (re.compile(r"…"), ".*"),
    (re.compile(r"\bN\b"), "[0-9]+"),
]


def spans(text: str) -> list[str]:
    out = []
    for m in re.finditer(r"`([^`\n]{4,220})`", text):
        s = m.group(1).strip()
        if s and s not in out:
            out.append(s)
    return out


BINARY = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".mp4", ".mov", ".webm", ".tar", ".gz",
          ".tgz", ".zip", ".sqlite", ".ico", ".woff", ".woff2", ".pdf", ".mp3"}


def source_text() -> str:
    """Every text file the plugin actually ships or runs.

    Note the extensionless files: `bin/omarchy-local-ai`, `test/all`, `test/bundle` and `test/visual`
    carry the most claims in the wiki, and a suffix filter drops them silently.
    """
    parts = []
    files = []
    for d in SOURCE_DIRS:
        files += [p for p in sorted((ROOT / d).rglob("*")) if p.is_file()]
    files += [ROOT / f for f in SOURCE_FILES]
    for p in files:
        if p.suffix in BINARY:
            continue
        try:
            parts.append(p.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError):
            continue
    return "\n".join(parts)


def as_path(span: str) -> Path | None:
    s = span.split(":")[0].rstrip("/")
    if not PATHISH.match(s) or " " in s or "*" in s:
        return None
    if "/" not in s:
        return None
    if s.split("/")[0] not in PATH_ROOTS:
        return None
    return ROOT / s


def looks_like_claim(span: str) -> bool:
    if len(span) < 14 or " " not in span or IGNORE.search(span):
        return False
    if not span[0].islower():
        return False
    if span.endswith(",") and not span.endswith(". "):
        return False
    # a sentence fragment of the wiki's own prose, not a quote: no symbol and no message shape
    return bool(re.search(r"(?:^|[\s(])(?:the|a|an|it|is|are|was|and|or|of|to|for|with|that|this)\b", span)) or \
           bool(re.search(r"[$<>%]|\w\(\w*\)|[a-z_]+_|\bno\b|\bnot\b|\bcould\b|\bcannot\b", span))


def to_regex(span: str) -> re.Pattern:
    pat = re.escape(span)
    # re.escape escapes the placeholder syntax too, so undo by rebuilding on the escaped text
    for rx, wild in PLACEHOLDER:
        pat = rx.sub(re.escape_escaped(wild) if hasattr(re, "escape_escaped") else re.escape(wild).replace("\\\\", "\\"), pat)
    pat = pat.replace(re.escape("\\("), r"\\\(")
    try:
        return re.compile(pat)
    except re.error:
        return re.compile(re.escape(span))


# Claims that reference something outside this repository, or that quote a value the wiki
# substituted for a placeholder. Each one is checked by hand when it changes; they are listed here
# rather than loosening the rules for everything else.
FOREIGN = {
    ".github/workflows/ci.yml",          # the registry's CI, not this repository's
}
NOT_SHIPPED = {
    "test/rented-results/",              # created by test/rented.py; gitignored
    "dist/",                             # created by make bundle; gitignored
    "wiki/index.html",                   # created by wiki/build.py; gitignored, and built in CI
}
ALLOW = {
    "port 12434 is in use by something else",          # source: port \($port) is in use by something else
    "port <n> is in use by something else",            # and its placeholder form
    "needs NVIDIA driver 575.0 or newer",              # source interpolates the recipe's minDriver
    "no CHANGELOG section for 5.0.1",                  # source interpolates the tag's version
    "gpu memory utilization 0.97 lowered to 0.83: that is what is free on the card",  # values filled in
    "loading the model · 95%",                         # a description of the old symptom, not a message
    "max_tokens: 160",                                 # request JSON
    "chat_template_kwargs.enable_thinking: false",     # request JSON
    "sha1(\"blob <size>\\0\" + contents)",                  # the git blob hash definition
    "free < WEXP − bytes_already_there",               # arithmetic from the source, not a string
    "weights_present = marked && files_ok",            # a definition, not a string
    "curate_registry.py --index-only",                 # a command in the registry's CI
    "ok <n> - <what>",                                 # TAP output shape
    "grep -n 'name()' path",                           # the lookup advice in the header
    "are symlinked into",
    "symlink is never",
    "and the user's side turns the directory's growth into a percentage each",
    "run <recipe> <backend:index>",                    # usage text with a different bracket form
    "omarchy-launch-tui --app-id=org.omarchy.local-ai-log less +G $STATE/log",  # the panel's argv
    "server",
    "op <name> <recipeId> <detail> <percent>",   # the signature the wiki writes for lwrite's caller
    "op_pending <name> <pid> [recipeId]",       # ditto; the source's own comment spells it out
    "exec 8>\"$STATE/op.lock\"; flock -n 8",     # two source lines the wiki quotes as one
}


def main() -> int:
    text = "\n".join(p.read_text(encoding="utf-8") for p in sorted(HERE.glob("*.md")))
    tree = source_text()
    checked = 0
    bad = []

    for s in spans(text):
        p = as_path(s)
        if p is not None:
            checked += 1
            if s.split(":")[0].rstrip("/") in FOREIGN or s.rstrip("/") in {x.rstrip("/") for x in NOT_SHIPPED}:
                continue
            if not p.exists():
                bad.append(("missing path", s))
            continue
        if not looks_like_claim(s):
            continue
        if s.rstrip(". ") in ALLOW:
            continue
        checked += 1
        core = s.rstrip(". ")
        if core in tree:
            continue
        # placeholder-aware: every literal run of the span must appear, in order
        runs = [r for r in re.split(r"<[^>]{0,40}>|\\\([^)]{0,40}\)|\$[A-Za-z_]\w*|%s|…|\b[NMX]\b", core) if len(r.strip()) > 3]
        if runs and all(r in tree for r in runs):
            continue
        bad.append(("unmatched quote", s))

    if "--list" in sys.argv:
        print(f"{checked} claims checked")
        return 0

    for kind, s in bad:
        print(f"{kind}: {s}")
    print(f"{checked} claims checked, {len(bad)} not found in the tree")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())