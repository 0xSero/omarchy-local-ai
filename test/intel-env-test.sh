#!/bin/bash
# Intel engines must stage host copies and turn shared-system USM off. 6.8.2 set only the staging flag;
# a cold vLLM load of Qwen3.8-27B still faulted the xe copy engine until shared-system USM was disabled.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { echo "not ok - $*" >&2; exit 1; }
line=$(grep -n 'EnableSharedSystemUsmSupport' "$ROOT/bin/omarchy-local-ai" || true)
[[ -n $line ]] || fail "intel engines do not set EnableSharedSystemUsmSupport"
echo "$line" | grep -q 'EnableSharedSystemUsmSupport=0' || fail "EnableSharedSystemUsmSupport is not 0: $line"
echo "$line" | grep -q 'TreatNonUsmForTransfersAsSharedSystem=0' || fail "staging flag missing beside shared-system USM: $line"
echo "$line" | grep -q 'NEOReadDebugKeys=1' || fail "NEO debug keys are not enabled beside the Intel flags: $line"
echo 'ok - intel engines stage copies and disable shared-system USM'
