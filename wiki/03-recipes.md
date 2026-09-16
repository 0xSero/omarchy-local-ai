# 3 — Recipes, hardware matching, and the gate

`recipes.json` is data. It is the only thing the registry repository and this plugin share, and every
field of it is re-checked at launch.

## File shape

```jsonc
{
  "schemaVersion": "omarchy-local-ai/recipes/1",
  "registryCommit": "<40 hex>",          // the registry commit this file was exported from
  "generatedAt": "2026-09-16T12:24:33Z", // the freshness key for the refresh
  "gateway": { "image": "ghcr.io/0xsero/gateway@sha256:…", "provenance": {…} },
  "assets": { "<file>": "<contents>" },  // config files recipes mount, written out at launch
  "hardware": {
    "<hardware-id>": {
      "match": { "backend": "nvidia|intel-xpu", "vramGb": 24, "names": ["rtx4090"], "name": "rtx-4090-24gb" },
      "recipe":  { … },                  // the recommended one
      "recipes": [ { … }, { … } ]        // alternates; optional
    }
  }
}
```

A recipe:

| Field | Meaning | Used for |
|---|---|---|
| `id` | `^[a-z0-9][a-z0-9-]*$` | slot key, container names, marker file name |
| `model.id` / `model.name` | display | the card |
| `model.repository` | `Owner/Repo` | the Hub download |
| `model.revision` | 40–64 hex | pinned revision; part of the marker |
| `model.servedName` | what `/v1/models` must report | acceptance; also the gateway's `MODEL` |
| `model.precision`, `model.sizeGb` | display and progress arithmetic | the card, the download ETA |
| `model.sha256`, `model.sizeBytes` | optional, for single-file GGUF | offline verification without a Hub call |
| `engine` | `tabbyapi`, `sglang`, `llama-cpp`, `vllm` | display only — the launch is described by `launch` |
| `capabilities` | `{chat, vision, video, tools, reasoning}` | which acceptance probes run, which agents can launch |
| `serving.ctxTokens`, `serving.kvTokens`, `serving.concurrency` | advertised context and KV | acceptance checks the runtime context; the card and the agents use it |
| `speed.tps` | validated decode speed | the acceptance floor is `max(3, tps/10)` |
| `weights.subdir` | where the download lands under the mount | TabbyAPI loads `<mount>/<model_name>` |
| `image.provenance`, `image.attestation` | display | how the image was built |
| `launch.image` | digest-pinned engine image | pulled, run |
| `launch.containerPort` | the engine's port inside the network | the gateway's `UPSTREAM` |
| `launch.entrypoint`, `launch.arguments`, `launch.environment` | the engine's argv | passed through |
| `launch.mounts[]` | `{source, target, read_only}` | see the mount policy below |
| `launch.shm`, `launch.ipc`, `launch.networkMode`, `launch.capAdd`, `launch.securityOpt` | shape | gated |
| `claims` / `cards` | how many cards, of which hardware ids | `claimed_indexes` |
| `minDriver` | optional minimum NVIDIA driver | `driver_ok` |
| `validated` | `{harness, acceptedAt}` | provenance, display |

### Mount policy

A mount `source` must be exactly one of:

| Source | Resolved | Rule |
|---|---|---|
| `${MODEL_ROOT}/<dir>` | `<MODEL_ROOT>/<dir>` | must be **read-only**; must stay under the canonical `${MODEL_ROOT}`'s parent (`gate_reason` calls that `plug_root`) |
| `${CACHE_ROOT}/<dir>` | likewise | same rule |
| `~/.cache/huggingface[/…]` | `$HOME/.cache/huggingface` | must stay under the canonical HF home |
| `asset/<file>` | `$STATE/assets/<file>` | `<file>` must be a single path segment with no `..`, and must exist in `recipes.json`'s `assets` |
| `/dev/dri/by-path` | as-is | the Intel render-node indirection |

Anything else, any `..` anywhere, or a `${…}` placeholder other than `${MODEL_ROOT}`/`${CACHE_ROOT}`
is refused. Model weights must be mounted read-only; a `~/.cache/huggingface` mount may be read-write
because the engine downloads into it.

## Hardware detection

`hardware_json` (`lib/hardware.sh`) emits:

