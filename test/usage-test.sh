#!/bin/bash
# The usage summary: appends, a half-written line, a completed line and a truncated log are all counted right, and a
# log that has not changed is not read again
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
B=${BACKEND:-$ROOT/bin/omarchy-local-ai}
FNS=$(mktemp); sed '/^paths "\$HOME"$/,$d' "$B" >"$FNS"
T=$(mktemp -d); D=$T/usage/m; mkdir -p "$D"
line() { printf '{"t":%d,"prompt":%d,"completion":10,"ms":500,"ttft_ms":50}\n' "$EPOCHSECONDS" "$1"; }
linec() { printf '{"t":%d,"prompt":%d,"completion":10,"ms":500,"ttft_ms":50,"cached":%d,"reasoning":%d}\n' "$EPOCHSECONDS" "$1" "$2" "$3"; }
req() { bash -c "set -euo pipefail; shopt -s nullglob; source $FNS >/dev/null 2>&1; summary '$D'" | jq -r '"\(.requests) \(.total)"'; }
vals() { bash -c "set -euo pipefail; shopt -s nullglob; source $FNS >/dev/null 2>&1; summary '$D'" | jq -r '"\(.cached.n) \(.cached.sum) \(.cached.prompt) \(.reasoning.n) \(.reasoning.sum)"'; }
check() { local got; got=$(req); [[ $got == "$1" ]] && echo "ok - $2 ($got)" || { echo "not ok - $2: want $1, got $got"; exit 1; }; }
checkv() { local got; got=$(vals); [[ $got == "$1" ]] && echo "ok - $2 ($got)" || { echo "not ok - $2: want $1, got $got"; exit 1; }; }
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
rm -f "$D/summary.json"
line 1 | awk '{for(i=0;i<200005;i++)print}' >"$D/usage.jsonl"
check "200005 2200055" "large logs cross the 100000-line boundary without SIGPIPE"
rm -f "$D/summary.json"
# before the engine's first cached count (an older gateway) nothing counts; after it, a prompt with no count is a miss
line 500 >"$D/usage.jsonl"; linec 1000 400 3 >>"$D/usage.jsonl"; line 2000 >>"$D/usage.jsonl"
checkv "1 400 3000 1 3" "the cache share starts at the first reported count and counts a later miss"
checkv "1 400 3000 1 3" "unchanged: the totals are read from the summary"
linec 1000 600 5 >>"$D/usage.jsonl"
checkv "2 1000 4000 2 8" "an appended row adds to cache and reasoning"
rm -f "$D/summary.json"
line 100 >"$D/usage.jsonl"; line 200 >>"$D/usage.jsonl"
checkv "0 0 0 0 0" "an engine that never reports a count has no cache figures"
rm -rf "$T" "$FNS"
