#!/usr/bin/env bash
# Upstream: the plugin's own release and the registry's recipe file. Sourced; do not run.
#
# One detached job, at most once per TTL, fetches both from one origin (raw.githubusercontent.com)
# and stages them under $STATE. The snapshot only reads what that job left behind, so refreshing the
# card never touches the network. Nothing is adopted on its own: `omarchy-local-ai update` — the
# card's update row — applies the staged registry copy and updates the harness through Omarchy's own
# `omarchy plugin update`. OMARCHY_AI_UPDATE=0 and OMARCHY_AI_RECIPES= turn the check off.
PLUGIN_MANIFEST="$ROOT/manifest.json"
MANIFEST_URL="${OMARCHY_AI_MANIFEST_URL-https://raw.githubusercontent.com/0xSero/omarchy-local-ai/main/manifest.json}"
RECIPES_URL="${OMARCHY_AI_RECIPES_URL-https://raw.githubusercontent.com/0xSero/local-ai-registry/main/plugin/recipes.json}"
MANIFEST_REMOTE="$STATE/manifest.remote.json"
UPSTREAM_CHECKED="$STATE/upstream.checked"
UPSTREAM_TTL="${OMARCHY_AI_UPDATE_TTL:-21600}"   # seconds between checks: six hours

plugin_version() { jq -r '.version // ""' "$PLUGIN_MANIFEST" 2>/dev/null || true; }
plugin_id() { jq -r '.id // ""' "$PLUGIN_MANIFEST" 2>/dev/null || true; }
version_newer() { [[ -n $1 && -n $2 && $1 != "$2" ]] && [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1) == "$1" ]]; }   # $1 is newer than $2
# upstream_json: the snapshot's `update` object. Pure: reads the files the check left behind, never the network.
upstream_json() {
  local cur latest next='null'
  cur=$(plugin_version)
  latest=$(jq -r '.version // ""' "$MANIFEST_REMOTE" 2>/dev/null || true)
  version_newer "$latest" "$cur" || latest=""
  [[ -s $RECIPES_NEXT ]] && next=$(cat "$RECIPES_NEXT")
  jq -nc --arg cur "$cur" --arg latest "$latest" --arg hw "${1:-}" \
     --arg on "$([[ -n $MANIFEST_URL || -n $RECIPES_URL ]] && printf 1 || printf '')" \
     --argjson cur_r "$(cat "$RECIPES")" --argjson next "$next" '
    def ids($f): [($f.hardware // {})[] | ((.recipe // empty), (.recipes[]? // empty)) | .id] | unique;
    def mine($f): [($f.hardware[$hw]? // {}) | ((.recipe // empty), (.recipes[]? // empty)) | .id];
    (ids($next) - ids($cur_r)) as $new
    | {enabled:($on!=""), plugin:{current:$cur, latest:$latest},
       recipes:{generatedAt:($next.generatedAt // ""), commit:($next.registryCommit // ""), new:($new|length),
                relevant:(if $hw=="" then 0 else ([$new[] | select(. as $id | mine($next) | index($id))] | length) end)}}'
}
upstream_check() { # fetch both upstream files; stage the registry copy, adopt nothing
  local why tmp
  state_dir; date -u +%s >"$UPSTREAM_CHECKED"
  if why=$(recipes_fetch "$RECIPES_NEXT"); then log "upstream: staged registry $(recipes_generated "$RECIPES_NEXT")"
  else log "upstream: registry: $why"; fi
  [[ -n $MANIFEST_URL ]] || return 0
  tmp="$MANIFEST_REMOTE.tmp.$$"
  if curl -fsSL --max-time 20 --max-filesize 65536 --proto =https -o "$tmp" "$MANIFEST_URL" 2>>"$LOGFILE" && jq -e '.version|type=="string"' "$tmp" >/dev/null 2>&1; then chmod 600 "$tmp"; mv -f "$tmp" "$MANIFEST_REMOTE"
  else rm -f "$tmp"; log "upstream: no plugin manifest from $MANIFEST_URL"; fi
}
upstream_autocheck() { # from snapshot: at most one detached check per TTL, never on the card's critical path
  [[ -z ${OMARCHY_AI_RECIPES:-} && ${OMARCHY_AI_UPDATE:-1} != 0 ]] || return 0
  local last=0; last=$(cat "$UPSTREAM_CHECKED" 2>/dev/null || printf 0); [[ $last =~ ^[0-9]+$ ]] || last=0
  (( $(date -u +%s) - last >= UPSTREAM_TTL )) || return 0
  state_dir; date -u +%s >"$UPSTREAM_CHECKED"   # claimed now, so concurrent snapshots do not all check
  if command -v setsid >/dev/null 2>&1; then setsid "$SELF" update --check >/dev/null 2>>"$LOGFILE" </dev/null & disown
  else "$SELF" update --check >/dev/null 2>>"$LOGFILE" </dev/null & disown; fi
}
upstream_apply() { # apply what is staged, then the harness update. Prints what it did; fails when a step fails.
  local cur latest id
  if recipes_staged_newer; then recipes_apply
  elif [[ -z ${OMARCHY_AI_RECIPES:-} ]]; then printf 'recipes: %s is current\n' "$(recipes_source)"; fi
  cur=$(plugin_version); latest=$(jq -r '.version // ""' "$MANIFEST_REMOTE" 2>/dev/null || true)
  if ! version_newer "$latest" "$cur"; then printf 'plugin: %s is the newest release known\n' "${cur:-unknown}"; return 0; fi
  id=$(plugin_id)
  command -v omarchy >/dev/null 2>&1 || { printf 'plugin: %s is out, but omarchy is not on PATH; update it by hand\n' "$latest"; return 1; }
  log "update: omarchy plugin update $id ($cur -> $latest)"
  omarchy plugin update "$id" --yes || { printf 'plugin: omarchy plugin update failed (see %s)\n' "$LOGFILE"; return 1; }
  printf 'plugin: %s %s -> %s\n' "$id" "$cur" "$latest"
}