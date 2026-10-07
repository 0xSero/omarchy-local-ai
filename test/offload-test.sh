#!/bin/bash
# Synthetic Docker and files only: no daemon, model downloads or GPU.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed '/^paths "\$HOME"$/,$d' "${BACKEND:-$ROOT/bin/omarchy-local-ai}" >"$TMP/functions"
source "$TMP/functions"
STATE=$TMP/state MODELS=$TMP/models LOG=$TMP/log RECIPES=$TMP/recipes.json
mkdir -p "$STATE/deploy/test" "$MODELS" "$STATE/usage/test"
echo '{}' >"$STATE/deploy/test/config.json"
printf '{"gateway":{"image":"ghcr.io/x/gateway@sha256:%064d"},"hardware":{"test":{"match":{"backend":"nvidia"}}}}\n' 0 >"$RECIPES"
R=$(jq -nc '{id:"test", hw:"test", cards:1, image:("ghcr.io/x/engine@sha256:"+("a"*64)),
  weights:[{repository:"test/raw",revision:("b"*40),layout:"dir",mountPath:"/models/raw",files:""},
    {repository:"test/engram",revision:("c"*40),layout:"dir",mountPath:"/models/engram",files:""}],
  prepare:{at:"/models",args:["prepare"],verifyArgs:["verify-pack"],gpu:true,sizeGb:117},
  launch:{arguments:[],environment:{MODE:"exact",NVIDIA_VISIBLE_DEVICES:"all"},port:8000,shm:"8g",
    resources:{memoryBytes:59055800320,memorySwapBytes:59055800320,memlockUnlimited:true,ipcLock:true}}}')
[[ $(policy "$R") == ok ]]
for change in '.launch.resources.privileged=true' '.launch.resources.memoryBytes=true' '.launch.resources.memorySwapBytes=1' 'del(.prepare.verifyArgs)' '.prepare.at="/models/raw/pack"' '.launch.flags=["--privileged"]' '.launch.environment.NOTE="hello\u0000--privileged"' '.launch.environment.NOTE=1' '.launch.arguments=["serve\u0000--privileged"]'; do
  [[ $(policy "$(jq "$change" <<<"$R")") != ok ]]
done
echo 'ok - offload policy rejects arbitrary flags, invalid resources and masked/unverified output'
owned() { [[ -d $1 || -f $1 ]]; }
say() { :; }
ours() { return 1; }
allocation_lock() { :; }
cards_free() { :; }
# Forward calls to the Docker function below, preserving argument boundaries; no external timeout/daemon.
timeout() { while [[ $1 == --* ]]; do shift; done; shift; "$@"; }
mv() { [[ $1 != -T ]] || shift; command mv "$@"; }
for w in $(jq -r '.weights[].repository|gsub("/";"--")' <<<"$R"); do
  case $w in test--raw) rev=bbbbbbbbbbbb ;; *) rev=cccccccccccc ;; esac
  mkdir -p "$MODELS/$w@$rev"; echo input >"$MODELS/$w@$rev/checkpoint"; touch "$MODELS/$w@$rev/.verified"