```json
{"gpus":[{"backend":"nvidia","index":0,"product":"NVIDIA GeForce RTX 4090","totalMiB":24564,
          "usedMiB":300,"freeMiB":24264,"tempC":41,"utilPct":3}],
 "driver":"580.65.06"}
```

**NVIDIA.** One `nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,driver_version,temperature.gpu,utilization.gpu`
call, under a 10-second `timeout`, supplies both the per-card rows and the driver version (column 6
of row 1). No `nvidia-smi`, no NVIDIA rows.

**Intel Arc Pro B70** (Battlemage G31, PCI `8086:e223`). Found by PCI id via `lspci -Dnn`, never by
marketing name, because a host's `pci.ids` may be older than the card. One entry per card **that has
a render node** under `/dev/dri/by-path` (`pci-<addr>-render`); a B70 with no render node is not
listed. VRAM is declared as 32768 MiB (it is not queryable the same way), `usedMiB`/`freeMiB` are
null, and the package temperature comes from the `xe` hwmon (`temp*_label == "pkg"`).

`OMARCHY_AI_HARDWARE_JSON` replaces the whole detection step, and `OMARCHY_AI_DRI_PATH` relocates the
render-node directory; both are used by the suite.

## Matching a card to a hardware id

`match_hardware` (`lib/recipes.sh`) runs over the detected cards and the file's `hardware` keys:

1. the backend must be equal;
2. the detected product, passed through `norm` — lowercased, with `nvidia|geforce|intel|amd|radeon|generation|workstation|edition|<n>gb` and every non-alphanumeric removed — must appear in the
   entry's `match.names[]`;
3. `|match.vramGb × 1024 − totalMiB| ≤ 1024`, i.e. VRAM within 1 GiB (an entry declares 24 for a 24564 MiB card).

A card with no matching entry gets `hardwareId: ""` and is still listed, so the card can say
*no validated recipe for &lt;product&gt; yet*.

**Which card is used.** `OMARCHY_AI_GPU`, else `$STATE/gpu`, else automatic. A pinned key
(`<backend>:<index>`, e.g. `nvidia:1`) is honoured even when that card has no recipe — the person
asked to see it, so the reason names it. Automatic selection sorts the cards that *do* have a recipe
by `-totalMiB`, then `-freeMiB`, then device order, and takes the first. That means: the largest card
with a recipe, and among equals the one with the most free memory — a box whose first card drives the
desktop does not get its model stranded there.

## Grouping into cards, and claims

The snapshot groups detected cards by `[backend, product, vramGb]`: two identical RTX 4090s become one
entry with `count: 2`, `totalGb: 48`, and both keys. The panel renders one cell per physical card.

A recipe says how many cards it needs with `cards` (default 1) or with an explicit `claims` map
(`{ "<hardware-id>": <count>, … }`). `claimed_indexes` resolves that to device indexes:

- per claim, take the cards whose `hardwareId` equals the claim's key, **the chosen card first**, then
  device order; if fewer exist than the claim needs, `short` becomes `recipe needs N <group> cards, M detected`;
- if the resolved cards span more than one backend, `short` becomes `recipe claims cards of different backends`
  (one container cannot run across two drivers);
- everything else is refused with whatever `short` says, and the snapshot puts it in `reason`.

Two-card recipes are how the tensor-parallel entries run (two RTX 3090s, or two Arc Pro B70s):
`--gpus "device=0,2"` — quoted as one csv field, because `--gpus device=0,2` would otherwise parse as
"device 0 plus count 1" and docker refuses.

## Choosing among a card's recipes

`recipe_pick()` is `OMARCHY_AI_RECIPE`, else `$STATE/recipe-pick`, else automatic.

- `recipe_for` returns the picked alternate when it exists **and is offered**, else `.recipe`
  (the recommended one). A pick that belongs to another card is silently ignored — the card changed —
  so the recommended recipe is the fallback.
- `recipes_for` lists every recipe of a card, recommended first.
- **Offering vs gating.** A recipe is not even *offered* when it fails the shape checks a file can
  fail on its own (`OFFERED`): `networkMode` other than `bridge`, `ipc: "host"`, a non-empty `capAdd`,
  or a non-empty `securityOpt`. Such an alternate disappears from the list. The recommended recipe is
  never filtered out; it stays visible with its `gate_reason` as the card's `reason`.

