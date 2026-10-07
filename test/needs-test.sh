#!/bin/bash
# A recipe that keeps weights in system RAM and on an NVMe drive (its `needs`) is offered only where the machine has
# them: the snapshot says why a recipe does not fit, the card's pick and a group skip it, and run refuses it. RAM comes
# from a meminfo file, free space and the drive from df and lsblk, all shimmed; a recipe without `needs` is unchanged.

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf '%s\n' "${2:-}" >&2; printf 'not ok - %s\n' "$1" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP/home XDG_RUNTIME_DIR=$TMP/run MEMINFO=$TMP/meminfo
mkdir -p "$HOME" "$TMP/bin" "$TMP/plugin/bin" "$TMP/plugin/lib"
cp "$ROOT/bin/omarchy-local-ai" "$TMP/plugin/bin/"
cp "$ROOT/lib/access.sh" "$TMP/plugin/lib/"
cp "$ROOT/manifest.json" "$TMP/plugin/"
CLI=$TMP/plugin/bin/omarchy-local-ai
sed -i "s|CATALOG=\$HOME/.cache/omarchy/local-ai/v3/recipes.json|CATALOG=$TMP/catalog.json|" "$CLI"
# the daemon's socket, reachable unless a case says otherwise
export OMARCHY_DOCKER_SOCKET=$TMP/docker.sock
: >"$OMARCHY_DOCKER_SOCKET"
MODELS=$HOME/.cache/omarchy/local-ai/models
PIN=ghcr.io/x/engine@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
shim() { printf '#!/bin/bash\n%s\n' "$2" >"$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

# An RTX 3090: first an offload recipe (96 GB of RAM, 120 GB of disk on NVMe), then one without `needs`; a two-card
# group of each, the offload one first
recipes() {
  jq -nc --arg img "$PIN" '
    def r($id; $w): {id: $id, name: $id, family: "qwen", format: "EXL3", sizeGb: 1, cards: 1, image: $img, servedName: "s",
      weights: [{repository: ("test/" + $w), revision: ("0" * 40), layout: "dir", mountPath: "/models", dir: $w, files: ""}],
      launch: {arguments: [], environment: {}, port: 8000, shm: ""}, serving: {ctxTokens: 32768}, capabilities: {}};
    def big: {needs: {host_ram_gb: 96, disk_gb: 120, fast_storage: "nvme"}, format: "EXL3 · 3.05 bpw, vision (experts in RAM, n-gram table on NVMe)"};
    {schemaVersion: "omarchy-local-ai/recipes/2", registryCommit: ("d" * 40), gateway: {image: ("ghcr.io/x/gateway@sha256:" + ("b" * 64))},
     hardware: {"rtx-3090-24gb": {match: {backend: "nvidia", vramGb: 24, names: ["rtx3090"]}, recipes: [
       r("big"; "big") + big, r("small"; "small"), r("big-tp2"; "big") + big + {cards: 2}, r("small-tp2"; "small") + {cards: 2}]}}}' \
    >"$TMP/plugin/recipes.json"
}
# host <available RAM GB> <free disk GB> <lsblk -s of the filesystem's device, rows "TYPE ROTA TRAN" joined by |>
host() {
  printf 'MemTotal:       %d kB\nMemAvailable:   %d kB\n' $((512 * 976563)) $(($1 * 976563)) >"$MEMINFO"
  shim df "printf 'Filesystem Avail\n/dev/mapper/root %s\n' $(($2 * 1000000000))"
  shim lsblk "printf '%s\n' '${3//|/"' '"}'"
}
unfit() { jq -r --arg id "$1" '[.kinds[].models[], .kinds[].groups[]] | map(select(.id == $id))[0].unfit' "$TMP/snap.json"; }
view() {
  node -e 'const fs = require("fs"), vm = require("vm"), c = {}; vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8"), c)
    const s = JSON.parse(fs.readFileSync(process.argv[2], "utf8")), v = c.build(s, {view: process.argv[3], id: process.argv[4] || "", open: process.argv[5] || "", key: "", problem: ""})
    console.log(JSON.stringify(v.rows))' "$ROOT/Model.js" "$TMP/snap.json" "$@"
}

shim nvidia-smi 'printf "0, NVIDIA GeForce RTX 3090, 24576, 300, 41\n1, NVIDIA GeForce RTX 3090, 24576, 300, 38\n"'
# The CLI falls back to /opt/rocm/bin/amd-smi, so absence from PATH no longer
# keeps a host's real AMD card out of the sandbox; pin an empty report.
shim amd-smi 'echo "{\"gpu_data\":[]}"'
shim omarchy-cmd-present 'command -v "$1" >/dev/null'
shim omarchy-setup-security-sudoless-docker 'exit 0'
shim getent '[[ $1 == group ]] && echo "docker:x:998:$(id -un)" || echo "$2:x:1000:1000::/home/$2:/bin/bash"'
shim lspci 'exit 0'
shim ss 'exit 0'
shim docker 'case $1 in ps) ;; info) echo "{\"nvidia\":{}}" ;; *) exit 1 ;; esac'
! command -v node >/dev/null || ln -s "$(command -v node)" "$TMP/bin/node"
export PATH=$TMP/bin:/usr/bin:/bin
recipes

# omarchy's own layout: btrfs on LUKS (/dev/mapper/root) on a partition of an NVMe drive
NVME_CRYPT='crypt 0 |part 0 nvme|disk 0 nvme'
host 256 500 "$NVME_CRYPT"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -c '.host' "$TMP/snap.json") == '{"ramGb":512,"freeRamGb":256,"diskFreeGb":500,"disk":"nvme"}' ]] || fail "host" "$(jq -c .host "$TMP/snap.json")"
[[ -z $(unfit big) && -z $(unfit big-tp2) && -z $(unfit small) ]] || fail "fit" "$(jq -c .kinds "$TMP/snap.json")"
pass "a machine with the RAM, the disk and an NVMe drive under LUKS fits the offload recipe"
if command -v node >/dev/null; then
  [[ $(view home | jq -r '[.[] | select(.type == "slot") | .run.action] | join(" ")') == "run|big|nvidia:0 run|big|nvidia:1 run|big-tp2|nvidia:0,nvidia:1" ]] ||
    fail "fit picks" "$(view home)"
  pass "and the card and its group are offered it first, as the registry orders them"
  # a Config row says whether its model fits; the offload one's page names its RAM beside a format without its detail
  rows=$(view kind rtx-3090-24gb)
  [[ $(jq -r 'map(select(.type == "opt") | .value) | join("|")' <<<"$rows") == "+96 GB RAM|fits" ]] || fail "config rows" "$rows"
  pass "a Config row says whether its model fits, and an offload recipe the RAM it takes"
