#!/bin/bash
# What the Omarchy plugin marketplace reads from this repo, checked against the limits it enforces
# (scripts/build-catalog.mjs in omacom/omarchy-plugin-marketplace): the manifest fields, a root preview image
# and no symlinks. The marketplace's own compatibility check and security baseline run on its side
# after a [Verify]: request; this catches the cheap failures before one is filed.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
M=$ROOT/manifest.json
fail() { echo "not ok - $*" >&2; exit 1; }

version=$(jq -r .version "$M")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "manifest version '$version' is not X.Y.Z"
((${#version} <= 64)) || fail "version is longer than 64 characters"
echo "ok - manifest version $version is X.Y.Z"

name=$(jq -r .name "$M")
((${#name} >= 1 && ${#name} <= 120)) || fail "name must be 1-120 characters, is ${#name}"
description=$(jq -r .description "$M")
((${#description} >= 1 && ${#description} <= 500)) || fail "description must be 1-500 characters, is ${#description}"
echo "ok - name (${#name}) and description (${#description} of 500 characters) are within the marketplace limits"

# A listing with a manual-setup override shows its description but no install command, so the description
# carries the start command; the README shows it at the top.
START='omarchy plugin add https://github.com/sybil-solutions/omarchy-local-ai --enable'
[[ $description == *"$START"* ]] || fail "the description does not carry the start command: $START"
head -n 15 "$ROOT/README.md" | grep -qF -- "$START" || fail "README.md does not show the start command in its first 15 lines"
echo "ok - the start command is in the description and at the top of the README"

grep -q "^## \[$version\]" "$ROOT/CHANGELOG.md" || fail "CHANGELOG.md has no '## [$version]' section"
echo "ok - CHANGELOG.md has a section for $version"

# validateManifest in build-catalog.mjs: schema 1, a lowercase id outside the reserved omarchy.* namespace,
# every kind backed by an entry point, entry points that are safe relative paths to real files
jq -e '.schemaVersion == 1' "$M" >/dev/null || fail "schemaVersion must be exactly 1"
jq -e '.author | type == "string" and length > 0' "$M" >/dev/null || fail "author is required"
id=$(jq -r .id "$M")
[[ $id =~ ^[a-z0-9][a-z0-9._-]*$ && $id != *..* ]] || fail "id '$id' must be lowercase letters, digits, . _ - and not contain '..'"
[[ $id != omarchy.* ]] || fail "the omarchy.* namespace is reserved"
jq -e '(.kinds | type == "array" and length > 0) and (.kinds | all(. == "bar-widget"))' "$M" >/dev/null || fail "kinds must be a non-empty list of supported values (bar-widget)"
jq -e '.entryPoints | has("barWidget")' "$M" >/dev/null || fail "kind bar-widget has no entryPoints.barWidget"
jq -e '(.barWidget.defaultSection // "right") | IN("left", "center", "right")' "$M" >/dev/null || fail "barWidget.defaultSection must be left, center or right"
while IFS= read -r f; do
  [[ $f != /* && $f != *..* && $f != *[\\:]* && -n $f ]] || fail "entry point '$f' is not a safe relative path"
  [[ -s $ROOT/$f ]] || fail "entry point $f is missing or empty"
done < <(jq -r '.entryPoints[]' "$M")
echo "ok - id $id, schema 1, kinds and entry points"

# SUBMISSION.md asks for a root README with install and removal instructions, the license and the external
# dependencies documented, and a root license file
for f in README.md LICENSE; do
  [[ -s $ROOT/$f ]] || fail "$f is missing or empty"
done
for section in 'Install' 'Remov(e|al)|Uninstall' 'Requirements|Dependencies' 'Licen[cs]e'; do
  grep -Eqi "^#{1,3} ($section)" "$ROOT/README.md" || fail "README.md has no heading for: $section"
done
echo "ok - README and LICENSE exist; README has install, removal, requirements and license sections"

links=$(find "$ROOT" -type l -not -path "$ROOT/.git/*" | head -3)
[[ -z $links ]] || fail "the marketplace refuses symlinks: $links"
echo "ok - no symlinks"

preview=$ROOT/preview.png
[[ -s $preview ]] || fail "preview.png is missing at the repo root"
read -r w h < <(od -An -tu1 -j16 -N8 "$preview" | awk '{print $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8}')
bytes=$(wc -c <"$preview")
((bytes <= 50 * 1024 * 1024)) || fail "preview.png is $bytes bytes; the limit is 50 MB"
((w * h <= 40000000)) || fail "preview.png is ${w}x${h}; the limit is 40 megapixels"
((w * 9 == h * 16)) || fail "preview.png is ${w}x${h}; the listing crops to 16:9"
echo "ok - preview.png is ${w}x${h} (16:9), $((bytes / 1024)) KiB"