## The gate: `gate_reason`

Run on the snapshot, at the start of `w_load`, and again inside every root phase. It prints one
sentence and returns non-zero, or prints nothing. Checks, in order:

| Condition | Message |
|---|---|
| `id` not `^[a-z0-9][a-z0-9-]*$` | `invalid recipe id` |
| `model.repository` not `Name/Name` | `invalid model repository` |
| `weights.subdir` not a clean relative path (or empty) | `invalid weights directory` |
| `model.servedName` contains `"`, `\` or `'` | `invalid served model name` |
| `launch.image` lacks `@sha256:<64 hex>` | `image is not digest-pinned` |
| `model.revision` not 40–64 hex | `model revision is not pinned` |
| `launch.networkMode` ≠ `bridge` | `requires <mode> networking` |
| `launch.ipc` = `host` | `requires host IPC` |
| `launch.capAdd` non-empty | `requires extra kernel capabilities` |
| `launch.securityOpt` non-empty | `requires a weakened security profile` |
| `launch.containerPort` not a number | `invalid container port` |
| an argument matches `enforce.eager`/`disable-cuda-graph` (case-insensitive) | `disallowed launch argument` |
| any string anywhere in `launch` contains a `${…}` other than the two known placeholders | `needs an unsupported placeholder` |
| the JSON cannot be parsed by the filter at all | `recipe data failed validation` |
| a mount source outside the mount policy | `mounts unsafe host path <src>` / `unsafe asset path <src>` / `asset <src> is not shipped` |
| `${MODEL_ROOT}/…` mounted read-write | `model weights must be mounted read-only` |

The two disallowed arguments are the CPU-fallback escape hatches: `enforce.eager` forces eager
execution and `disable-cuda-graph(s)` disables CUDA graphs, both of which turn a broken GPU into a
slow success.

## The file in use, and refreshing it

| Var | Default | Effect |
|---|---|---|
| `OMARCHY_AI_RECIPES` | unset | use exactly this file; disables fetching |
| `OMARCHY_AI_RECIPES_URL` | `https://raw.githubusercontent.com/0xSero/local-ai-registry/main/plugin/recipes.json` | the one fixed HTTPS origin; empty string disables fetching |
| `OMARCHY_AI_RECIPES_TTL` | `21600` (6 h) | how often `snapshot` may start a background refresh |

`recipes_select`: the explicit file if set; otherwise the **live** copy (`$STATE/recipes.json`) when it
exists, is a valid recipes file, and its `generatedAt` is strictly greater (string comparison — the
format is ISO-8601 UTC, so that is a date comparison) than the vendored file's; otherwise the
**vendored** file. `recipes_source` reports which, and the snapshot carries it as
`registryFile.source`.

`recipes_refresh`:

```
curl -fsSL --max-time 20 --max-filesize 8388608 --proto =https -o <tmp> <url>
```

then: a broken download → `recipes: could not fetch the registry (<curl error>); keeping <source>`;
a file that fails `recipes_ok_file` → `recipes: the fetched file is not a recipes file; keeping <source>`;
an older-or-equal `generatedAt` → `recipes: <source> is current (registry <sha12>, <when>)`; otherwise
it is `chmod 600`, moved to `$STATE/recipes.json`, and reported as
`recipes: updated to registry <sha12> (<when>, <n> recipes)`. Nothing else changes — the new file is
gated recipe by recipe like any other.

`recipes_autorefresh` (called by `snapshot`) starts at most one **detached** `recipes update` per TTL,
and stamps `$STATE/recipes.checked` *before* forking so concurrent snapshots do not all fetch. The
fetch is never on the card's critical path.

## `make sync`: where the file comes from

```bash
make sync REGISTRY=../local-ai-registry
# python3 <registry>/scripts/export_plugin_recipes.py --out recipes.json
```

The registry's exporter writes the file and stamps `registryCommit`. The registry's CI (and this
repo's `make check`) validate the schema, the pinned gateway image, and that `.hardware` is non-empty.
The `registryCommit` in the file must match the registry commit it was exported from; the plugin's own
history shows the stamp moving when the registry moves without any recipe content changing.