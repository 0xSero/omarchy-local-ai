#!/bin/bash
# Weights: fetched as the user, verified against the Hub tree, resumed, adopted from the Hub cache, laid out per engine.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command jq
source "$ROOT/test/shell.d/fixtures/local-ai/env.sh"

write_recipes rtx-4090-24gb "$(recipe test-dir)" "$(recipe test-hub hub)" "$(recipe test-sub dir '.weights[0].dir="Sub-Model" | .asset={name:"config.yml",mountPath:"/app/config.yml",text:"model_dir: /workspace/models\n"} | .scratch="/root/.cache/vllm"')"
"$CLI" snapshot >/dev/null

SHIM_CORRUPT=1 "$CLI" load test-dir
[[ $(snap .state) == error && $(snap .error) == *"did not match the pinned revision"* && ! -f $MODELS/test--model@0123456789ab/model.safetensors ]] || fail "corrupt" "$(snap .error) $(find "$MODELS")"
pass "a download whose checksum does not match the Hub tree is deleted and refused"

SHIM_DOWNLOAD_FAIL=1 "$CLI" load test-dir
[[ $(snap .state) == error && $(snap .error) == *"resumes on the next load"* ]] || fail "curl failure" "$(snap .error)"
pass "a failed transfer is a reason, and the next load resumes it"

rm -rf "$STATE/trees"; SHIM_HUB_DOWN=1 "$CLI" load test-dir
[[ $(snap .error) == *"cannot list"* ]] || fail "hub down" "$(snap .error)"
pass "an unreachable Hub is a reason, not a hang"

"$CLI" load test-dir
[[ $(snap .state) == ready ]] || fail "dir load" "$(snap .error)"
grep -q -- '--proto =https' "$SHIM/curl.log" || fail "https only"
[[ $(mode "$MODELS/test--model@0123456789ab/model.safetensors") == 644 ]] || fail "weights mode" "$(ls -l "$MODELS/test--model@0123456789ab")"
pass "weights download over https only and land world-readable for the engine's own uid"
"$CLI" unload >/dev/null

"$CLI" load test-hub
[[ $(snap .state) == ready ]] || fail "hub load" "$(snap .error) $(cat "$STATE/log")"
hub="$MODELS/hf/hub/models--test--model"
[[ -f $hub/snapshots/0123456789abcdef0123456789abcdef01234567/model.safetensors && $(cat "$hub/refs/main") == 0123456789abcdef0123456789abcdef01234567 ]] || fail "hub layout" "$(find "$MODELS")"
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine == *"--volume $MODELS/hf:/root/.cache/huggingface:ro"* && $engine == *"--env HF_HUB_OFFLINE=1"* ]] || fail "hub mount" "$engine"
pass "a hub-layout recipe gets the Hub cache tree, mounted read-only, with the engine kept offline"
"$CLI" unload >/dev/null

"$CLI" load test-sub
[[ $(snap .state) == ready ]] || fail "sub load" "$(snap .error) $(cat "$STATE/log")"
[[ -f $MODELS/test--model@0123456789ab/Sub-Model/model.safetensors ]] || fail "subdir" "$(find "$MODELS")"
engine=$(grep 'docker run .*role=engine' "$SHIM/docker.log" | tail -1)
[[ $engine == *"--volume $MODELS/test--model@0123456789ab:/models:ro"* && $engine == *"--volume $STATE/assets/config.yml:/app/config.yml:ro"* && $engine == *"scratch/test-sub:/root/.cache/vllm"* ]] || fail "sub mounts" "$engine"
[[ $(cat "$STATE/assets/config.yml") == "model_dir: /workspace/models" && $(mode "$STATE/assets/config.yml") == 644 ]] || fail "asset" "$(ls -l "$STATE/assets")"
pass "a recipe with a subdirectory, an asset and a scratch path gets exactly those three mounts, weights and asset read-only"
"$CLI" unload >/dev/null

