#!/bin/bash
# The usage summary: appends, a half-written line, a completed line and a truncated log are all counted right, and a
# log that has not changed is not read again
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
B=$ROOT/bin/omarchy-local-ai
FNS=$(mktemp); sed '/^if \[\[ \${1:-} =~ \^__/,$d' "$B" >"$FNS"
T=$(mktemp -d); D=$T/usage/m; mkdir -p "$D"
line() { printf '{"t":%d,"prompt":%d,"completion":10,"ms":500,"ttft_ms":50}\n' "$EPOCHSECONDS" "$1"; }
req() { bash -c "set -euo pipefail; shopt -s nullglob; source $FNS >/dev/null 2>&1; summary '$D'" | jq -r '"\(.requests) \(.total)"'; }
check() { local got; got=$(req); [[ $got == "$1" ]] && echo "ok - $2 ($got)" || { echo "not ok - $2: want $1, got $got"; exit 1; }; }
line 100 >"$D/usage.jsonl"; line 200 >>"$D/usage.jsonl"; line 300 >>"$D/usage.jsonl"
check "3 630" "three lines"
check "3 630" "unchanged: read from the summary"
line 400 >>"$D/usage.jsonl"; line 500 >>"$D/usage.jsonl"
check "5 1550" "two appended lines"
printf '{"t":%d,"prompt":600,' "$EPOCHSECONDS" >>"$D/usage.jsonl"
check "5 1550" "a half-written line waits"
printf '"completion":10,"ms":500,"ttft_ms":50}\n' >>"$D/usage.jsonl"
check "6 2160" "the line, once written, is counted"
line 700 >"$D/usage.jsonl"
check "1 710" "a truncated log is summed again"
sleep 1.1; line 800 >>"$D/usage.jsonl"
check "2 1520" "a line a second later"
rm -rf "$T" "$FNS"
