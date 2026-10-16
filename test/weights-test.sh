#!/bin/bash
# Select only the named weight files, preserving the existing mmproj companion behavior.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
STATE=$TMP/state
mkdir -p "$STATE/trees"
rev=0000000000000000000000000000000000000001
printf 'config.json\t100\t-\ninference/engram.py\t200\t-\nmodel-01.safetensors\t300\t-\nmodel-02.safetensors\t400\t-\nmmproj.gguf\t50\t-\n' >"$STATE/trees/owner--model@$rev.tsv"
actual=$(tree owner/model "$rev" 'config.json,inference/engram.py,model-02.safetensors' | cut -f1)
[[ $actual == $'config.json\ninference/engram.py\nmodel-02.safetensors\nmmproj.gguf' ]] || { echo 'not ok - explicit weight-file list'; exit 1; }
[[ $(tree owner/model "$rev" '' | wc -l) == 5 ]] || exit 1
r=$(jq -c 'first(.hardware[].recipes[0])' "$ROOT/recipes.json")
for files in 'config.json,inference/engram.py' 'model-02.safetensors'; do
 [[ $(policy "$(jq --arg f "$files" '.weights[0].files=$f' <<<"$r")" "$ROOT/recipes.json") == ok ]] || exit 1
done
for files in '../escape' 'config.json,/absolute' 'a/../../escape'; do
 [[ $(policy "$(jq --arg f "$files" '.weights[0].files=$f' <<<"$r")" "$ROOT/recipes.json") == 'invalid weights' ]] || exit 1
done
echo 'ok - weight lists select named files and reject traversal and absolute paths'

# Small (non-LFS) files are checked against the Git blob SHA-1 the Hub lists for them, of "blob <size>\0" and the
# content: same size and other content is refused, downloaded or found in the Hugging Face cache
paths "$TMP/home"
mkdir -p "$STATE/trees"
blob=git:ce013625030ba8dba906f756967f9e9ca394464a # "hello\n", as `git hash-object` gives it
printf 'hello\n' >"$TMP/right"; printf 'jello\n' >"$TMP/wrong"
good "$TMP/right" 6 "$blob" && ! good "$TMP/wrong" 6 "$blob" && ! good "$TMP/right" 7 "$blob" || { echo 'not ok - blob check'; exit 1; }
! command -v git >/dev/null || [[ git:$(git hash-object "$TMP/right") == "$blob" ]] || { echo 'not ok - blob SHA-1 differs from git'; exit 1; }
printf 'config.json\t6\t%s\n' "$blob" >"$STATE/trees/owner--small@$rev.tsv"
item=$(jq -nc --arg rev "$rev" '{repository: "owner/small", revision: $rev, layout: "dir", mountPath: "/models", dir: "", files: ""}')
dest=$MODELS/owner--small@${rev:0:12}
status() { :; }
# SERVE: what the Hub sends for the file
hf_curl() {
  local a o=""
  for a in "$@"; do [[ $o == -o ]] && o=$a && break; o=$a; done
  echo called >>"$TMP/downloads"; printf "$SERVE" >"$o"
}
cache=$HOME_DIR/.cache/huggingface/hub/models--owner--small/snapshots/$rev
mkdir -p "$cache"; cp "$TMP/wrong" "$cache/config.json"
SERVE='hello\n' fetch m "$item"
[[ $(cat "$dest/config.json") == hello && -f $dest/.verified2 && $(wc -l <"$TMP/downloads") == 1 ]] || { echo 'not ok - a same-size cached file with other content was reused'; exit 1; }
rm -rf "$dest" "$TMP/downloads"; cp "$TMP/right" "$cache/config.json"
SERVE='' fetch m "$item"
[[ $(cat "$dest/config.json") == hello && ! -e $TMP/downloads ]] || { echo 'not ok - a matching cached file was not reused'; exit 1; }
rm -rf "$dest"; cp "$TMP/wrong" "$cache/config.json"
if (SERVE='jello\n' fetch m "$item") 2>"$TMP/err"; then echo 'not ok - a small file with other content was accepted'; exit 1; fi
grep -q 'config.json does not match the pinned revision' "$TMP/err" && [[ ! -f $dest/.verified2 && ! -e $dest/config.json ]] ||
  { echo 'not ok - the refused file'; cat "$TMP/err"; exit 1; }
# a folder an earlier version marked checked (.verified, sizes only for small files) is checked again, once
rm -rf "$dest" "$TMP/downloads"; mkdir -p "$dest"; cp "$TMP/wrong" "$dest/config.json"; : >"$dest/.verified"
SERVE='hello\n' fetch m "$item"
[[ $(cat "$dest/config.json") == hello && -f $dest/.verified2 && $(wc -l <"$TMP/downloads") == 1 ]] || { echo 'not ok - an old .verified folder was trusted'; exit 1; }
SERVE='' fetch m "$item"
[[ $(wc -l <"$TMP/downloads") == 1 ]] || { echo 'not ok - a .verified2 folder was checked again'; exit 1; }
echo 'ok - small files are checked by their Git blob SHA-1, downloaded or reused from the Hugging Face cache; the mark of an earlier version is not trusted'
