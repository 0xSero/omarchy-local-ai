#!/bin/bash
# The root boundary: what crosses it, what root refuses, and that the policy is re-checked as root.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq
source "$ROOT/test/shell.d/fixtures/local-ai/env.sh"

write_recipes rtx-4090-24gb "$(recipe test-a)"
"$CLI" snapshot >/dev/null
"$CLI" load test-a >/dev/null   # weights and key in place, direct mode
"$CLI" unload >/dev/null

# the root side, called the way pkexec would, from a scrubbed environment
ROOT_EXTRA=()   # environment a caller might try to smuggle in; env -i is what pkexec does
root() { env -i PATH="$PATH" HOME="$HOME" SHIM="$SHIM" OMARCHY_AI_TEST_ROOT=1 OMARCHY_AI_TEST_HOME="$HOME" SHIM_ROOT=1 PKEXEC_UID="$(id -u)" ${ROOT_EXTRA[@]+"${ROOT_EXTRA[@]}"} "$CLI" __priv "$@"; }
out=$(root start test-a nvidia:0 2>/dev/null); rc=$?
[[ $rc == 0 && $out == *"port 12434"* && $out == *"accepted {"* ]] || fail "root start" "rc=$rc $out"
pass "the root phase starts, accepts and reports the port and the record on stdout"
root stop test-a >/dev/null 2>&1

for bad in "../etc" "a b" "x;rm" "$(printf 'a\nb')" "A-upper"; do
  out=$(root start "$bad" nvidia:0 2>/dev/null) && fail "bad id accepted" "$bad"
  [[ $out == *"reason invalid recipe id"* ]] || fail "bad id reason" "$bad -> $out"
done
pass "a recipe id that is not [a-z0-9.-] is refused before anything runs"
out=$(root start test-a "nvidia:0;x" 2>/dev/null) && fail "bad key accepted"
[[ $out == *"reason invalid gpu key"* ]] || fail "bad key reason" "$out"
pass "a GPU key that is not vendor:index is refused"
out=$(root start not-a-recipe nvidia:0 2>/dev/null) && fail "unknown recipe accepted"
[[ $out == *"not in recipes.json"* ]] || fail "unknown recipe reason" "$out"
pass "a recipe id that is not in the packaged file is refused"
out=$(root frobnicate 2>/dev/null) && fail "unknown phase accepted"
[[ $out == *"unknown phase"* ]] || fail "unknown phase reason" "$out"
pass "only start, stop and toolkit exist behind the prompt"
[[ ! -f $SHIM/docker.log ]] || ! grep -q 'docker run' <(grep -A0 'frobnicate\|not-a-recipe' "$SHIM/docker.log" 2>/dev/null || true)
pass "a refused phase never reaches docker"

