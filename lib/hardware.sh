#!/usr/bin/env bash
# Live GPU inventory and driver. Sourced; do not run.
# Output shape: {"gpus":[{backend,index,product,totalMiB,usedMiB,freeMiB}],"driver":"580.65.06"}

hardware_json() {
  [[ -n ${OMARCHY_AI_HARDWARE_JSON:-} ]] && { jq -c . <<<"$OMARCHY_AI_HARDWARE_JSON"; return; }
  local rows='' nvidia='[]' driver=''
  if command -v nvidia-smi >/dev/null 2>&1; then
    # one invocation answers both: per-card rows and the driver version on every row
    rows=$(deadline 10 nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,driver_version,temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || true)
    driver=$(head -1 <<<"$rows" | awk -F, '{print $6}' 2>/dev/null | tr -d ' ' || true)
  fi
  [[ -n $rows ]] && nvidia=$(jq -Rsc 'split("\n")|map(select(length>0)|split(",")|map(gsub("^ +| +$";"")))
    |map({backend:"nvidia",index:(.[0]|tonumber),product:.[1],totalMiB:(.[2]|tonumber),usedMiB:(.[3]|tonumber),freeMiB:(.[4]|tonumber),
          tempC:(.[6]|if .==null or .=="" then null else tonumber end), utilPct:(.[7]|if .==null or .=="" then null else tonumber end)})' <<<"$rows")
  jq -nc --argjson n "$nvidia" --argjson i "$(intel_gpus)" --arg d "$driver" '{gpus:($n+$i),driver:$d}'
}

# Intel Arc Pro B70 (Battlemage G31, PCI 8086:e223): one entry per card that has a render node.
# Found by the PCI vendor:device id, so the card never vanishes when the host's pci.ids is too old
# to print the marketing name.
INTEL_B70_IDS='8086:e223'
intel_gpus() {
  command -v lspci >/dev/null 2>&1 || { printf '[]'; return; }
  local dri="${OMARCHY_AI_DRI_PATH:-/dev/dri/by-path}" a idx=0 out='[]'
  while IFS= read -r a; do
    [[ -n $a && -e "$dri/pci-$a-render" ]] || continue
    out=$(jq -c --argjson i "$idx" --argjson t "$(intel_temp "$a")" '.+[{backend:"intel-xpu",index:$i,product:"Intel Arc Pro B70",totalMiB:32768,usedMiB:null,freeMiB:null,tempC:$t,utilPct:null}]' <<<"$out")
    idx=$((idx+1))
  done < <(lspci -Dnn -d "$INTEL_B70_IDS" 2>/dev/null | awk '{print $1}' | sort -u)
  printf '%s' "$out"
}

intel_temp() { # intel_temp <pci-address> -> package temperature in °C from the xe hwmon, or null
  local h f; for h in /sys/bus/pci/devices/"$1"/hwmon/hwmon*; do
    for f in "$h"/temp*_label; do [[ -f $f && $(cat "$f" 2>/dev/null) == pkg ]] && { awk '{printf "%d", $1/1000}' "${f%_label}_input" 2>/dev/null; return; }; done
  done; printf null
}

driver_ok() { # driver_ok <have> <min>  (dotted versions; empty min means no requirement)
  [[ -z $2 ]] && return 0
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}
