#!/usr/bin/env bash
# Tailnet share and the gateway key. Sourced; do not run.
#
# The key exists from the first Start: agents launched from the panel always send it, the gateway
# always checks it, and sharing adds nothing but the tailnet route. `share --key <value>` replaces
# it in place; the gateway reads the file on every request, so no restart.
#
# The route is the gateway's own port published on this machine's tailnet address, next to the
# loopback one: `docker run --publish 100.x.y.z:12434:12434`. Nothing else is involved. No
# `tailscale serve` (which refuses a plain user until root names them the operator, and which the
# panel cannot escalate), no polkit, no password, no extra image. WireGuard already encrypts
# everything on the tailnet, so a plain http URL there is as private as the https one serve would
# have minted. Toggling restarts the stateless gateway with or without the second publish; agents
# reconnect on their next request. `tailscale status` is the only tailscale call, and it needs no
# operator.

KEY_FILE="$STATE/gateway.key"
SHARE_MARK="$STATE/share.on"      # present while sharing is wanted; gateway_argv honours it on every start
SHARE_ERROR="$STATE/share.error"  # the last refusal, shown under the toggle; cleared by the next success
ts_bin() { command -v tailscale 2>/dev/null; }

ensure_key() {
  [[ -s $KEY_FILE ]] && return 0
  mkdir -p "$STATE"; (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-32 >"$KEY_FILE")
  lwrite '.share.key=$k' --arg k "$(cat "$KEY_FILE")"
}
set_key() {
  [[ ${#1} -ge 16 ]] || { fail "key must be at least 16 characters"; return; }
  mkdir -p "$STATE"; (umask 077; printf '%s\n' "$1" >"$KEY_FILE"); lwrite '.share.key=$k' --arg k "$1"; snapshot_write
}

tailnet_self() { # -> {ip,dns}; empty fields when tailscale is off
  local b; b=$(ts_bin) || { printf '{"ip":"","dns":""}'; return; }
  "$b" status --json 2>/dev/null | jq -c '{ip:((.Self.TailscaleIPs//[])|map(select(test("^[0-9.]+$")))|.[0]//""), dns:((.Self.DNSName//"")|rtrimstr("."))}' 2>/dev/null \
    || printf '{"ip":"","dns":""}'
}
share_wanted() { [[ -f $SHARE_MARK ]]; }
share_publish_argv() { # extra `docker run` words for the gateway while sharing is on; nothing otherwise
  share_wanted || return 0
  local ip; ip=$(tailnet_self | jq -r .ip); [[ -n $ip ]] || return 0
  printf '%s\0' --publish "$ip:$PORT:12434"
}

share_state() { # -> {available,active,url,key,error}; read from tailscale and docker each time, never cached
  local self ip dns active=false url="" err; err=$(cat "$SHARE_ERROR" 2>/dev/null || true)
  self=$(tailnet_self); ip=$(jq -r .ip <<<"$self"); dns=$(jq -r .dns <<<"$self")
  if [[ -z $ip ]]; then jq -nc --arg k "$(cat "$KEY_FILE" 2>/dev/null)" --arg e "$err" '{available:false,active:false,url:"",key:$k,error:$e}'; return; fi
  share_wanted && owned "$GATEWAY" && running "$GATEWAY" && active=true
  url="http://${dns:-$ip}:$PORT"
  jq -nc --argjson a "$active" --arg u "$url" --arg k "$(cat "$KEY_FILE" 2>/dev/null)" --arg e "$err" '{available:true,active:$a,url:$u,key:$k,error:$e}'
}

share_on() { mkdir -p "$STATE"; : >"$SHARE_MARK"; restart_gateway; }
share_off() { rm -f "$SHARE_MARK"; owned "$GATEWAY" && running "$GATEWAY" && restart_gateway; return 0; }
share_forget() { rm -f "$SHARE_MARK"; }   # for unload: the gateway is about to go, no restart
share_refuse() { # the model is still fine, so this goes under the toggle, not into the ledger's error
  log "share: $1"; mkdir -p "$STATE"; printf '%s\n' "$1" >"$SHARE_ERROR"; op_done; fail "$1"
}

share_toggle() { # share [--key value]
  if [[ ${1:-} == --key ]]; then set_key "${2:-}"; return; fi
  jq -e '.available' >/dev/null <<<"$(share_state)" || { share_refuse "tailscale is not connected"; return; }
  [[ $(jq -r .state "$SNAPSHOT" 2>/dev/null) == ready ]] || { share_refuse "load a model first"; return; }
  if jq -e '.active' >/dev/null <<<"$(share_state)"; then
    op share "" "stopping the tailnet route" 0   # an op, so the card shows the toggle in progress
    share_off || { share_refuse "could not restart the gateway (see $LOGFILE)"; return; }; log "share off"
  else
    op share "" "publishing on the tailnet" 0
    share_on || { rm -f "$SHARE_MARK"; restart_gateway || true; share_refuse "could not publish on the tailnet (see $LOGFILE)"; return; }; log "share on"
  fi
  rm -f "$SHARE_ERROR"; op_done
}
