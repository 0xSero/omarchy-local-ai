#!/usr/bin/env bash
# The derived read model. Sourced; do not run.
#
# snapshot_write derives everything from the ledger + reality (owned containers, the gateway's
# /v1/models, tailscale, installed agents) + recipes.json, and rewrites $SNAPSHOT. It never edits
# the ledger. Workers call it after every step so the panel, which watches the file, updates live;
# the panel also asks for one on a slow timer so a container that died outside an op shows up.
#
# State rule: busy while the op's pid is alive; else ready when an owned engine+gateway run and
# the gateway answers; else error when the ledger has one; else starting when they run but do
# not answer yet; else idle. Reality outranks the message: a model that answers is ready even
# when the last verb was refused (the error text still shows beside it).
#
# Snapshot 8 adds what the command-stack panel renders and nothing the old panel read has moved:
#   cards      detected GPUs aggregated by identical product (2× RTX 3090 · 48 GB total), each with
#              its recipe, how many of its cards the selected recipe claims, and how many stay idle
#   recipes    every validated recipe of every detected card type (recommended first), with onDisk and its card claim
#   selected   the recipe for the chosen card, with the claims it makes on the card groups
#   running    now also carries the recipe's name and `older` (a running recipe the file no longer has)
#   port       the gateway port and whether something that is not ours listens on it
#   stats      decode and prefill speed measured at acceptance, VRAM in use, tokens served by window
#   registry*  registryCount and registryList: every hardware id the vendored file carries