fi

host 64 500 "$NVME_CRYPT"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs 96 GB RAM, you have 64" && -z $(unfit small) ]] || fail "RAM short" "$(unfit big)"
pass "too little free RAM: needs 96 GB RAM, you have 64"
if command -v node >/dev/null; then
  [[ $(view home | jq -r '[.[] | select(.type == "slot") | .run.action] | join(" ")') == "run|small|nvidia:0 run|small|nvidia:1 run|small-tp2|nvidia:0,nvidia:1" ]] ||
    fail "unfit skipped" "$(view home)"
  rows=$(view kind rtx-3090-24gb)
  jq -e 'map(select(.type == "opt")) | .[0] == {type: "opt", label: "big", value: "needs 96 GB RAM", on: false, off: true, action: ""}
    and .[1].on and .[1].action == "model|small"' <<<"$rows" >/dev/null || fail "config" "$rows"
  jq -e 'any(.[]; .type == "acts" and .items[0].action == "run|small|nvidia:0")' <<<"$rows" >/dev/null || fail "config run" "$rows"
  pass "the card's pick and its group skip it; Config shows it with the reason and cannot choose it"
fi
"$CLI" run big nvidia:0 2>"$TMP/err" && fail "an unfit run started"
grep -qx "local-ai: big needs 96 GB RAM, you have 64" "$TMP/err" || fail "run reason" "$(cat "$TMP/err")"
[[ ! -d $HOME/.local/state/omarchy/local-ai/deploy/big ]] || fail "unfit run claimed the card"
pass "run refuses it with the same reason, before claiming a card"

