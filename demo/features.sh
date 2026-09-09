#!/bin/bash
# features.sh: record every feature of the card being used, the way a person does it: real cursor,
# real clicks, prompts and commands typed live. Records HDMI-A-3 (1920x1080) with the cursor and
# marks every chapter for cut.py. Assumes the first-party panel (omarchy.local-ai) on the bar and
# a model ready on the default card when it starts.
#
# Chapters: card (the card and the GPU picker), start-3090 (pin an RTX 3090, Stop, Start: Gemma
# downloads and loads there), agent (Open agent · claude, a live prompt), share (Share on Tailscale,
# the tailnet URL fetched from a terminal with the key file, Stop sharing), cli (Stop, then
# `omarchy local ai gpu auto` and `load` from the terminal: back to the default card).
set -u
exec 2>>/tmp/features-trace.log
export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
CK=${OMARCHY_PATH:-$HOME/omarchy-pr}; export OMARCHY_PATH=$CK PATH="$CK/bin:$PATH"
TARGET=omarchy.local-ai; CLI="omarchy local ai"
OUT=/tmp/features-raw.mp4; MARKS=/tmp/features-marks.txt; T0=$(date +%s)
: >"$MARKS"; mark() { echo "$(( $(date +%s) - T0 )) $1" >>"$MARKS"; }
ipc() { timeout 5 qs -p "$CK/shell" ipc call $TARGET "$@" >/dev/null 2>&1; }
hypr() { timeout 5 hyprctl dispatch "$1" >/dev/null 2>&1; }
state() { $CLI snapshot | jq -r .state; }
wait_state() { local want=$1 n=0; while [[ $(state) != "$want" && $n -lt 300 ]]; do sleep 2; n=$((n+1)); done; }

# --- the hand ---------------------------------------------------------------------------------
CUR_X=960; CUR_Y=540
glide() {
  local x=$1 y=$2 i n=24 t
  for i in $(seq 1 $n); do
    t=$(python3 -c "import math; print((1-math.cos(math.pi*$i/$n))/2)")
    hypr "hl.dsp.cursor.move({ x = $(python3 -c "print(round($CUR_X+($x-$CUR_X)*$t))"), y = $(python3 -c "print(round($CUR_Y+($y-$CUR_Y)*$t))") })"
    sleep 0.018
  done
  CUR_X=$x; CUR_Y=$y
}
click() { glide "$1" "$2"; sleep 0.35; python3 "$HOME/click.py" "${3:-left}"; sleep 0.7; }
type_text() { wtype -d 34 -- "$1"; sleep 0.5; wtype -k Return; }

# --- geometry (measured on HDMI-A-3; the card is anchored to the bar, rows keep their distance
# from the bottom, lists push the rows above them up by 25 px each) ------------------------------
ICON="1765 1060"; X=1712
BOTTOM=1018                          # the last row: Stop when loaded, Start when idle
SHARE_OFF=988; OPENAGENT_OFF=958; GPU_OFF=928        # share off, model loaded
SHARE_ON=904;  OPENAGENT_ON=874;  GPU_ON=844          # share on (URL and key lines shown)
START_SWITCH=928                                      # another model running: Start sits where Open agent was; Open agent, Share, Stop below it
gpu_row() { echo $(( $2 - 100 + 30 + ($1 - 1) * 25 )); }   # gpu_row <n 1..4> <GPU line y when closed>
agent_row() { case $1 in pi) echo 782;; omp) echo 807;; opencode) echo 832;; claude) echo 857;; codex) echo 882;; grok) echo 907;; copilot) echo 932;; crush) echo 957;; esac; }

place() { # place <class>: fullscreen on workspace 1 of HDMI-A-3
  local cls=$1 i where
  for i in 1 2 3 4 5 6 7 8; do
    sleep 1
    where=$(timeout 5 hyprctl clients -j 2>/dev/null | jq -r --arg c "$cls" '.[] | select(.class==$c) | "\(.monitor) \(.workspace.id) \(.fullscreen)"' | head -1)
    [[ -z $where ]] && continue
    [[ $where == "0 1 2" ]] && return 0
    hypr "hl.dsp.window.move({ workspace = 1, window = \"class:$cls\" })"; sleep 0.4
    hypr "hl.dsp.window.fullscreen({ mode = \"fullscreen\", window = \"class:$cls\" })"
  done
  return 1
}
close_win() { hypr "hl.dsp.window.close({ window = \"class:$1\" })"; sleep 1.5; }
terminal() { # a terminal on camera; commands are typed into it
  setsid omarchy-launch-tui --app-id=org.omarchy.demo bash >/dev/null 2>&1 </dev/null & disown
  place org.omarchy.demo || echo "terminal did not appear" >&2; sleep 1.5; click 1200 700; sleep 0.5
}