recipe_on_disk() { # recipe_on_disk <recipe-json> -> true|false: weights marked complete and, where docker answers, the image pulled
  local r=$1
  if weights_present "$r" && { ! docker_direct || docker image inspect "$(jq -r .launch.image <<<"$r")" >/dev/null 2>&1; }; then printf true; else printf false; fi
}
# port_listener -> none | gateway | other. A listener is found with ss, or, without ss, by a
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
usage_note() { # usage_note <prompt-tokens> <completion-tokens>: one line per request the plugin itself made through the gateway
  state_dir; printf '{"t":%s,"prompt":%s,"completion":%s}\n' "$(date -u +%s)" "${1:-0}" "${2:-0}" >>"$STATE/$USAGE_FILE_NAME"
}
usage_windows() { # -> {hour,today,week}: completion tokens served through the gateway, summed per window
  local f="$STATE/$USAGE_FILE_NAME" now; now=$(date -u +%s)
  [[ -s $f ]] || { printf '{"hour":0,"today":0,"week":0}'; return; }
  jq -sc --argjson now "$now" '[.[]|select(type=="object")] as $u
    | {hour:([$u[]|select(.t>=$now-3600)|.completion]|add//0), today:([$u[]|select(.t>=$now-86400)|.completion]|add//0), week:([$u[]|select(.t>=$now-604800)|.completion]|add//0)}' "$f" 2>/dev/null \
    || printf '{"hour":0,"today":0,"week":0}'
}

snapshot_write() {
  state_dir
  # a ledger written by an older plugin carries the key under .share: scrub it once, here, where every path passes
  [[ -f $LEDGER ]] && jq -e 'has("share")' "$LEDGER" >/dev/null 2>&1 && lwrite 'del(.share)'
  local ledger match rec hw_id reason state="" note="" pid running_recipe="" served="" busy=false answering=false engine_up=false
  ledger=$(lread); match=$(match_hardware); hw_id=$(jq -r .hardwareId <<<"$match"); reason=$(jq -r .reason <<<"$match")
  rec=$(recipe_for "$hw_id"); [[ -n $rec ]] && rec=$(jq -c --argjson m "$match" '. + {gpuIndex:$m.gpu.index, match:{backend:$m.gpu.backend}}' <<<"$rec")
  pid=$(busy_pid); [[ -n $pid ]] && busy=true
  if ! $busy && [[ $(jq -r .op.pid <<<"$ledger") -gt 0 ]]; then # the op's worker is gone without a word (killed): say so, once
    log "error: worker $(jq -r .op.pid <<<"$ledger") vanished during $(jq -r .op.name <<<"$ledger")"
    lwrite '.error=$e | .op={name:"",recipeId:"",pid:0,startedAt:"",detail:"",percent:0}' --arg e "stopped unexpectedly while $(jq -r .op.detail <<<"$ledger"); press Start again (see $LOGFILE)"
    ledger=$(lread)
  fi
  if docker_direct; then
    local e; e=$(live "$ENGINE" || true); [[ $e == "true|1|"* ]] && { engine_up=true; running_recipe=${e#true|1|}; }
    if $engine_up && [[ $(live "$GATEWAY") == "true|1|"* ]]; then
      served=$(api models 2 2>/dev/null | jq -r '.data[0].id // empty' || true); [[ -n $served ]] && answering=true
    fi
  else # docker would prompt: the gateway answering is the evidence, and the recipe it was started from is on file
    served=$(api models 2 2>/dev/null | jq -r '.data[0].id // empty' || true)
    if [[ -n $served ]]; then answering=true; engine_up=true; running_recipe=$(jq -r '.id // ""' "$STATE/gateway.recipe.json" 2>/dev/null || true); fi
  fi
  if $busy; then state=$(jq -r .op.name <<<"$ledger")
  elif $answering && [[ $(jq -r '.accepted.recipeId // ""' <<<"$ledger") == "$running_recipe" || $(jq -r '(.accepted.recipeId // "") + .error' <<<"$ledger") == "" ]]; then state=ready   # verified, or adopted with nothing against it
  elif $answering; then state=error; note="the running model was never verified; press Start"   # a worker died between the gateway answering and acceptance
  elif [[ $(jq -r .error <<<"$ledger") != "" ]]; then state=error
  elif $engine_up; then state=error; note="the gateway is not answering; press Start or Stop"   # no worker is bringing it up
  else state=idle; fi
  # a running recipe the vendored file no longer carries (any card, recommended or alternate) is
  # still ours: it is reported as older. Whether it matches the selection is a separate question.
  local running_known=true; [[ -n $running_recipe ]] && ! recipe_known "$running_recipe" && running_known=false
  local downloaded=false; [[ -n $rec ]] && [[ $(recipe_on_disk "$rec") == true ]] && downloaded=true
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
      recs=$(jq -c --argjson r "$r" --arg h "$h" --argjson od "$od" --argjson pb "${pb:-0}" '. + [{id:$r.id, name:$r.model.name, engine:$r.engine, sizeGb:($r.model.sizeGb//0),
        ctxTokens:($r.serving.ctxTokens//0), tools:($r.capabilities.tools//false), onDisk:$od, partialBytes:$pb, hardwareId:$h, cards:($r.cards//1), claims:($r.claims // {($h):($r.cards//1)}),
        recommended:true}]' <<<"$recs")
    done < <(jq -c '.[]' <<<"$all")
  done < <(jq -r '[.gpus[].hardwareId|select(.!="")]|unique[]' <<<"$match")
  # the first recipe of each card is the recommended one
  recs=$(jq -c 'reduce .[] as $r ([]; if any(.[]; .hardwareId==$r.hardwareId) then . + [$r + {recommended:false}] else . + [$r + {recommended:true}] end)' <<<"$recs")
  local listener=none; ! $engine_up && ! $answering && listener=$(port_listener); local pbusy=false; [[ $listener == other ]] && pbusy=true
  local claim='{"indexes":[],"backends":[],"short":""}'; [[ -n $rec ]] && claim=$(claimed_indexes "$rec" "$match")
  jq -nc --argjson l "$ledger" --argjson rec "${rec:-null}" --argjson match "$match" --arg state "$state" --arg reason "$reason" --arg gate "$gate" \
    --arg hw "$hw_id" --arg served "$served" --arg rr "$running_recipe" --argjson known "$running_known" --argjson dl "$downloaded" \
    --argjson agents "$(agents_json)" --argjson share "$(share_state)" --arg reg "$(registry_commit)" --arg t "$(now)" --arg note "$note" \
    --argjson recs "$recs" --arg pick "$(recipe_pick)" --argjson pbusy "$pbusy" --arg listener "$listener" --argjson claim "$claim" --argjson port "$PORT" --argjson usage "$(usage_windows)" \
    --argjson reglist "$(jq -c '[.hardware|to_entries[]|{hardwareId:.key, card:((.value.match.name//.key)|gsub("^(NVIDIA GeForce |NVIDIA |GeForce |Intel |AMD Radeon |AMD )";"")), model:(.value.recipe.model.name//""), engine:(.value.recipe.engine//""), sizeGb:(.value.recipe.model.sizeGb//0)}]' "$RECIPES")" '
    def short: gsub("^(NVIDIA GeForce |NVIDIA |Intel |AMD Radeon |AMD )";"");
    ($recs | map(select(.id==($rec.id // ""))) | .[0]) as $sel
    | ($match.gpus | group_by([.backend, .product, .vramGb]) | map(
        (.[0]) as $g | length as $n | (if $sel==null then 0 else ($sel.claims[$g.hardwareId] // 0) end) as $need
        | {hardwareId:$g.hardwareId, backend:$g.backend, product:$g.product, name:($g.product|short), vramGb:$g.vramGb, count:$n,
           totalGb:(($g.vramGb//0)*$n), keys:map(.key), chosen:(map(.chosen)|any),
           recipe:($recs|map(select(.hardwareId==$g.hardwareId))|.[0] // null),
           claimed:([$need,$n]|min), idle:($n-([$need,$n]|min))})
        | sort_by(-(.totalGb//0), .name)) as $cards
    | (if $gate!="" then ("recipe refused: "+$gate)
       elif $rec==null then $reason
       elif $claim.short != "" then $claim.short
       elif $pbusy then ("port \($port) is in use by something else")
       else "" end) as $why
    | {schemaVersion:"omarchy-local-ai/snapshot/8", updatedAt:$t, state:$state, error:(if $l.error!="" then $l.error else $note end), lastStartSeconds:($l.lastStartSeconds//0),
       operation:{name:$l.op.name, detail:$l.op.detail, percent:$l.op.percent, startedAt:$l.op.startedAt,
         expectedSeconds:(if $l.op.name=="starting" then ($l.lastStartSeconds//0) else 0 end)},
       hardwareId:$hw, registry:$reg, gpus:$match.gpus, gpuPinned:$match.pinned,
       model:(if $rec==null then null else
         {recipeId:$rec.id, name:$rec.model.name, servedName:(if $served!="" then $served else $rec.model.servedName end),
          engine:$rec.engine, ctxTokens:$rec.serving.ctxTokens, tps:$rec.speed.tps, sizeGb:$rec.model.sizeGb, downloaded:$dl,
          endpoint:("http://127.0.0.1:"+($port|tostring)+"/v1")} end),
       reason:$why,
       running:(if $rr=="" then null else {recipeId:$rr, current:$known, older:($known|not), name:(($recs|map(select(.id==$rr))|.[0].name) // $rr),
                cards:((($recs|map(select(.id==$rr))|.[0].cards) // 1))} end),
       apis:$l.accepted.apis, agents:$agents, share:$share,
       cards:$cards, recipes:$recs, recipePinned:($pick!=""),
       selected:(if $sel==null then null else {recipeId:$sel.id, name:$sel.name, hardwareId:$sel.hardwareId, cards:$sel.cards, claims:$sel.claims, indexes:$claim.indexes, onDisk:$sel.onDisk, partialBytes:$sel.partialBytes, sizeGb:$sel.sizeGb} end),
       port:{number:$port, busy:$pbusy, listener:$listener},
       stats:{decodeTps:($l.accepted.tps//0), prefillTps:($l.accepted.prefillTps//0), validatedTps:($rec.speed.tps//0),
              vramUsedGb:(if $match.gpu==null or $match.gpu.usedMiB==null then null else (($match.gpu.usedMiB/1024*10|round)/10) end),
              vramTotalGb:(if $match.gpu==null or $match.gpu.totalMiB==null then null else (($match.gpu.totalMiB/1024)+0.5|floor) end),
              ctxTokens:($rec.serving.ctxTokens//0), tokens:$usage},
       registryCount:($reglist|length), registryList:$reglist}' >"$SNAPSHOT.tmp.$$" && mv "$SNAPSHOT.tmp.$$" "$SNAPSHOT"
}
