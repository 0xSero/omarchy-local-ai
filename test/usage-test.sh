#!/bin/bash
# The usage summary: appends, a half-written line, a completed line and a new (shorter) log are all counted right, a
# log that has not changed is not read again, a large folded log is set aside, and old buckets coarsen
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
B=${BACKEND:-$ROOT/bin/omarchy-local-ai}
FNS=$(mktemp); sed '/^paths "\$HOME"$/,$d' "$B" >"$FNS"
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
check "7 2870" "a shorter log is a new one: the history is kept"
sleep 1.1; line 800 >>"$D/usage.jsonl"
check "8 3680" "a line a second later"
rm -f "$D/summary.json"
line 1 | awk '{for(i=0;i<200005;i++)print}' >"$D/usage.jsonl"
check "200005 2200055" "large logs cross the 100000-line boundary without SIGPIPE"
[[ ! -e $D/usage.jsonl ]] && echo "ok - a folded log over 256 KB is set aside" || { echo "not ok - the large log is still there"; exit 1; }
check "200005 2200055" "with no log, the summary is still read"
line 5 >"$D/usage.jsonl"
check "200006 2200070" "the next log starts from its first line"
# buckets coarsen with age: two answers 40 days ago in one 5-minute slot, one 10 days ago, one now
rm -f "$D/summary.json"
old=$((EPOCHSECONDS - 40 * 86400)); mid=$((EPOCHSECONDS - 10 * 86400))
for t in $old $((old + 60)) $mid $EPOCHSECONDS; do printf '{"t":%d,"prompt":10,"completion":10,"ms":500,"ttft_ms":50}\n' "$t"; done >"$D/usage.jsonl"
b=$(bash -c "set -euo pipefail; shopt -s nullglob; source $FNS >/dev/null 2>&1; summary '$D'" | jq -c --argjson now "$EPOCHSECONDS" '[.buckets | to_entries[] | {a: ($now - (.key | tonumber)), v: .value}] | sort_by(-.a) | map(.v)')
[[ $b == "[40,20,20]" ]] && echo "ok - old buckets merge by age ($b)" || { echo "not ok - buckets $b"; exit 1; }
rm -rf "$T" "$FNS"
