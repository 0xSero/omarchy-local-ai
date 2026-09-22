#!/bin/bash
# The load path end to end: weights, one docker phase, acceptance, rollback, unload; direct and prompt mode.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq
source "$ROOT/test/shell.d/fixtures/local-ai/env.sh"

write_recipes rtx-4090-24gb "$(recipe test-a)" "$(recipe test-b dir '.name="Other Model"')"

"$CLI" snapshot >/dev/null
[[ $(snap .state) == idle && $(snap .hardwareId) == rtx-4090-24gb && $(snap '.recipes[0].id') == test-a && $(snap '.recipes[0].recommended') == true && $(snap '.recipes[0].onDisk') == false ]] || fail "first snapshot" "$(cat "$STATE/snapshot.json")"
pass "a fresh install snapshots idle with the card's recipes, the recommended one first"
[[ $(mode "$STATE") == 700 && $(mode "$STATE/snapshot.json") == 600 ]] || fail "state modes" "$(ls -la "$STATE")"
pass "the state directory is private"

"$CLI" load test-a
[[ $(snap .state) == ready && $(snap '.models[0].recipeId') == test-a && $(snap '.models[0].state') == ready && $(snap '.models[0].port') == 12434 ]] || fail "load" "$(cat "$STATE/snapshot.json") $(cat "$STATE/log")"
pass "load downloads, starts and accepts the recommended recipe"
[[ -f $MODELS/test--model@0123456789ab/model.safetensors && -f $MODELS/test--model@0123456789ab/.verified@0123456789abcdef0123456789abcdef01234567 ]] || fail "weights on disk" "$(find "$MODELS")"
pass "weights land under the model root, verified against the Hub tree"
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine == *"--gpus device=0"* && $engine == *"--volume $MODELS/test--model@0123456789ab:/models:ro"* && $engine == *"--network omarchy-local-ai-test-a"* && $engine != *"--ipc"* && $engine != *"--cap-add"* && $engine != *"--publish"* ]] || fail "engine argv" "$engine"
pass "the engine gets its GPU, a read-only weights mount and a private network; nothing is published"
gateway=$(grep 'docker run .*role=gateway' "$SHIM/docker.log" | tail -1)
[[ $gateway == *"--user $(id -u):$(id -g)"* && $gateway == *"--publish 127.0.0.1:12434:12434"* && $gateway == *"gateway.key:/run/gateway.key:ro"* ]] || fail "gateway argv" "$gateway"
pass "the gateway runs as the user on loopback with the key mounted read-only"
[[ $(snap '.models[0].apis | join(",")') == chat,messages,responses && $(snap '.models[0].launchable | index("claude")') != null ]] || fail "dialects" "$(snap '.models[0]')"
pass "acceptance records every dialect that answered, and the agents that can use them"
key=$(cat "$STATE/gateway.key")
grep -q "Bearer $key" "$SHIM/curl.log" && fail "key in argv" "$(grep -n Bearer "$SHIM/curl.log" | head -3)"
grep -q -- "-H @$STATE/gateway.auth" "$SHIM/curl.log" || fail "header file" "$(head -3 "$SHIM/curl.log")"
[[ $(mode "$STATE/gateway.key") == 600 && $(mode "$STATE/gateway.auth") == 600 ]] || fail "key modes"
grep -q "$key" "$STATE/log" "$STATE/state.json" "$STATE/snapshot.json" && fail "key persisted" "the key appears in the log, ledger or snapshot"
pass "the gateway key is only ever read from a 0600 file, never in argv, log, ledger or snapshot"

before=$(grep -c 'docker run' "$SHIM/docker.log")
"$CLI" load test-a
[[ $(snap .state) == ready && $(snap '.models | length') == 1 ]] || fail "reload" "$(snap .models)"
[[ ! -d $SHIM/containers/omarchy-local-ai-test-a-engine-previous ]] || fail "previous kept"
grep -q 'docker rename omarchy-local-ai-test-a-engine omarchy-local-ai-test-a-engine-previous' "$SHIM/docker.log" || fail "set aside" "$(grep rename "$SHIM/docker.log")"
pass "loading the same recipe again sets the running pair aside and drops it once the new one is accepted"

