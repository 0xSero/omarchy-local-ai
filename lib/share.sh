#!/usr/bin/env bash
# Tailscale share and the gateway key. Sourced; do not run.
#
# The key exists from the first Start: agents launched from the panel always send it, the gateway
# always checks it, and sharing adds nothing but the tailnet route. `share --key <value>` replaces
# it in place; the gateway reads the file on every request, so no restart.

KEY_FILE="$STATE/gateway.key"
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

# tailscaled refuses serve changes from a plain user until that user is made the operator, once,
# with root ("Access denied: serve config denied. Use 'sudo tailscale set --operator=$USER'"). The
# panel cannot type a sudo password, so the toggle asks polkit for that one command instead, and
# every refusal lands in share.error of the snapshot (not the ledger: the model is still fine) so the
# card says why, under the toggle, rather than showing a button that did nothing.
SHARE_ERROR="$STATE/share.error"
OPERATOR_HINT="run once: sudo tailscale set --operator=\$USER"
ts_denied() { grep -qi 'access denied\|operator' "$1" 2>/dev/null; }

share_state() { # -> {available,operator,active,url,key,error}; read from tailscale each time, never cached
  local b active=false operator=true dns="" url="" st err; err=$(cat "$SHARE_ERROR" 2>/dev/null || true)
  b=$(ts_bin) || { jq -nc --arg k "$(cat "$KEY_FILE" 2>/dev/null)" --arg e "$err" '{available:false,operator:false,active:false,url:"",key:$k,error:$e}'; return; }
  st=$("$b" serve status 2>"$STATE/share.status.err") || { ts_denied "$STATE/share.status.err" && operator=false; }
  grep -q "127\.0\.0\.1:$PORT" <<<"$st" && active=true
  dns=$("$b" status --json 2>/dev/null | jq -r '(.Self.DNSName//"")|rtrimstr(".")')
  [[ -n $dns ]] && url="https://$dns"
  jq -nc --argjson a "$active" --argjson o "$operator" --arg u "$url" --arg k "$(cat "$KEY_FILE" 2>/dev/null)" --arg e "$err" '{available:true,operator:$o,active:$a,url:$u,key:$k,error:$e}'
}
share_grant() { # make this user tailscale's operator through polkit's graphical prompt; no terminal, no sudo
  command -v pkexec >/dev/null 2>&1 || return 1
  log "share: asking polkit to run tailscale set --operator=$USER"
  pkexec "$(ts_bin)" set --operator="$USER" >/dev/null 2>>"$STATE/share.err"
}
share_on() { ensure_key; "$(ts_bin)" serve --bg "http://127.0.0.1:$PORT" >/dev/null; }
share_off() { local b; b=$(ts_bin) || return 0; "$b" serve --bg "http://127.0.0.1:$PORT" off >/dev/null 2>&1 || "$b" serve reset >/dev/null 2>&1 || true; }
share_refuse() { log "share: $1"; mkdir -p "$STATE"; printf '%s\n' "$1" >"$SHARE_ERROR"; snapshot_write; fail "$1"; }

share_toggle() { # share [--key value]
  if [[ ${1:-} == --key ]]; then set_key "${2:-}"; return; fi
  jq -e '.available' >/dev/null <<<"$(share_state)" || { share_refuse "tailscale is not installed"; return; }
  [[ $(jq -r .state "$SNAPSHOT" 2>/dev/null) == ready ]] || { share_refuse "load a model first"; return; }
  if jq -e '.active' >/dev/null <<<"$(share_state)"; then share_off; log "share off"
  else
    : >"$STATE/share.err"
    if ! share_on 2>>"$STATE/share.err"; then
      if ts_denied "$STATE/share.err"; then
        share_grant && : >"$STATE/share.err" && share_on 2>>"$STATE/share.err" \
          || { share_refuse "tailscale needs a one-time permission; $OPERATOR_HINT"; return; }
      else share_refuse "$(awk 'NF{l=$0} END{print (l==""?"tailscale serve failed":l)}' "$STATE/share.err")"; return; fi
    fi
    log "share on"
  fi
  rm -f "$SHARE_ERROR"; snapshot_write
}
