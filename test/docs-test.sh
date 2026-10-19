#!/bin/bash
# The docs stay true to the code: the generated cards table, links and anchors, the shell commands, no orphan pages.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "not ok - $*" >&2; exit 1; }

want=$(bash "$ROOT/scripts/cards.sh")
have=$(sed -n '/^<!-- cards:/,/^<!-- \/cards -->/p' "$ROOT/README.md" | sed '1d;$d')
[[ $have == "$want" ]] || fail "README.md's supported-hardware table differs from recipes.json: run make docs"
echo "ok - the README's supported-hardware table matches recipes.json"

# a heading's GitHub anchor: lowercase, punctuation dropped, spaces to hyphens
anchors() { sed -n 's/^#\{1,6\} //p' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 _-]//g; s/ /-/g'; }
for f in "$ROOT/README.md" "$ROOT"/docs/*.md; do
  while read -r link; do
    path=${link%%#*} frag=${link#*#}; [[ $link == *#* ]] || frag=""
    target=$f; [[ -z $path ]] || target=$(dirname "$f")/$path
    [[ -e $target ]] || fail "${f#$ROOT/} links to $link, which does not exist"
    [[ -z $frag || ! -f $target ]] || anchors "$target" | grep -qx -- "$frag" || fail "${f#$ROOT/} links to $link, which has no such heading"
  done < <(grep -oE '\]\([^) ]+\)' "$f" | sed 's/^](//; s/)$//' | grep -vE '^(https?:|mailto:)' || true)
done
echo "ok - every relative link and anchor in README.md and docs/ resolves"

verbs=$(sed -n '/^```bash/,/^```/p' "$ROOT/README.md" | grep -oE '^omarchy-local-ai [a-z]+' | awk '{print $2}' | sort -u)
[[ -n $verbs ]] || fail "README.md shows no omarchy-local-ai commands"
# the backend's usage line, "# omarchy:args=setup | registry | forget <recipe> | ...", lists every verb it takes
known=$(sed -n 's/^# omarchy:args=//p' "$ROOT/bin/omarchy-local-ai" | tr '|' '\n' | awk '{print $1}')
for v in $verbs; do grep -qx -- "$v" <<<"$known" || fail "README.md shows 'omarchy-local-ai $v', which the backend does not have"; done
echo "ok - every command the README shows exists in the backend ($(wc -w <<<"$verbs" | tr -d ' ') verbs)"

for d in "$ROOT"/docs/*.md; do
  n=docs/$(basename "$d"); [[ $n == docs/STYLE.md ]] && continue
  grep -qF "]($n" "$ROOT/README.md" || fail "$n is not linked from README.md"
done
echo "ok - every page in docs/ is linked from the README"