SHIM_REPLY=WRONG "$CLI" load test-b
[[ $(snap .state) == ready && $(snap .error) == *"chat acceptance failed"* && $(snap '.models[0].recipeId') == test-a && $(snap '.models[0].state') == ready ]] || fail "rollback" "$(cat "$STATE/snapshot.json")"
[[ -d $SHIM/containers/omarchy-local-ai-test-a-engine && ! -d $SHIM/containers/omarchy-local-ai-test-b-engine ]] || fail "rollback containers" "$(ls "$SHIM/containers")"
pass "a recipe that fails acceptance is removed and the previous model comes back, ready"

SHIM_CRASHLOOP=1 "$CLI" load test-b
[[ $(snap .error) == *"engine keeps crashing"* && $(snap '.models[0].recipeId') == test-a ]] || fail "crashloop" "$(snap .error)"
pass "an engine that restarts forever is reported with its last log line and rolled back"

SHIM_LEAK_THINK=1 "$CLI" load test-b
[[ $(snap .error) == *"reasoning leaks"* ]] || fail "leak" "$(snap .error)"
pass "a reasoning model whose thinking leaks into the answer is refused"

"$CLI" unload test-a
[[ $(snap .state) == idle && $(snap '.models | length') == 0 && ! -d $SHIM/containers/omarchy-local-ai-test-a-engine && ! -f $SHIM/net-omarchy-local-ai-test-a ]] || fail "unload" "$(cat "$STATE/snapshot.json") $(ls "$SHIM/containers")"
pass "unload removes the pair and its network"

"$CLI" load test-a
[[ $(snap .state) == ready ]] || fail "reload after unload"
lines=$(grep -c 'docker run' "$SHIM/docker.log")
grep -q 'huggingface.co/test/model/resolve' <(tail -n +1 "$SHIM/curl.log" | tail -20) && fail "re-download" "verified weights were fetched again"
pass "verified weights are not downloaded again"

# ---------------------------------------------------------------- prompt mode: the user cannot reach the socket
"$CLI" unload
export OMARCHY_AI_DOCKER=prompt
: >"$SHIM/docker.log"; : >"$SHIM/pkexec.log"
"$CLI" snapshot >/dev/null
[[ ! -s $SHIM/docker.log ]] || fail "snapshot touched docker" "$(cat "$SHIM/docker.log")"
pass "behind a prompt, a snapshot never calls docker"
"$CLI" load test-a
[[ $(snap .state) == ready ]] || fail "prompt load" "$(cat "$STATE/snapshot.json") $(cat "$STATE/log")"
grep -q "pkexec $CLI __priv start test-a nvidia:0" "$SHIM/pkexec.log" || fail "pkexec argv" "$(cat "$SHIM/pkexec.log")"
[[ $(grep -c pkexec "$SHIM/pkexec.log") == 1 ]] || fail "one prompt" "$(cat "$SHIM/pkexec.log")"
grep -v SHIM_ROOT "$SHIM/docker.log" | grep -q 'permission denied' && fail "user-side docker" "a docker call ran outside the prompt"
pass "a Start behind a prompt is one pkexec of the script with the recipe id and the GPU key, nothing else"
find "$STATE" -newer "$SHIM/pkexec.log" -user 0 2>/dev/null | grep -q . && fail "root-owned state"
pass "the root phase wrote nothing under the user's state"
"$CLI" unload test-a
[[ $(snap .state) == idle && $(grep -c pkexec "$SHIM/pkexec.log") == 2 ]] || fail "prompt unload" "$(cat "$SHIM/pkexec.log")"
pass "a Stop behind a prompt is one more pkexec"
SHIM_PKEXEC_FAIL=1 "$CLI" load test-a
[[ $(snap .state) == error && $(snap .error) == *"dismissed"* ]] || fail "dismissed" "$(snap .error)"
pass "a dismissed prompt is a reason on the card, and nothing changed"
unset OMARCHY_AI_DOCKER