done
docker() {
  jq -nc '$ARGS.positional' --args -- "$@" >>"$TMP/docker.jsonl"
  [[ $1 != wait ]] || { echo 0; return; }
  [[ $1 == run ]] || return 0
  local i j output=""
  for ((i=1;i<=$#;i++)); do if [[ ${!i} == --volume ]]; then j=$((i+1)); output=${!j}; output=${output%%:*}; break; fi; done
  if [[ ${@: -1} == prepare ]]; then
    [[ -z ${STUB_DELAY:-} ]] || sleep 0.3
    [[ -z ${STUB_FAIL:-} ]] || return 42
    echo generated >"$output/generated"
    [[ -z ${STUB_CANCEL:-} ]] || touch "$STATE/deploy/test/cancel"
  elif [[ ${@: -1} == verify-pack ]]; then
    [[ $(cat "$output/generated" 2>/dev/null) == generated ]]
  fi
}
prepare_model test "$R" --gpus '"device=0"'
PACK=$(prepared_path "$R")
[[ -f $PACK/.complete.json && ! -e $(rundir test)/generated ]]
jq -se 'map(select(.[0]=="run")) as $r | $r|length==2' "$TMP/docker.jsonl" >/dev/null
jq -se 'map(select(.[0]=="run")) as $r |
  ($r[0]|index("--gpus")!=null) and ($r[1]|index("--gpus")==null and index("NVIDIA_VISIBLE_DEVICES=void")!=null) and
  all($r[]; index("MODE=exact")!=null and index("59055800320")!=null and index("memlock=-1:-1")!=null and index("IPC_LOCK")!=null
    and index("NVIDIA_VISIBLE_DEVICES=all")==null) and
  all($r[]; [range(0;length) as $i|select(.[$i]=="--volume")|.[$i+1]] as $m |
    ($m|length)==3 and all($m[1:][]; endswith(":ro")))' "$TMP/docker.jsonl" >/dev/null
echo 'ok - same pinned image prepares with selected GPU, verifies CPU-only, inherits typed resources and mounts inputs read-only'
: >"$TMP/docker.jsonl"
prepare_model test "$R" --gpus '"device=0"'
jq -se 'map(select(.[0]=="run")) | length==1 and .[0][-1]=="verify-pack"' "$TMP/docker.jsonl" >/dev/null
touch "$STATE/deploy/test/cancel"
if (prepare_model test "$R") >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'cancelled' "$TMP/error"
rm "$STATE/deploy/test/cancel"
echo 'ok - verified persistent output is checked and reused, while cancelled warm starts are refused' 
for change in '.image|="ghcr.io/x/engine@sha256:"+("d"*64)' '.weights[0].revision=("e"*40)' '.launch.environment.MODE="fast"' '.prepare.args=["prepare","different"]' '.launch.resources.memoryBytes=59055800319'; do
  [[ $(prepared_path "$(jq "$change" <<<"$R")") != "$PACK" ]]
done
echo 'ok - image, input revision, preparation arguments, environment and resources cannot reuse an incompatible store'
echo corrupted >"$PACK/generated"
if (prepare_model test "$R") >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'failed verification' "$TMP/error"
[[ -f $PACK/generated ]]
echo generated >"$PACK/generated"
echo 'ok - completion markers cannot admit corrupted output or trigger its replacement'
R_CPU=$(jq '.prepare.gpu=false|.launch.environment.MODE="cpu"' <<<"$R")
: >"$TMP/docker.jsonl"
prepare_model test "$R_CPU" --gpus '"device=0"' --device /dev/dri/renderD128
jq -se 'all(.[]|select(.[0]=="run"); index("--gpus")==null and index("--device")==null and index("NVIDIA_VISIBLE_DEVICES=void")!=null)' "$TMP/docker.jsonl" >/dev/null
echo 'ok - CPU preparation and verification receive no GPU or device passthrough'
H=$(jq -nc '{freeRamGb:500,diskFreeGb:1,disk:"nvme",got:{},have:["test--raw@bbbbbbbbbbbb/.verified","test--engram@cccccccccccc/.verified"],prepared:[]}')
[[ $(jq -r --argjson h "$H" "$NEEDS unfit(\$h)" <<<"$R") == *'117 GB free disk'* ]]
H=$(jq --argjson c "$(prepared_contract "$R")" '.prepared=[$c]' <<<"$H")
[[ $(jq -r --argjson h "$H" "$NEEDS unfit(\$h)" <<<"$R") == "" ]]
echo 'ok - verified raw weights cannot bypass the missing generated-store disk budget'
R_NEW=$(jq '.launch.environment.MODE="new"' <<<"$R")
STUB_FAIL=1
if (prepare_model test "$R_NEW") >"$TMP/error" 2>&1; then exit 1; fi
unset STUB_FAIL
[[ ! -e $(prepared_path "$R_NEW") && -z $(find "$MODELS/prepared" -name '.staging.*' -print) ]]
STUB_CANCEL=1
if (prepare_model test "$R_NEW") >"$TMP/error" 2>&1; then exit 1; fi
unset STUB_CANCEL
rm "$STATE/deploy/test/cancel"
[[ ! -e $(prepared_path "$R_NEW") && -f $PACK/.complete.json && -z $(find "$MODELS/prepared" -name '.staging.*' -print) ]]
echo 'ok - failed and cancelled preparation leaves no published output and preserves completed stores'
: >"$TMP/docker.jsonl"
STUB_DELAY=1
prepare_model test "$R_NEW" & P1=$!
prepare_model test "$R_NEW" & P2=$!
wait "$P1"; wait "$P2"
unset STUB_DELAY
jq -se 'map(select(.[-1]=="prepare"))|length==1' "$TMP/docker.jsonl" >/dev/null
echo 'ok - simultaneous starts serialize one preparation and verify the shared store'
mkdir -p "$(rundir test)"; echo transient >"$(rundir test)/asset"
ours() { [[ $1 == "$(preparer test)" ]]; }
: >"$TMP/docker.jsonl"
remove test
jq -se --arg n "$(preparer test)" 'any(.[]; . == ["rm","-f",$n])' "$TMP/docker.jsonl" >/dev/null
ours() { return 1; }
[[ -f $PACK/.complete.json && ! -d $(rundir test) ]]
echo 'ok - Stop removes its owned preparer and retains completed stores outside the runtime directory'
mkdir -p "$STATE/deploy/live"
jq -nc --arg p "$PACK" '{id:"removed-from-catalog",managedPaths:[$p]}' >"$STATE/deploy/live/config.json"
recipe() { [[ $1 == test ]] && echo "$R"; }
jq -nc --argjson r "$R" '{recipe:$r}' >"$STATE/deploy/test/config.json"
jq -nc --argjson r "$R" '{recipe:$r,managedPaths:[]}' >"$STATE/deploy/live/config.json"
if (cmd_forget test) >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'incomplete download records' "$TMP/error"
jq -nc --arg p "$PACK" '{id:"removed-from-catalog",managedPaths:[$p]}' >"$STATE/deploy/live/config.json"
if (cmd_forget test) >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'stop models using these weights' "$TMP/error"
[[ -f $PACK/.complete.json ]]
rm -rf "$STATE/deploy/live" "$STATE/deploy/test"
mkdir -p "$TMP/user-hf"; echo private-input >"$TMP/user-hf/input"
cmd_forget test
[[ ! -d $PACK && -f $TMP/user-hf/input ]]
echo 'ok - Forget protects persisted active paths after catalog removal and deletes only managed downloads'
