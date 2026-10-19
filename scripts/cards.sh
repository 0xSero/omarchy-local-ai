#!/bin/bash
# The supported-hardware table in README.md, from recipes.json. `make docs` writes it between the cards markers;
# test/docs-test.sh fails when the README's copy differs.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
jq -r '
  def maker: {"nvidia": "NVIDIA", "intel-xpu": "Intel", "amd-rocm": "AMD", "amd-vulkan": "AMD", "cpu": "CPU"}[.] // .;
  def clean: sub("^CPU \\(AVX2\\)$"; "any x86-64 CPU with AVX2") | sub("^NVIDIA GB10$"; "DGX Spark (GB10)")
    | sub("^NVIDIA "; "") | sub("^Intel "; "") | sub("^AMD "; "") | sub("^GeForce "; "") | sub(" Laptop GPU$"; " Laptop") | sub(" Generation$"; "")
    | sub(" \\(\\d+-core.*\\)$"; "");
  def card: (.name | clean) + (if .vramGb > 0 then " \(.vramGb) GB" + (if .unifiedMemory then " unified" else "" end) else "" end);
  ["NVIDIA", "Intel", "AMD", "CPU"] as $order
  | [.hardware[].match | {maker: (.backend | maker), label: card}] | unique
  | group_by(.maker) | sort_by(.[0].maker as $m | $order | index($m))
  | "| Maker | Cards |", "|---|---|",
    (.[] | "| \(.[0].maker) | \([.[].label] | sort_by(ascii_downcase | [scan("\\d+|\\D+") | (tonumber? // .)]) | join(", ")) |")
' "$ROOT/recipes.json"
