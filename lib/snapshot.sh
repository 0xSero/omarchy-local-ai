#!/usr/bin/env bash
# The derived read model. Sourced; do not run.
#
# snapshot_write derives everything from the ledger + reality (owned containers, each slot's
# gateway /v1/models, tailscale, installed agents) + recipes.json, and rewrites $SNAPSHOT. It edits
# the ledger only for housekeeping (a slot whose containers are gone).
# Workers call it after every step so the panel, which watches the file, updates live; the panel
# also asks for one on a slow timer so a container that died outside an op shows up.
#
# State rule: busy while the op's pid is alive; else ready when any model answers and was
# verified; else error when the ledger has one or a model is up but wrong; else idle.
#
# Snapshot 10: `models` lists every running model (slot) with its port, cards, state, dialects,
# launchable agents, capabilities, cache sizes and tokens served today; `gpus` carry temperature,
# load and VRAM in use; `cards` group identical cards and count the ones in use; `recipes` list
# every offered recipe of a detected card with its disk state; `selected` is the picked recipe.
# `running`, `port`, `apis`, `agents` and `share` describe the model the card looks at.

declare -A IMG_OK=()   # image presence by reference, asked once per snapshot: recipes share images
image_present() { local i=$1; [[ -n ${IMG_OK[$i]:-} ]] || { if docker image inspect "$i" >/dev/null 2>&1; then IMG_OK[$i]=1; else IMG_OK[$i]=0; fi; }; [[ ${IMG_OK[$i]} == 1 ]]; }
recipe_on_disk() { # recipe_on_disk <recipe-json> -> true|false: weights marked complete and, where docker answers, the image pulled
  local r=$1
  if weights_present "$r" && { ! docker_direct || image_present "$(jq -r .launch.image <<<"$r")"; }; then printf true; else printf false; fi
}
# port_listener -> none | gateway | other, for $PORT. A listener is found with ss, or, without ss, by a
# connect probe (never assumed free). Our gateway is recognised by its exact refusal of an
# unkeyed /v1/models: HTTP 401 with {"error":{"type":"authentication_error","message":"invalid or missing API key"}}.
port_listener() {
  local listening=false out code body
  if command -v ss >/dev/null 2>&1; then [[ -n $(ss -Hltn "( sport = :$PORT )" 2>/dev/null) ]] && listening=true
  else curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; [[ $? != 7 ]] && listening=true; fi   # 7: connection refused
  $listening || { printf none; return; }
  out=$(curl -s --max-time 2 --max-filesize 4096 -w '\n%{http_code}' "http://127.0.0.1:$PORT/v1/models" 2>/dev/null || true)
  code=${out##*$'\n'}; body=${out%$'\n'*}
  if [[ $code == 401 ]] && jq -e '.error.type=="authentication_error" and .error.message=="invalid or missing API key"' <<<"$body" >/dev/null 2>&1; then printf gateway; else printf other; fi
}
USAGE_FILE_NAME=usage.jsonl
usage_note() { # usage_note <prompt-tokens> <completion-tokens> [recipe]: one line per request the plugin itself made through a gateway
  state_dir; printf '{"t":%s,"prompt":%s,"completion":%s,"recipe":"%s"}\n' "$(date -u +%s)" "${1:-0}" "${2:-0}" "${3:-}" >>"$STATE/$USAGE_FILE_NAME"
}
usage_today() { # usage_today <recipe> -> completion tokens that model served in the last 24 h
  local f="$STATE/$USAGE_FILE_NAME"; [[ -s $f ]] || { printf 0; return; }
  jq -s --arg id "$1" --argjson now "$(date -u +%s)" '[.[]|select(type=="object" and .recipe==$id and .t>=$now-86400)|.completion]|add//0' "$f" 2>/dev/null || printf 0
}

# models_json <ledger> -> every slot with what reality says about it
models_json() {
  local ledger=$1 id s port engine gateway e g served answering engine_up mstate note out='[]' busy_id apis
  busy_id=$(jq -r 'if .op.pid > 0 then .op.recipeId else "" end' <<<"$ledger")
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    s=$(jq -c --arg id "$id" '.slots[$id]' <<<"$ledger"); port=$(jq -r .port <<<"$s"); engine=$(jq -r .engine <<<"$s"); gateway=$(jq -r .gateway <<<"$s")
    served=""; answering=false; engine_up=false; note=""
    if docker_direct; then
      e=$(live "$engine" || true); [[ $e == "true|1|"* ]] && engine_up=true
      if $engine_up && [[ $(live "$gateway") == "true|1|"* ]]; then
        served=$(PORT=$port api models 2 2>/dev/null | jq -r '.data[0].id // empty' || true); [[ -n $served ]] && answering=true
      fi
    else # docker would prompt: the gateway answering is the evidence
      served=$(PORT=$port api models 2 2>/dev/null | jq -r '.data[0].id // empty' || true)
      [[ -n $served ]] && { answering=true; engine_up=true; }
    fi
    if [[ $busy_id == "$id" ]]; then mstate=$(jq -r .op.name <<<"$ledger")
    elif $answering && [[ $(jq -r '(.accepted // "") | tostring' <<<"$s") != "" ]]; then mstate=ready   # verified
    elif $answering; then mstate=error; note="never verified; press Start"   # a worker died between the gateway answering and acceptance
    elif $engine_up; then mstate=error; note="the gateway is not answering; press Start or Stop"
    elif [[ -n $busy_id ]]; then mstate=stopped   # set aside while another Start runs
    else mstate=stopped; note="stopped outside the plugin; press Start or Stop"; fi
    apis=$(jq -c '.accepted.apis // []' <<<"$s")
    out=$(jq -c --argjson s "$s" --arg id "$id" --arg st "$mstate" --arg note "$note" --arg served "$served" --argjson agents "$(agents_json "$apis")" --argjson share "$(share_state "$port")" \
      --argjson rec "$(cat "$STATE/slots/$id.json" 2>/dev/null || recipe_by_id "$id")" --argjson today "$(usage_today "$id")" \
      '. + [{recipeId:$id, name:($s.name // $id), port:$s.port, endpoint:("http://127.0.0.1:"+($s.port|tostring)+"/v1"), keys:($s.keys // []), cards:(($s.keys // []) | length),
             state:$st, note:$note, servedModel:(if $served != "" then $served else ($s.accepted.servedModel // "") end), apis:($s.accepted.apis // []),
             caps:(($rec.capabilities // {}) | {chat, vision, video, tools, reasoning}),
             ctxTokens:($rec.serving.ctxTokens // 0), kvTokens:(if ($rec.serving.kvTokens // 0) > 0 then $rec.serving.kvTokens else ($rec.serving.ctxTokens // 0) end), tokensToday:$today,
             decodeTps:($s.accepted.tps // 0), prefillTps:($s.accepted.prefillTps // 0), acceptedAt:($s.accepted.at // ""), startedAt:($s.startedAt // ""),
             launchable:$agents.launchable, shareUrl:(if $share.active then $share.url else "" end), engine:$s.engine, gateway:$s.gateway}]' <<<"$out")
  done < <(jq -r '.slots | keys[]' <<<"$ledger")
  printf '%s' "$out"
}

snapshot_write() {
  state_dir
  [[ -f $LEDGER ]] && jq -e 'has("share")' "$LEDGER" >/dev/null 2>&1 && lwrite 'del(.share)'   # a ledger from before 4.1 carried the key: scrub it wherever it is met
  local ledger match rec hw_id reason state="" note="" pid busy=false
  ledger=$(lread); match=$(match_hardware); hw_id=$(jq -r .hardwareId <<<"$match"); reason=$(jq -r .reason <<<"$match")
  rec=$(recipe_for "$hw_id"); [[ -n $rec ]] && rec=$(jq -c --argjson m "$match" '. + {gpuIndex:$m.gpu.index, match:{backend:$m.gpu.backend}}' <<<"$rec")
  pid=$(busy_pid); [[ -n $pid ]] && busy=true
  $busy || ledger=$(lread)   # a worker that finished between the two reads has already cleared its op: read again before calling it vanished
  if ! $busy && [[ $(jq -r .op.pid <<<"$ledger") -gt 0 ]]; then # the op's worker is gone without a word (killed): say so, once
    log "error: worker $(jq -r .op.pid <<<"$ledger") vanished during $(jq -r .op.name <<<"$ledger")"
    lwrite '.error=$e | .op={name:"",recipeId:"",pid:0,startedAt:"",detail:"",percent:0}' --arg e "stopped unexpectedly while $(jq -r .op.detail <<<"$ledger"); press Start again (see $LOGFILE)"
    ledger=$(lread)
  fi
  # a slot whose containers are gone (removed by hand) is forgotten, unless a worker is mid-way with it
  if docker_direct && ! $busy; then
    local id; while IFS= read -r id; do
      [[ -n $id ]] || continue
      local s; s=$(jq -c --arg id "$id" '.slots[$id]' <<<"$ledger")
      exists "$(jq -r .engine <<<"$s")" || exists "$(jq -r .gateway <<<"$s")" || exists "$(jq -r .engine <<<"$s")-previous" || { log "model $id is gone (its containers were removed); forgotten"; slot_forget "$id"; rm -f "$STATE/slots/$id.json"; }
    done < <(jq -r '.slots | keys[]' <<<"$ledger")
    ledger=$(lread)
  fi
  local models; models=$(models_json "$ledger")
  # the model the card looks at: the selected recipe when it runs, else the first one running
  local focus; focus=$(jq -c --arg sel "$(jq -r '.id // ""' <<<"${rec:-null}")" '(map(select(.state != "stopped")) ) as $up | ([$up[] | select(.recipeId == $sel)] | .[0]) // $up[0] // null' <<<"$models")
  if $busy; then state=$(jq -r .op.name <<<"$ledger")
  elif jq -e 'any(.[]; .state == "ready")' >/dev/null <<<"$models"; then state=ready
  elif [[ $(jq -r .error <<<"$ledger") != "" ]]; then state=error
  elif jq -e 'any(.[]; .state == "error")' >/dev/null <<<"$models"; then state=error; note=$(jq -r '[.[] | select(.state == "error")][0].note' <<<"$models")
  else state=idle; fi
  local gate=""; [[ -n $rec ]] && gate=$(gate_reason "$rec")
  local driver_min driver_have; driver_have=$(jq -r .driver <<<"$match"); driver_min=$(jq -r '.minDriver // ""' <<<"${rec:-null}")
  [[ -n $rec && -z $gate ]] && ! driver_ok "$driver_have" "$driver_min" && gate="needs NVIDIA driver $driver_min or newer (have ${driver_have:-none})"
  # every recipe a detected card type has, with its disk state and the cards it claims (a recipe
  # without a `cards` count claims one card of its own type)
  local recs='[]' h r od all
  while IFS= read -r h; do
    [[ -n $h ]] || continue
    all=$(recipes_for "$h")
    while IFS= read -r r; do
      [[ -n $r ]] || continue
      od=$(recipe_on_disk "$r"); local pb=0; [[ $od == false ]] && pb=$(weights_partial_bytes "$r")
      recs=$(jq -c --argjson r "$r" --arg h "$h" --argjson od "$od" --argjson pb "${pb:-0}" '. + [{id:$r.id, name:$r.model.name, engine:$r.engine, sizeGb:($r.model.sizeGb//0), precision:($r.model.precision//""),
        ctxTokens:($r.serving.ctxTokens//0), kvTokens:(if ($r.serving.kvTokens // 0) > 0 then $r.serving.kvTokens else ($r.serving.ctxTokens // 0) end),
        caps:(($r.capabilities // {}) | {chat, vision, video, tools, reasoning}),
        onDisk:$od, partialBytes:$pb, hardwareId:$h, cards:($r.cards//1), claims:($r.claims // {($h):($r.cards//1)})}]' <<<"$recs")
    done < <(jq -c '.[]' <<<"$all")
  done < <(jq -r '[.gpus[].hardwareId|select(.!="")]|unique[]' <<<"$match")
  # the first recipe of each card is the recommended one; a recipe that runs says so
  recs=$(jq -c --argjson models "$models" 'reduce .[] as $r ([]; if any(.[]; .hardwareId==$r.hardwareId) then . + [$r + {recommended:false}] else . + [$r + {recommended:true}] end)
    | map(.id as $rid | . + {running: (([$models[] | select(.recipeId == $rid and .state != "stopped")] | length) > 0)})' <<<"$recs")
  local fport listener=none; fport=$(jq -r '.port // 0' <<<"$focus"); (( fport > 0 )) || fport=$PORT
  [[ $(jq -r 'if . == null then "none" else .state end' <<<"$focus") == none ]] && listener=$(PORT=$fport port_listener); local pbusy=false; [[ $listener == other ]] && pbusy=true
  local claim='{"indexes":[],"backends":[],"keys":[],"short":""}'; [[ -n $rec ]] && claim=$(claimed_indexes "$rec" "$match")
  local fapis; fapis=$(jq -c '.apis // []' <<<"$focus")
  jq -nc --argjson l "$ledger" --argjson rec "${rec:-null}" --argjson match "$match" --arg state "$state" --arg reason "$reason" --arg gate "$gate" \
    --arg hw "$hw_id" --argjson focus "$focus" --argjson models "$models" --argjson agents "$(agents_json "$fapis")" --argjson share "$(share_state "$fport")" \
    --arg t "$(now)" --arg note "$note" --argjson recs "$recs" --argjson pbusy "$pbusy" --arg listener "$listener" --argjson claim "$claim" --argjson port "$fport" \
    --arg reg "$(registry_commit)" --arg rsrc "$(recipes_source)" --arg rgen "$(recipes_generated "$RECIPES")" --arg rchk "$(cat "$STATE/recipes.checked" 2>/dev/null || printf 0)" --arg rurl "$RECIPES_URL" '
    def short: gsub("^(NVIDIA GeForce |NVIDIA |Intel |AMD Radeon |AMD )";"");
    ($recs | map(select(.id==($rec.id // ""))) | .[0]) as $sel
    | ([$models[] | select(.state != "stopped") | .keys[]]) as $busyKeys
    | ($match.gpus | group_by([.backend, .product, .vramGb]) | map(
        (.[0]) as $g | length as $n | ([.[] | select(.key as $k | $busyKeys | index($k))] | length) as $used
        | {hardwareId:$g.hardwareId, backend:$g.backend, product:$g.product, name:($g.product|short), vramGb:$g.vramGb, count:$n,
           totalGb:(($g.vramGb//0)*$n), keys:map(.key), chosen:(map(.chosen)|any),
           recipe:($recs|map(select(.hardwareId==$g.hardwareId))|.[0] // null),
           claimed:$used, idle:($n-$used)})
        | sort_by(-(.totalGb//0), .name)) as $cards
    | (if $gate!="" then ("recipe refused: "+$gate)
       elif $rec==null then $reason
       elif $claim.short != "" then $claim.short
       elif $pbusy then ("port \($port) is in use by something else")
       else "" end) as $why
    | {schemaVersion:"omarchy-local-ai/snapshot/10", updatedAt:$t, state:$state, error:(if $l.error!="" then $l.error else $note end),
       operation:{name:$l.op.name, recipeId:$l.op.recipeId, detail:$l.op.detail, percent:$l.op.percent, startedAt:$l.op.startedAt,
         expectedSeconds:(if $l.op.name=="starting" then ($l.lastStartSeconds//0) else 0 end)},
       hardwareId:$hw, gpus:$match.gpus, registry:$reg,
       registryFile:{source:$rsrc, generatedAt:$rgen, checkedAt:($rchk|tonumber), refresh:($rurl!="")},
       reason:$why,
       running:(if $focus == null then null else {recipeId:$focus.recipeId, name:$focus.name, cards:$focus.cards, port:$focus.port, state:$focus.state} end),
       models:$models, apis:($focus.apis // []), agents:$agents, share:$share,
       cards:$cards, recipes:$recs,
       selected:(if $sel==null then null else {recipeId:$sel.id, name:$sel.name, hardwareId:$sel.hardwareId, cards:$sel.cards, claims:$sel.claims, indexes:$claim.indexes, keys:$claim.keys, onDisk:$sel.onDisk, partialBytes:$sel.partialBytes, sizeGb:$sel.sizeGb, running:$sel.running} end),
       port:{number:$port, busy:$pbusy, listener:$listener}}' >"$SNAPSHOT.tmp.$$" && mv "$SNAPSHOT.tmp.$$" "$SNAPSHOT" || { rm -f "$SNAPSHOT.tmp.$$"; return 1; }   # a failed derivation leaves no stray file behind
}