# the user's own Hub cache is adopted when it verifies, so a model already on the machine is not fetched twice
rm -rf "$MODELS"; mkdir -p "$HOME/.cache/huggingface/hub/models--test--model/snapshots/0123456789abcdef0123456789abcdef01234567"
head -c 4096 /dev/zero >"$HOME/.cache/huggingface/hub/models--test--model/snapshots/0123456789abcdef0123456789abcdef01234567/model.safetensors"
: >"$SHIM/curl.log"
"$CLI" load test-dir
[[ $(snap .state) == ready ]] || fail "adopt" "$(snap .error)"
grep -q '/resolve/' "$SHIM/curl.log" && fail "adopt downloaded" "$(grep resolve "$SHIM/curl.log")"
grep -q 'adopted model.safetensors from' "$STATE/log" || fail "adopt log" "$(tail -5 "$STATE/log")"
pass "a verified copy in the user's Hub cache is adopted instead of downloaded"
"$CLI" unload >/dev/null; rm -rf "$MODELS" "$HOME/.cache/huggingface"; mkdir -p "$MODELS/old-layout-5x/Sub-Model"
head -c 4096 /dev/zero >"$MODELS/old-layout-5x/Sub-Model/model.safetensors"; : >"$SHIM/curl.log"
"$CLI" load test-dir
[[ $(snap .state) == ready ]] || fail "adopt legacy" "$(snap .error)"
grep -q '/resolve/' "$SHIM/curl.log" && fail "legacy downloaded" "$(grep resolve "$SHIM/curl.log")"
[[ -f $MODELS/test--model@0123456789ab/model.safetensors ]] || fail "legacy placed" "$(find "$MODELS")"
pass "a verified copy from an older layout of this plugin is adopted, so an upgrade downloads nothing"
"$CLI" unload >/dev/null; mkdir -p "$HOME/.cache/huggingface/hub/models--test--model/snapshots/0123456789abcdef0123456789abcdef01234567"
head -c 4096 /dev/urandom >"$HOME/.cache/huggingface/hub/models--test--model/snapshots/0123456789abcdef0123456789abcdef01234567/model.safetensors"
rm -rf "$MODELS"; : >"$SHIM/curl.log"
"$CLI" load test-dir
[[ $(snap .state) == ready ]] || fail "adopt-mismatch" "$(snap .error)"
grep -q '/resolve/' "$SHIM/curl.log" || fail "mismatch not downloaded"
pass "a cached copy that does not verify is ignored and the pinned file is downloaded"

# a private token travels in a header file, never in argv or the log
"$CLI" unload >/dev/null; rm -rf "$MODELS" "$STATE/trees"; : >"$SHIM/curl.log"
HF_TOKEN=hf_secret_token_value "$CLI" load test-dir
[[ $(snap .state) == ready ]] || fail "token load" "$(snap .error)"
grep -q hf_secret_token_value "$SHIM/curl.log" "$STATE/log" "$STATE/snapshot.json" && fail "token leaked" "$(grep -l hf_secret_token_value "$SHIM/curl.log" "$STATE/log")"
grep -q -- "-H @$STATE/hf.header" "$SHIM/curl.log" || fail "token header" "$(head -2 "$SHIM/curl.log")"
[[ $(mode "$STATE/hf.header") == 600 ]] || fail "token mode"
pass "HF_TOKEN reaches curl only through a 0600 header file"

# stopping a download keeps the partial file and the next load resumes
"$CLI" unload >/dev/null; rm -rf "$MODELS"
export OMARCHY_AI_FOREGROUND=0
SHIM_DOWNLOAD_SLOW=4 "$CLI" load test-dir >/dev/null
for i in 1 2 3 4 5 6 7 8 9 10; do [[ $(snap .state) == download && -f $MODELS/test--model@0123456789ab/model.safetensors.part ]] && break; sleep 0.5; done
[[ $(snap .state) == download ]] || fail "background download" "$(cat "$STATE/snapshot.json")"
"$CLI" unload >/dev/null
[[ $(snap .state) == idle && -f $MODELS/test--model@0123456789ab/model.safetensors.part ]] || fail "cancel" "$(snap .state) $(find "$MODELS")"
pass "a running download can be stopped and its partial file stays for a resume"
export OMARCHY_AI_FOREGROUND=1
