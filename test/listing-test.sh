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

grep -q "^## \[$version\]" "$ROOT/CHANGELOG.md" || fail "CHANGELOG.md has no '## [$version]' section"
echo "ok - CHANGELOG.md has a section for $version"

for f in README.md LICENSE "$(jq -r .entryPoints.barWidget "$M")"; do
  [[ -s $ROOT/$f ]] || fail "$f is missing or empty"
done
echo "ok - README, LICENSE and the bar widget entry point exist"

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
