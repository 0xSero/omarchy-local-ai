#!/bin/bash
# Click through the Local AI panel in a private headless sway, recording it: real backend, real pointer clicks.
# Output: ~/la-rec-out/{clickthrough.mp4, clickthrough.gif, steps/NN-*.png, steps.log}
set -uo pipefail
H=$HOME/la-rec OUT=$HOME/la-rec-out RT=/tmp/la-rec-rt
rm -rf "$OUT" "$RT"; mkdir -p "$OUT/frames" "$OUT/steps" "$RT"; chmod 700 "$RT"
cat >"$RT/config" <<'C'
output HEADLESS-1 resolution 1280x880 scale 1 bg #0b0b0c solid_color
default_border none
default_floating_border none
seat seat0 hide_cursor 0
for_window [title="panel"] floating enable, move position 0 0
for_window [title="Local AI"] floating enable, move position 0 0
for_window [app_id="^org.omarchy.local-ai$"] floating enable, resize set 860 600, move position 400 180
C
# uwsm-app hands a launch to the user's systemd, which runs it on the real desktop; here the terminal must open inside
# this private session, so a shim on this run's PATH runs the command directly
mkdir -p "$RT/shim"; printf '#!/bin/bash\n[[ $1 == -- ]] && shift\nexec "$@"\n' >"$RT/shim/uwsm-app"; chmod +x "$RT/shim/uwsm-app"
export PATH=$RT/shim:$PATH
export XDG_RUNTIME_DIR=$RT WAYLAND_DISPLAY=wayland-1
env -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway -c "$RT/config" >"$RT/sway.log" 2>&1 &
SP=$!
for i in $(seq 50); do [[ -S $RT/wayland-1 ]] && break; sleep 0.1; done
export SWAYSOCK=$(ls "$RT"/sway-ipc.*.sock 2>/dev/null | head -1)
[[ -n $SWAYSOCK ]] || { echo "no sway"; tail "$RT/sway.log"; exit 1; }
quickshell -p "$H" >"$OUT/quickshell.log" 2>&1 &
QP=$!
sleep 4
# frames: four a second, cursor included
( n=0; while kill -0 $QP 2>/dev/null; do grim -c -t jpeg -q 85 "$OUT/frames/$(printf %05d $n).jpg" 2>/dev/null; n=$((n+1)); sleep 0.25; done ) &
FP=$!

ipc() { timeout 10 quickshell ipc -p "$H" call rec "$@" 2>/dev/null | tail -1; }
s=0
step() { s=$((s+1)); ipc step "$1" >/dev/null; echo "$(date +%T) $s. $1" | tee -a "$OUT/steps.log"; sleep 0.6; grim -c "$OUT/steps/$(printf %02d $s)-$2.png"; }
# where <label> [nth] [full]: wait up to 40 s for it to be on screen
where() {
  local p="" t=0
  while ((t < 80)); do p=$(ipc pos "$1" "${2:-0}" "${3:-false}"); [[ $p =~ ^[0-9]+\ [0-9]+$ ]] && { echo "$p"; return 0; }; sleep 0.5; t=$((t+1)); done
  echo "MISSING $1" | tee -a "$OUT/steps.log" >&2; return 1
}
glide() { # move the pointer there in a few steps, so the video shows where it goes
  local x=$1 y=$2 i
  for i in 1 2 3 4; do swaymsg -q seat seat0 cursor set $((CX + (x - CX) * i / 4)) $((CY + (y - CY) * i / 4)); sleep 0.06; done
  CX=$x CY=$y
}
CX=600 CY=400
click() { local r t=0; while ((t < 60)); do r=$(ipc click "$1" "${2:-0}" "${3:-false}"); [[ $r == ok ]] && { sleep 1.2; return 0; }; sleep 0.5; t=$((t+1)); done; echo "MISSING $1 ($r)" | tee -a "$OUT/steps.log" >&2; return 1; }
gone() { local t=0; while ((t < 120)); do [[ -z $(ipc pos "$1" 0 false) ]] && return 0; sleep 0.5; t=$((t+1)); done; return 1; }