# --- a known starting point: default card, model ready, share off ---------------------------
$CLI gpu auto >/dev/null 2>&1
[[ $(state) == ready ]] || { $CLI load >/dev/null; wait_state ready; }
$CLI snapshot | jq -e '.share.active' >/dev/null 2>&1 && { $CLI share >/dev/null; sleep 3; }
timeout 5 qs -p "$CK/shell" ipc call notifications dismissAll >/dev/null 2>&1
ipc close; close_win org.omarchy.agent; close_win org.omarchy.demo
hypr "hl.dsp.cursor.move({ x = $CUR_X, y = $CUR_Y })"

gpu-screen-recorder -w HDMI-A-3 -f 30 -fm cfr -q high -cursor yes -o "$OUT" >/tmp/features-rec.log 2>&1 &
REC=$!; sleep 3; mark "rec-start"

# 1. the card and the GPU picker
mark "card"
sleep 1; click $ICON; sleep 3
click $X $GPU_OFF; sleep 3                      # the picker: four cards, the B70 in use
click $X "$(gpu_row 1 $GPU_OFF)"; sleep 4       # pin the first RTX 3090: the card now shows its recipe, and says the B70 model is still up
echo "pinned: $($CLI snapshot | jq -c '.gpus[]|select(.chosen)|.product'), model $($CLI snapshot | jq -r .model.name)" >&2

# 2. Start Gemma on the 3090: Start replaces the running model (set aside, then dropped once Gemma is accepted)
mark "start-3090"
click $X $START_SWITCH; sleep 6                 # Start · N GB, while the other model still runs
[[ $(state) == ready && $(omarchy local ai snapshot | jq -r .running.current) == false ]] && { echo "Start click did not take; ipc load" >&2; ipc load; sleep 3; }
[[ $(state) == idle ]] && { ipc open; sleep 1.5; click $X $BOTTOM; sleep 5; }
[[ $(state) == idle ]] && { echo "Start click did not take; loading directly" >&2; $CLI load >/dev/null; }
while [[ $(state) != ready ]]; do sleep 3; [[ $(state) == error ]] && { echo "load errored: $($CLI snapshot | jq -r .error)" >&2; break; }; done
echo "loaded on: $($CLI snapshot | jq -c '{model:.model.name, gpu:(.gpus[]|select(.chosen)|.product)}')" >&2
sleep 4; ipc close; sleep 1

# 3. Open agent · claude, a live prompt on the new model
mark "agent"
click $ICON; sleep 1.5
click $X $OPENAGENT_OFF; sleep 1                # the agent list
click $X "$(agent_row claude)"                  # claude opens on the model
place org.omarchy.agent || { ipc close; sleep 1; click $ICON; sleep 1; click $X $OPENAGENT_OFF; sleep 1; click $X "$(agent_row claude)"; place org.omarchy.agent; }
ipc close; sleep 0.5; click 1200 700; sleep 10
type_text "In two lines: which model are you talking to, and what is its API base URL? Do not run any commands."
sleep 45
close_win org.omarchy.agent

# 4. Share on Tailscale, fetch it from a terminal with the key file, Stop sharing
mark "share"
click $ICON; sleep 1.5
click $X $SHARE_OFF; sleep 8                    # Share on Tailscale: the toggle is an op, then the URL appears
wait_state ready; $CLI snapshot | jq -e '.share.active' >/dev/null || { echo "Share click did not take; cli" >&2; $CLI share >/dev/null; }
wait_state ready; sleep 4
url=$($CLI snapshot | jq -r .share.url)
ipc close; sleep 0.5
terminal
type_text "curl -s -H @~/.local/state/omarchy/local-ai/gateway.auth $url/v1/models | jq -c '.data[].id'"
sleep 4
type_text "curl -s -o /dev/null -w '%{http_code}\\n' $url/v1/models   # without the key"
sleep 4
close_win org.omarchy.demo
click $ICON; sleep 1.5
click $X $SHARE_ON; sleep 8; wait_state ready   # Stop sharing
$CLI snapshot | jq -e '.share.active' >/dev/null && { echo "Stop sharing click did not take; cli" >&2; $CLI share >/dev/null; wait_state ready; }; sleep 3
ipc close; sleep 1

# 5. Stop from the card, then the CLI: back to the default card and its model
mark "cli"
click $ICON; sleep 1.5; click $X $BOTTOM; sleep 6; [[ $(state) == idle ]] || ipc unload; wait_state idle; sleep 2; ipc close; sleep 1
terminal
type_text "omarchy local ai gpu auto | jq -c 'map({product, chosen})'"
sleep 4
type_text "omarchy local ai load && watch -n 2 'omarchy local ai snapshot | jq -c \"{state, detail: .operation.detail, percent: .operation.percent}\"'"
wait_state ready; sleep 4
wtype -M ctrl c -m ctrl
sleep 1; type_text "omarchy local ai snapshot | jq -c '{state, model: .model.name, gpu: (.gpus[] | select(.chosen) | .product)}'"
sleep 5
close_win org.omarchy.demo
click $ICON; sleep 4; ipc close

mark "end"; sleep 2; mark "rec-stop"
kill -INT $REC; wait $REC 2>/dev/null; echo "recorded $OUT"; cat "$MARKS"