host 256 54 "$NVME_CRYPT"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs 120 GB free disk, you have 54" ]] || fail "disk short" "$(unfit big)"
mkdir -p "$MODELS/test--big@000000000000/big" && : >"$MODELS/test--big@000000000000/big/.verified"
"$CLI" snapshot >"$TMP/snap.json"
[[ -z $(unfit big) ]] || fail "downloaded weights" "$(unfit big)"
rm -rf "$MODELS"
mkdir -p "$MODELS/test--big@000000000000/big" && truncate -s 60G "$MODELS/test--big@000000000000/big/model.safetensors.part"
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs 120 GB free disk, you have 54" ]] || fail "partial download short" "$(unfit big)"
truncate -s 10G "$MODELS/test--big@000000000000/big/model-2.safetensors"
"$CLI" snapshot >"$TMP/snap.json"
[[ -z $(unfit big) ]] || fail "partial download" "$(unfit big)"
rm -rf "$MODELS"
pass "too little free disk: needs 120 GB free disk, you have 54; it fits once what is left of its weights does, or they are checked"

host 256 500 'disk 0 sata'
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs the models folder on an NVMe drive" ]] || fail "SATA SSD" "$(unfit big)"
host 256 500 'lvm 0 |part 1 sata|disk 1 sata'
"$CLI" snapshot >"$TMP/snap.json"
[[ $(jq -r .host.disk "$TMP/snap.json") == hdd && $(unfit big) == "needs the models folder on an NVMe drive" ]] || fail "HDD" "$(jq -c .host "$TMP/snap.json")"
host 256 500 'lvm 0 |part 0 nvme|disk 0 nvme|part 1 sata|disk 1 sata'
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs the models folder on an NVMe drive" ]] || fail "LVM across NVMe and a disk" "$(unfit big)"
pass "a SATA SSD, a hard disk, or an LVM volume that spans one is not NVMe"

host 16 10 'disk 1 sata'
"$CLI" snapshot >"$TMP/snap.json"
[[ $(unfit big) == "needs 96 GB RAM, you have 16; needs 120 GB free disk, you have 10; needs the models folder on an NVMe drive" && -z $(unfit small) ]] ||
  fail "every reason" "$(unfit big)"
pass "every reason is given at once, and a recipe without needs fits anywhere"

# every model of the card unfit: the card says why, is not offered to run, and its page has no Run
jq '.hardware[].recipes |= map(. + {needs: {host_ram_gb: 96, disk_gb: 1}})' "$TMP/plugin/recipes.json" >"$TMP/r" && mv "$TMP/r" "$TMP/plugin/recipes.json"
"$CLI" snapshot >"$TMP/snap.json"
if command -v node >/dev/null; then
  [[ $(view gpus | jq -r '[.[] | select(.type == "slot") | "\(.run // "none") \(.note)"] | unique | join(",")') == "none needs 96 GB RAM, you have 16" ]] ||
    fail "all unfit" "$(view gpus)"
  [[ $(view home | jq -r '[.[] | select(.type == "slot")] | length') == 0 ]] || fail "all unfit home" "$(view home)"
  rows=$(view kind rtx-3090-24gb)
  jq -e '(any(.[]; .type == "acts") | not) and any(.[]; .type == "error" and .label == "needs 96 GB RAM, you have 16")' <<<"$rows" >/dev/null ||
    fail "all unfit page" "$rows"
  pass "a card with no model that fits is not offered to run; its row and page say why"
else
  echo "ok - the view model skips unfit recipes # SKIP node is not installed"
fi