sleep 2
step "gpus: one row per running model and per card; the header and footer never move" gpus
click "home" && step "home: launch each running model in its agent and folder; the usage tiers; the calendar" home
AGENT=$(jq -r '.deployments[] | select(.state=="ready") | .agent' <(~/.config/omarchy/plugins/sero.local-ai/bin/omarchy-local-ai snapshot) | head -1)
FOLDER=$(jq -r '.deployments[] | select(.state=="ready") | .folder' <(~/.config/omarchy/plugins/sero.local-ai/bin/omarchy-local-ai snapshot) | head -1 | sed "s#^$HOME#~#")
NAME=$(jq -r '.deployments[] | select(.state=="ready") | .name' <(~/.config/omarchy/plugins/sero.local-ai/bin/omarchy-local-ai snapshot) | head -1)
LABEL=$(node -e 0 2>/dev/null; case $AGENT in omp) echo oh-my-pi;; claude) echo "Claude Code";; *) echo "$AGENT";; esac)
click "$LABEL" && step "launch › agent: every installed agent, the chosen one dotted, the default named" agent
click "pi" && sleep 2 && step "choose pi: set for this model only, back on home" agent-set
click "pi" && click "$LABEL" && sleep 2 && step "and back to $LABEL (the box's own choice)" agent-revert
click "$FOLDER" && step "launch › folder: recent folders, choose another…" folder
click "~/Work" && sleep 2 && step "choose ~/Work, back on home" folder-set
click "~/Work" && click "$FOLDER" && sleep 2 && step "and back to $FOLDER" folder-revert
click "gpus" && step "gpus again" gpus2
click "$NAME" && step "open the running row: speed, prefill, first token, tokens, uptime, its settings, Open · Stop · logs" open-run
if where "off · turn on" >/dev/null; then
  click "off · turn on" && where "on ›" >/dev/null && step "share: turned on (the tailnet address now answers with the key)" share-on
  click "on ›" && step "the share page: address and key, each copied with one tap" share
  click "Stop sharing" && sleep 2 && where "off · turn on" >/dev/null && step "Stop sharing: off again" share-off
fi
click "$NAME" && step "close the row" closed
click "CPU" && step "open a free row (the CPU): every model for it, the pick highlighted, Run" open-free
click "Run LFM2.5-2.6B" && step "Run: the row shows the model starting, with its progress" starting
where "LFM2.5-2.6B" >/dev/null; sleep 20; step "ready: the model is its own row with its speed" running-cpu
click "LFM2.5-2.6B" && step "open it" open-cpu
click "Stop" && gone "LFM2.5-2.6B" && sleep 1 && step "Stop: the CPU is free again" stopped
for n in 0 1 2; do
  p=$(ipc pos "Arc Pro B70" $n false); [[ -n $p ]] || continue
  click "Arc Pro B70" $n && step "open Arc Pro B70 #$((n+1)): in use (what holds it, what it could run) or free (its models)" b70-$n
  click "Arc Pro B70" $n
done
if [[ -n $(ipc pos "RTX 3090" 0 false) ]]; then click "RTX 3090" && step "open the RTX 3090: held by another program, its models readable" rtx3090; click "RTX 3090"; fi
click "󰊓" && sleep 2 && step "full screen: the same tabs in a window, every row opened as a tile" full-gpus
click "home" 0 true && sleep 1 && step "full screen home: launch and a year of the calendar" full-home
click "󰊔  esc" 0 true && sleep 1 && step "back to the panel" back
click "home" && click "Open" && sleep 10 && step "Open: $LABEL opens in a terminal on the running model, in its folder" open-agent
swaymsg -q '[title="^(?!panel$|Local AI$).*"] kill' 2>/dev/null; sleep 1
step "done" done
sleep 1
kill $QP; wait $FP 2>/dev/null; kill $SP; wait $SP 2>/dev/null
ffmpeg -loglevel error -y -framerate 4 -pattern_type glob -i "$OUT/frames/*.jpg" -vf "scale=1280:-2" -c:v libx264 -pix_fmt yuv420p -r 12 "$OUT/clickthrough.mp4"
ffmpeg -loglevel error -y -i "$OUT/clickthrough.mp4" -vf "fps=4,scale=900:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" "$OUT/clickthrough.gif"
ls -la "$OUT" | tail -5; echo "frames: $(ls "$OUT/frames" | wc -l), steps: $(ls "$OUT/steps" | wc -l)"; grep -c MISSING "$OUT/steps.log" || true
