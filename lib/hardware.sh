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
  jq -nc --argjson n "$nvidia" --argjson i "$(intel_gpus)" --argjson a "$(amd_gpus)" --argjson p "$(amd_npus)" --arg d "$driver" '{gpus:($n+$i+$a+$p),driver:$d}'
}

# Intel Arc Pro B70 (Battlemage G31, PCI 8086:e223): one entry per card that has a render node.
# Found by the PCI vendor:device id, so the card never vanishes when the host's pci.ids is too old
# to print the marketing name.
INTEL_B70_IDS='8086:e223'
intel_gpus() {
  command -v lspci >/dev/null 2>&1 || { printf '[]'; return; }
  local dri="${OMARCHY_AI_DRI_PATH:-/dev/dri/by-path}" a idx=0 out='[]' metrics='{}'
  [[ -d /sys/bus/pci/drivers/xe && -z ${OMARCHY_AI_DRI_PATH:-} ]] && metrics=$(deadline 8 python3 "$HERE/../lib/intel-metrics.py" "$STATE" 2>/dev/null || printf '{}')
  while IFS= read -r a; do
    [[ -n $a && -e "$dri/pci-$a-render" ]] || continue
    out=$(jq -c --argjson i "$idx" --argjson t "$(intel_temp "$a")" --argjson m "$metrics" --arg pci "$a" '.+[{backend:"intel-xpu",index:$i,product:"Intel Arc Pro B70",totalMiB:32768,usedMiB:null,freeMiB:null,tempC:$t,utilPct:null} + (($m[$pci] // {}) | del(.totalMiB,.activity))]' <<<"$out")
    idx=$((idx+1))
  done < <(lspci -Dnn -d "$INTEL_B70_IDS" 2>/dev/null | awk '{print $1}' | sort -u)
  printf '%s' "$out"
}

intel_temp() { # intel_temp <pci-address> -> package temperature in °C from the xe hwmon, or null
  local h f; for h in /sys/bus/pci/devices/"$1"/hwmon/hwmon*; do
    for f in "$h"/temp*_label; do [[ -f $f && $(cat "$f" 2>/dev/null) == pkg ]] && { awk '{printf "%d", $1/1000}' "${f%_label}_input" 2>/dev/null; return; }; done
  done; printf null
}

amd_smi_bin() {
  [[ -n ${OMARCHY_AI_AMD_SMI:-} ]] && { printf '%s\n' "$OMARCHY_AI_AMD_SMI"; return; }
  command -v amd-smi 2>/dev/null && return
  [[ -z ${OMARCHY_AI_NO_HOST_AMD:-} && -x /opt/rocm/bin/amd-smi ]] && printf '%s\n' /opt/rocm/bin/amd-smi
}

rocm_smi_bin() {
  [[ -n ${OMARCHY_AI_ROCM_SMI:-} ]] && { printf '%s\n' "$OMARCHY_AI_ROCM_SMI"; return; }
  command -v rocm-smi 2>/dev/null && return
  [[ -z ${OMARCHY_AI_NO_HOST_AMD:-} && -x /opt/rocm/bin/rocm-smi ]] && printf '%s\n' /opt/rocm/bin/rocm-smi
}

amd_render_node_for_bdf() {
  local bdf=$1 node
  [[ -n $bdf ]] || return 1
  node=$(readlink -f "/dev/dri/by-path/pci-$bdf-render" 2>/dev/null || true)
  [[ $node =~ ^/dev/dri/renderD[0-9]+$ ]] || return 1
  printf '%s' "$node"
}