# the policy, re-checked by root on the packaged recipe: a swapped file cannot widen what runs
swap() { write_recipes rtx-4090-24gb "$(recipe test-a dir "$1")"; }
swap '.image="ghcr.io/x/engine:latest"';                        out=$(root start test-a nvidia:0 2>/dev/null) && fail "unpinned image ran"; [[ $out == *"not digest-pinned"* ]] || fail "unpinned reason" "$out"
swap '.weights[0].mountPath="/models/../../etc"';              out=$(root start test-a nvidia:0 2>/dev/null) && fail "traversal ran"; [[ $out == *"invalid weights mount path"* ]] || fail "traversal reason" "$out"
swap '.weights[0].repository="../../etc/passwd"';              out=$(root start test-a nvidia:0 2>/dev/null) && fail "bad repo ran"; [[ $out == *"invalid weights repository"* ]] || fail "bad repo reason" "$out"
swap '.weights[0].revision="main"';                             out=$(root start test-a nvidia:0 2>/dev/null) && fail "unpinned revision ran"; [[ $out == *"not pinned"* ]] || fail "revision reason" "$out"
swap '.launch.arguments += ["--enforce-eager"]';                out=$(root start test-a nvidia:0 2>/dev/null) && fail "eager ran"; [[ $out == *"disallowed launch argument"* ]] || fail "eager reason" "$out"
swap '.launch.environment.LD_PRELOAD="${HOME}/x"';             out=$(root start test-a nvidia:0 2>/dev/null) && fail "placeholder ran"; [[ $out == *"unsupported placeholder"* ]] || fail "placeholder reason" "$out"
swap '.launch.entrypoint="/bin/sh -c evil"';                    out=$(root start test-a nvidia:0 2>/dev/null) && fail "entrypoint ran"; [[ $out == *"invalid entrypoint"* ]] || fail "entrypoint reason" "$out"
swap '.asset={name:"../../x",mountPath:"/etc/x",text:"y"}';    out=$(root start test-a nvidia:0 2>/dev/null) && fail "asset ran"; [[ $out == *"invalid asset"* ]] || fail "asset reason" "$out"
swap '.scratch="/root/../../etc"';                              out=$(root start test-a nvidia:0 2>/dev/null) && fail "scratch ran"; [[ $out == *"invalid scratch path"* ]] || fail "scratch reason" "$out"
swap '.cards=64';                                               out=$(root start test-a nvidia:0 2>/dev/null) && fail "cards ran"; [[ $out == *"invalid card count"* ]] || fail "cards reason" "$out"
grep -q 'docker run' <(grep -c 'docker run' "$SHIM/docker.log" | awk '$1>2') && fail "policy bypass" "docker ran for a refused recipe"
pass "ten kinds of swapped recipe are refused by root before docker is called"

# the schema itself has no way to say the dangerous things: the words are simply unknown to the launcher
swap '.launch.ipc="host" | .launch.capAdd=["SYS_ADMIN"] | .launch.securityOpt=["seccomp=unconfined"] | .launch.devices=["/dev/sda"] | .launch.networkMode="host"'
root start test-a nvidia:0 >/dev/null 2>&1 || fail "extra fields broke the start"
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine != *"--ipc"* && $engine != *"--cap-add"* && $engine != *"--security-opt"* && $engine != *"/dev/sda"* && $engine != *"--network host"* ]] || fail "unknown fields leaked" "$engine"
pass "fields the schema does not have are ignored: ipc, capabilities, security options, devices and network mode cannot be expressed"
root stop >/dev/null 2>&1

# only two strings cross: nothing from the user's environment reaches the phase
ROOT_EXTRA=(OMARCHY_AI_MODEL_ROOT=/tmp/elsewhere OMARCHY_AI_STATE=/tmp/elsewhere XDG_STATE_HOME=/tmp/elsewhere)
out=$(root start test-a nvidia:0 2>/dev/null) || fail "env start" "$out"
ROOT_EXTRA=()
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine == *"--volume $MODELS/test--model@0123456789ab:/models:ro"* && $engine != *elsewhere* ]] || fail "env leaked" "$engine"
pass "root derives the model path from the home, not from the caller's environment"
root stop >/dev/null 2>&1

# the target: only a canonical regular file is ever handed to pkexec
export OMARCHY_AI_DOCKER=prompt
: >"$SHIM/pkexec.log"
"$CLI" load test-a >/dev/null
grep -q "^pkexec $CLI __priv start test-a nvidia:0$" "$SHIM/pkexec.log" || fail "target" "$(cat "$SHIM/pkexec.log")"
pass "pkexec is given the script's own canonical path, the phase, the recipe id and the GPU key"
ln -sfn "$CLI" "$TMP/bin/omarchy-local-ai"
: >"$SHIM/pkexec.log"
"$TMP/bin/omarchy-local-ai" unload >/dev/null
grep -q "^pkexec $CLI __priv stop" "$SHIM/pkexec.log" || fail "symlink target" "$(cat "$SHIM/pkexec.log")"
pass "a symlinked invocation still names the real file to pkexec"
