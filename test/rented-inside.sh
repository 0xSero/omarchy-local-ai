#!/usr/bin/env bash
# rented-inside.sh: run the plugin's own Start inside a rented GPU container, on the real card.
#
# Rented containers have no docker daemon, so `docker` here is a shim: the plugin's engine argv
# launches the engine as a process of this container (the container IS the recipe's image), the
# gateway argv starts gateway.py, and inspect/stop/rm act on those processes. Everything else is
# the shipped plugin at one commit: hardware match on the real nvidia-smi, the gate, the weights
# marker, engine and gateway argv generation, and the full acceptance chain through the real
# gateway and engine. Weights and assets were materialized at their mount targets by the onstart
# script before this runs. The result is served over http on RESULT_PORT until the box is destroyed.
#
# Env from the driver: PLUGIN_URL PLUGIN_COMMIT GATEWAY_URL HW_ID RECIPE_ID ENGINE_ENTRYPOINT
# RESULT_PORT MODEL_REPO MODEL_REV [ENGINE_TIMEOUT]
set -uo pipefail
export ENGINE_CWD=$PWD   # the image's WORKDIR: where its entrypoint expects to run (tabbyapi's main.py lives there)
W=${WORK:-/work}; export WORK=$W; mkdir -p $W/out $W/bin $W/dock $W/state; cd $W
T0=$(date +%s)
say() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a $W/out/harness.log >&2; }
finish() { # finish <status> <detail>: write result.json and serve it forever
  local status=$1 detail=$2
  local p; for p in $W/dock/*/pid; do [[ -f $p ]] && kill "$(cat "$p")" 2>/dev/null; done   # by pid only: never pkill -f, the driver's own argv carries these names
  python3 - "$status" "$detail" <<'PY'
import json, os, sys, subprocess, glob
W=os.environ.get("WORK","/work"); status, detail = sys.argv[1], sys.argv[2]
def read(p, n=None):
    try:
        t = open(p, errors="replace").read()
        return t[-n:] if n else t
    except OSError: return ""
snap = {}
try: snap = json.loads(read(f"{W}/state/snapshot.json"))
except Exception: pass
nvsmi = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader"], capture_output=True, text=True).stdout.strip()
res = {"status": status, "detail": detail, "hardwareId": os.environ.get("HW_ID"), "recipeId": os.environ.get("RECIPE_ID"),
       "pluginCommit": os.environ.get("PLUGIN_COMMIT"), "nvidiaSmi": nvsmi, "elapsedSeconds": int(read(f"{W}/out/elapsed") or 0),
       "snapshot": {k: snap.get(k) for k in ("state", "error", "reason", "hardwareId", "apis", "model", "gpus")},
       "engineArgv": read(f"{W}/out/omarchy-local-ai-engine.argv"), "gatewayArgv": read(f"{W}/out/omarchy-local-ai-gateway.argv"),
       "keyInCurlArgv": any(l for l in read(f"{W}/out/curl.log").splitlines() if read(f"{W}/state/gateway.key").strip() and read(f"{W}/state/gateway.key").strip() in l),
       "pluginLog": read(f"{W}/state/log", 6000), "engineLogTail": read(f"{W}/engine.log", 3000), "gatewayLogTail": read(f"{W}/gateway.log", 1500),
       "harnessLog": read(f"{W}/out/harness.log", 3000)}
json.dump(res, open(f"{W}/out/result.json", "w"), indent=1)
PY
  say "result: $status ($detail); serving on :$RESULT_PORT"
  cd $W/out && exec python3 -m http.server "$RESULT_PORT" --bind 0.0.0.0 >/dev/null 2>&1
}
trap 'finish harness-error "line $LINENO"' ERR

# ---------------------------------------------------------------- tools the plugin needs
export PATH="$W/bin:$PATH"
fetch() { python3 -c 'import sys,urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' "$1" "$2"; }
command -v jq >/dev/null || { fetch https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64 $W/bin/jq
  echo "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f  $W/bin/jq" | sha256sum -c --quiet || finish harness-error "jq checksum"; chmod +x $W/bin/jq; }
fetch "$PLUGIN_URL" $W/plugin.tgz && mkdir -p $W/plugin && tar -xzf $W/plugin.tgz -C $W/plugin --strip-components=1 || finish harness-error "plugin download"
fetch "$GATEWAY_URL" $W/gateway.py || finish harness-error "gateway download"
say "plugin $PLUGIN_COMMIT, gateway.py $(wc -c <$W/gateway.py) bytes, jq $(jq --version)"

# curl the plugin's way, in python: -fsS --max-time N --max-filesize N -H 'k: v' | -H @file -d data URL. Records its argv.
cat >$W/bin/curl <<'PY'
#!/usr/bin/env python3
import sys, json, urllib.request, urllib.error
import os; W=os.environ.get("WORK","/work")
args = sys.argv[1:]; open(f"{W}/out/curl.log", "a").write(" ".join(args) + "\n")
url = args[-1]; headers = {}; data = None; timeout = 30; i = 0
while i < len(args) - 1:
    a = args[i]
    if a == "-H":
        h = args[i+1]; h = open(h[1:]).read().strip() if h.startswith("@") else h
        k, _, v = h.partition(":"); headers[k.strip()] = v.strip(); i += 2
    elif a == "-d": data = args[i+1].encode(); i += 2
    elif a == "--max-time": timeout = float(args[i+1]); i += 2
    elif a == "--max-filesize": i += 2
    else: i += 1
req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
try:
    with urllib.request.urlopen(req, timeout=timeout) as r: sys.stdout.write(r.read().decode(errors="replace")); sys.exit(0)
except urllib.error.HTTPError as e: sys.stderr.write(f"curl: ({22}) HTTP {e.code}\n"); sys.exit(22)
except Exception as e: sys.stderr.write(f"curl: (7) {e}\n"); sys.exit(7)
PY
chmod +x $W/bin/curl

# docker, as the shim described above
cat >$W/bin/docker <<'SH'
#!/usr/bin/env bash
# a docker whose containers are processes of this container. Records under /work/dock/<name>/.
W=${WORK:-/work}; D=$W/dock; say() { printf '%s docker: %s\n' "$(date -u +%H:%M:%S)" "$*" >>$W/out/harness.log; }
alive() { [[ -f $D/$1/pid ]] && kill -0 "$(cat "$D/$1/pid")" 2>/dev/null; }
case "$1" in
  network) exit 0 ;;
  image) exit 0 ;;                       # this container is the image
  pull) exit 0 ;;
  inspect)
    fmt=""; name=""; for a in "$@"; do case $a in -f) ;; '{{'*) fmt=$a ;; inspect) ;; *) name=$a ;; esac; done
    [[ -d $D/$name ]] || exit 1
    case $fmt in
      *Labels*) key=${fmt#*\"}; key=${key%%\"*}; grep -E "^$key=" "$D/$name/labels" | head -1 | cut -d= -f2- ;;
      *Running*) alive "$name" && echo true || echo false ;;
      *) echo "[]" ;;
    esac; exit 0 ;;
  run)
    shift; name=""; role=""; entry=""; declare -a envs=() ; declare -a vols=(); declare -a rest=(); labels=""
    while (($#)); do
      case $1 in
        --detach|-d) ;; --restart|--network|--network-alias|--shm-size|--gpus|--device|--user|--publish|-p) shift ;;
        --name) name=$2; shift ;;
        --label) labels+="$2"$'\n'; [[ $2 == *role=engine ]] && role=engine; [[ $2 == *role=gateway ]] && role=gateway; [[ $2 == *download=1 ]] && role=download; shift ;;
        --env|-e) envs+=("$2"); shift ;;
        --volume|-v) vols+=("$2"); shift ;;
        --entrypoint) entry=$2; shift ;;
        --rm) ;;
        *) rest+=("$1") ;;
      esac; shift
    done
    [[ $role == download ]] && { say "download container: weights are already materialized"; exit 0; }
    [[ -n $name ]] || exit 0
    mkdir -p "$D/$name"; printf '%s' "$labels" >"$D/$name/labels"; printf '%q ' "${rest[@]}" >"$D/$name/argv"; printf '%q ' "${rest[@]}" >"$W/out/$name.argv"   # a copy that survives rm
    for v in "${vols[@]}"; do src=${v%%:*}; tgt=${v#*:}; tgt=${tgt%%:*}   # assets: copy the file to its target; weights: already there
      [[ -f $src && $tgt != /run/gateway.key ]] && { mkdir -p "$(dirname "$tgt")"; cp -f "$src" "$tgt"; }; done
    if [[ $role == engine ]]; then
      # rest = image then arguments; drop the image (this container is it)
      args=("${rest[@]:1}"); entry=${ENGINE_ENTRYPOINT:-$entry}   # the driver passes the contract's entrypoint; the local rehearsal passes a fake engine
      say "engine: ${entry:+$entry }${args[*]}"
      ( for e in "${envs[@]}"; do export "$e"; done; cd "${ENGINE_CWD:-/}"; exec ${entry:+"$entry"} "${args[@]}" ) >$W/engine.log 2>&1 &
      echo $! >"$D/$name/pid"
    elif [[ $role == gateway ]]; then
      keyfile=""; for v in "${vols[@]}"; do [[ $v == *:/run/gateway.key* ]] && keyfile=${v%%:*}; done
      say "gateway: gateway.py upstream from env, key file $keyfile"
      ( for e in "${envs[@]}"; do case $e in UPSTREAM=*) export "UPSTREAM=${e#UPSTREAM=}"; export UPSTREAM=${UPSTREAM/\/\/engine:/\/\/127.0.0.1:} ;;
                                            GATEWAY_KEY_FILE=*) export GATEWAY_KEY_FILE=$keyfile ;; *) export "$e" ;; esac; done
        exec python3 $W/gateway.py ) >$W/gateway.log 2>&1 &
      echo $! >"$D/$name/pid"
    else say "unknown role for $name"; exit 125; fi
    echo "$name"; exit 0 ;;
  stop) alive "$2" && kill "$(cat "$D/$2/pid")"; sleep 1; exit 0 ;;
  start) exit 0 ;;                       # a stopped process cannot be restarted here; rollback is not under test
  rename) mv "$D/$2" "$D/$3"; exit 0 ;;
  rm) n=${@: -1}; alive "$n" && kill "$(cat "$D/$n/pid")" 2>/dev/null; rm -rf "$D/$n"; exit 0 ;;
esac
exit 0
SH
chmod +x $W/bin/docker
export ENGINE_ENTRYPOINT="${ENGINE_ENTRYPOINT:-}"

# ---------------------------------------------------------------- the plugin's state for this run
export OMARCHY_AI_STATE=$W/state OMARCHY_AI_USER_HOME="${HOME:-/root}" OMARCHY_AI_MODEL_ROOT=$W/models OMARCHY_AI_CACHE_ROOT=$W/cache OMARCHY_AI_FOREGROUND=1 OMARCHY_AI_POLL=5 \
  OMARCHY_AI_TIMEOUT="${ENGINE_TIMEOUT:-2400}" OMARCHY_AI_NO_HOST_HF=1 OMARCHY_AI_RECIPES=$W/plugin/recipes.json
mkdir -p $W/state/weights
jq -nc --arg repo "$MODEL_REPO" --arg rev "$MODEL_REV" --arg t "$(date -u +%FT%TZ)" '{repository:$repo,revision:$rev,completedAt:$t,kind:"rented",path:"materialized"}' >"$W/state/weights/$RECIPE_ID.json"
say "gpu: $(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | tr -d '\n')"

CLI=$W/plugin/bin/omarchy-local-ai
snap=$($CLI snapshot) || finish plugin-error "snapshot failed"
say "match: hardwareId=$(jq -r .hardwareId <<<"$snap") reason='$(jq -r .reason <<<"$snap")' gpus=$(jq -c '[.gpus[]|{product,vramGb,hardwareId}]' <<<"$snap")"
[[ $(jq -r .hardwareId <<<"$snap") == "$HW_ID" ]] || finish no-match "plugin matched '$(jq -r .hardwareId <<<"$snap")', expected $HW_ID: $(jq -r .reason <<<"$snap")"

say "load"
$CLI load; rc=$?
echo $(( $(date +%s) - T0 )) >$W/out/elapsed
snap=$($CLI snapshot)
state=$(jq -r .state <<<"$snap")
say "load exit $rc, state $state, error '$(jq -r .error <<<"$snap")', apis $(jq -c .apis <<<"$snap")"
{ grep -h "accepted\|tps=\|error:\|rollback" $W/state/log || true; } | tail -3 | while read -r l; do say "$l"; done
if [[ $state == ready ]]; then finish ready "$(grep -o 'tps=[0-9]* apis=.*' $W/state/log | tail -1)"; else finish "$state" "$(jq -r .error <<<"$snap")"; fi