amd_gpus_from_amd_smi() {
  local smi static metric out
  smi=$(amd_smi_bin) || return 1
  [[ -n $smi ]] || return 1
  static=$("$smi" static --json 2>/dev/null) || return 1
  [[ -n $static ]] || return 1
  metric=$("$smi" metric --mem-usage --json 2>/dev/null) || metric='{}'
  out=$(jq -nc --argjson s "$static" --argjson m "$metric" '
    ($m.gpu_data // []) as $md
    | [($s.gpu_data // [])[]
        | . as $g
        | ([$md[]? | select(.gpu==$g.gpu)] | .[0] // {}) as $u
        | select(($g.asic.market_name // "") != "")
        | {
            backend:"amd-rocm",
            index:($g.gpu|tonumber),
            product:$g.asic.market_name,
            totalMiB:($g.vram.size.value // $u.mem_usage.total_vram.value // 0),
            usedMiB:($u.mem_usage.used_vram.value // null),
            freeMiB:($u.mem_usage.free_vram.value // null),
            bdf:($g.bus.bdf // null),
            renderNode:null
          }]') || return 1
  printf '%s' "$out"
}

amd_gpus_from_rocm_smi() {
  local smi raw i=0 out='[]' product bytes used card bdf
  smi=$(rocm_smi_bin) || return 1
  [[ -n $smi ]] || return 1
  raw=$(deadline 10 "$smi" --showproductname --showmeminfo vram --csv 2>/dev/null) || return 1
  [[ -n $raw ]] || return 1
  # rocm-smi CSV column order varies across versions; Card Vendor may carry an embedded comma that
  # breaks naive IFS parsing. Read the header row to find the field indices we need by name — the
  # column names themselves are stable across versions. awk emits tab-separated so bash's IFS
  # splits cleanly across the four fields even though Card Series contains spaces.
  while IFS=$'\t' read -r card product bytes used; do
    [[ -n $product && -n $bytes ]] || continue
    [[ $product == *Radeon* || $product == *AMD* ]] || continue
    [[ $product == AMD* ]] || product="AMD $product"
    bdf=''
    if [[ -n $card && -e /sys/class/drm/$card/device ]]; then
      bdf=$(basename "$(readlink /sys/class/drm/$card/device 2>/dev/null)" 2>/dev/null) || bdf=''
    fi
    out=$(jq -c --argjson i "$i" --arg p "$product" --argjson t "$bytes" --argjson u "${used:-0}" --arg bdf "${bdf:-}" \
      '.+[{backend:"amd-rocm",index:$i,product:$p,totalMiB:($t/1048576|floor),
            usedMiB:(if $u=="" then null else ($u/1048576|floor) end),
            freeMiB:(if $u=="" then null else (($t-$u)/1048576|floor) end),
            bdf:(if $bdf=="" then null else $bdf end),
            renderNode:null}]' <<<"$out")
    i=$((i+1))
  done < <(printf '%s\n' "$raw" | awk -F, '
    BEGIN { OFS = "\t" }
    NR==1 {
      for (i=1; i<=NF; i++) {
        if ($i == "device") dv = i
        if ($i == "Card Series") cs = i
        if ($i == "VRAM Total Memory (B)") vt = i
        if ($i == "VRAM Total Used Memory (B)") vu = i
      }
      next
    }
    NR>1 && dv && cs && vt && vu {
      card = $(dv); product = $(cs); bytes = $(vt); used = $(vu)
      if (product == "" || bytes == "") next
      print card, product, bytes, used
    }')
  printf '%s' "$out"
}

amd_gpus() {
  local out
  if out=$(amd_gpus_from_amd_smi 2>/dev/null); then
    printf '%s' "$(amd_gpus_resolve_render_nodes "$out")"; return
  fi
  if out=$(amd_gpus_from_rocm_smi 2>/dev/null); then
    printf '%s' "$(amd_gpus_resolve_render_nodes "$out")"; return
  fi
  printf '[]'
}

amd_gpus_resolve_render_nodes() { # fill renderNode per GPU from its bdf via sysfs readlink
  local in=$1
  [[ -n $in && $in != "[]" ]] || { printf '%s' "$in"; return; }
  while IFS=$'\t' read -r bdf idx; do
    [[ -n $bdf && -n $idx ]] || continue
    local node; node=$(amd_render_node_for_bdf "$bdf" 2>/dev/null) || node=''
    local sys="${OMARCHY_AI_SYSFS_ROOT:-/sys}/bus/pci/devices/$bdf" used=null total=null util=null temp=null f
    [[ -r $sys/mem_info_vram_used ]] && used=$(awk '{print $1/1048576}' "$sys/mem_info_vram_used")
    [[ -r $sys/mem_info_vram_total ]] && total=$(awk '{print $1/1048576}' "$sys/mem_info_vram_total")
    [[ -r $sys/gpu_busy_percent ]] && util=$(cat "$sys/gpu_busy_percent")
    for f in "$sys"/hwmon/hwmon*/temp1_input; do [[ -r $f ]] && { temp=$(awk '{print $1/1000}' "$f"); break; }; done
    in=$(jq -c --argjson i "$idx" --arg n "$node" --argjson used "$used" --argjson total "$total" --argjson util "$util" --argjson temp "$temp" \
      '[.[] | if .index == $i then . + {renderNode:(if $n!="" then $n else .renderNode end),
        usedMiB:($used // .usedMiB), totalMiB:($total // .totalMiB),
        freeMiB:(if $used!=null and $total!=null then $total-$used else .freeMiB end), utilPct:$util,tempC:$temp} else . end]'  <<<"$in")
  done < <(jq -r '.[] | "\(.bdf // empty)\t\(.index)"' <<<"$in")
  printf '%s' "$in"
}

# normalize a product name the way the registry export does, so a match is a string compare
norm() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/nvidia|geforce|intel|amd|radeon|generation|workstation|edition|[0-9]+gb|[^a-z0-9]//g'; }

# AMD Ryzen AI NPU (XDNA2, PCI 1022:17f0): one entry when the accel node is there.
# Product comes from xrt-smi when it names the silicon (Krackan, Strix Halo, …);
# otherwise a generic name that still matches a recipe's names[] after norm.
AMD_NPU_IDS='1022:17f0'
amd_npus() {
  local accel="${OMARCHY_AI_ACCEL_PATH:-/dev/accel/accel0}"
  [[ -e $accel ]] || { printf '[]'; return; }
  command -v lspci >/dev/null 2>&1 || { printf '[]'; return; }
  local a; a=$(lspci -Dnn -d "$AMD_NPU_IDS" 2>/dev/null | awk '{print $1}' | head -1)
  [[ -n $a ]] || { printf '[]'; return; }
  local product="AMD Ryzen AI NPU" total=16384 exam=""
  exam=$(deadline 8 xrt-smi examine 2>/dev/null || true)
  if grep -qi 'strix halo' <<<"$exam"; then product="AMD NPU Strix Halo"; total=32768
  elif grep -qi krackan <<<"$exam"; then product="AMD NPU Krackan"; total=16384
  elif grep -qi strix <<<"$exam"; then product="AMD NPU Strix"; total=16384
  fi
  jq -nc --arg p "$product" --argjson t "$total" '[{backend:"amd-npu",index:0,product:$p,totalMiB:$t,usedMiB:null,freeMiB:null,tempC:null,utilPct:null}]'
}

driver_ok() { # driver_ok <have> <min>  (dotted versions; empty min means no requirement)
  [[ -z $2 ]] && return 0
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]
}
