# 16 — History

## Versions

### 4.0.0 — 2026-09-08 (the marketplace-verified snapshot, `3f447b9`)

One validated model per GPU, one button on the bar. Agents launch-only, nothing written into user
config. Keyed sharing on the tailnet. A GPU picker. 29 NVIDIA recipes validated on rented cards, RTX
3060 through RTX 6000 Ada.

### 4.1.0 — 2026-09-12

- **Docker without the docker group.** Omarchy deliberately keeps users out of `docker`; Start, Stop
  and Share batch their docker calls into one polkit prompt through Omarchy's own agent, and the
  NVIDIA container toolkit is installed inside that prompt when missing. The card's refresh never
  touches docker in that mode.
- **The root phase trusts pkexec, not user-owned files**: the uid comes from `PKEXEC_UID`, every path
  from that user's home, and inputs are pinned by hashes on pkexec's own command line.
- Acceptance refuses a reasoning model whose thinking leaks into the answer; the Qwen TabbyAPI recipes
  enable the reasoning parser.
- Claude launched with `ANTHROPIC_AUTH_TOKEN` — the bearer form meant for gateways — after
  `ANTHROPIC_API_KEY` kept prompting for consent.
- Every failure became a sentence on the card. Ready began to require the acceptance record.
- Fixed: the root-phase env parser dropped values containing `x`, `6` or `0`, so the gateway and
  downloader ran as root behind a prompt; prompt-mode acceptance called docker as the user and
  reported a slow-loading engine as exited; a lock loser could rewrite the winner's ledger.

### 5.0.0 — 2026-09-16 (`317d619`, tagged)

- **Several models at once.** Every running model is its own engine+gateway pair on its own private
  network, first gateway on 12434, each further one on the next free port. A Start replaces only the
  models on the cards it claims and sets them aside until the new one is accepted. Ledger `2` with
  `slots`; snapshot `10` with `models[]`, `cards[].claimed`, `running`.
- **The card became three places** (home › card › model) with work and error taking the card over:
  554 lines from 702, with more on it. `ui.js` decides the rows, `Panel.qml` draws them.
- **Context and capabilities became promises.** Cards show context and chat/vision/video/tools/
  reasoning before launch; acceptance checks the advertised runtime context and exercises image and
  video input; Pi/OMP and Crush receive the recipe's real context instead of a hardcoded 128K, and
  Pi/OMP receive image support. A failed launch no longer silently retries at a smaller context.
- **Recipes became dynamic**: the vendored file is the floor; a newer copy is fetched from the
  registry, schema-checked, kept 0600, and used in its place; every recipe is still gated at launch.
- **Weights already on the machine are used**, verified file by file against the Hub tree of the
  pinned revision and adopted by reflink into the right layout.
- Two-card (tensor-parallel) recipes are offered, with `--gpus "device=…"` correctly quoted.
- A one-card recipe starts on the free card with the most memory free, and a vLLM
  `--gpu-memory-utilization` is lowered to what is actually free — a box whose first card drives the
  desktop can now start a 97%-of-card recipe at all.
- Fixed: a "downloaded" marker no longer outranks the disk (weights deleted behind it are fetched
  again, instead of launching the engine over an empty read-only mount and crash-looping it); a
  crash-looping engine is reported within seconds with its last log line instead of after an hour as
  `loading the model · 95%`.

### 5.0.1 — 2026-09-16 (`d38f8d2`, tagged)

The release that made the repository match what it ships:

- **The card moved to `ui/`** (`ui/Panel.qml`, `ui/CardRow.qml`, `ui/Orb.qml`, `ui/ui.js`) and the
  design document to `docs/design.md`; `manifest.json`'s `entryPoints.barWidget` follows.
- **Recordings, logos and the preview left the repository**, and the vision/video acceptance inputs
  became tiny base64 payloads embedded in `lib/runtime.sh` — readiness no longer needs loose media
  files, an encoder or a network.
- **A runtime-only archive.** `make bundle` packs an explicit file list into
  `dist/omarchy-local-ai-<version>.tar.gz`; `make test` unpacks it and runs both suites against its
  contents; the release workflow attaches that same tested archive; `.gitattributes` marks the
  development paths `export-ignore` so source archives carry the runtime set too.
- **Full-screen mode.** A header control (or `F11`) expands the card to the available area, and
  `Escape` returns to compact first. Home changed shape too: running models nest under the GPU group
  they hold, and an occupied GPU reads `locked` rather than naming the model inside a cell.

`CHANGELOG.md` carries the full list for both versions, including the trimmed code paths (the
single-model ledger migration, the parsed pull percent, the windowed token counters) and the reasoning
for each removal.

### 5.0.2 — 2026-09-16 (`66e200a`, tagged)

The release that gave the marketplace listing its picture and its words back. `5.0.1` had removed both,
and the marketplace reads both from the listed commit — publishing it would have replaced the v4 image
with nothing and kept a v4 paragraph under a v5 card:

- **`preview.png` is back in the repository root** — 1600×900, cut from a live capture of the v5 card
  by `docs/preview.py`. The generator finds the panel by its own background colour, so a capture at any
  resolution works, and a line that no longer fits the text column fails the build instead of clipping.
- **`manifest.json`'s `description`** is what the listing prints, and it now describes the card as it
  is: several models at once on separate GPU groups, context and capabilities stated before launch,
  agents with nothing written to config, the keyed tailnet endpoint, and the stats on the card.

### 5.0.7 — 2026-09-17

- **The listing image is the Local AI banner plus the card.** `preview.png` now opens with the dove
  banner, states the supported GPUs (NVIDIA RTX 30/40/50, RTX Ada, RTX Pro Blackwell, Intel Arc Pro
  B70), the 67 recipes across 34 cards, the agents and the tailnet share, and shows the card running
  Qwen3.8-27B on 2× RTX 3090 and on 2× Arc Pro B70. `docs/preview.py` takes the banner and two
  captures; the banner lives in `media/`.
- **The description says which GPUs.** It names the GPU families and the agents rather than
  describing the card's controls.

## The 2026-09-16 consolidation

The work had grown four copies of this repository across two machines, with `main` and `panel-v5`
forks of one another. What was done, and what is true now:

| Fact | State |
|---|---|
| Canonical checkout | `~/local-omarchy/omarchy-local-ai` (macOS), `main` |
| Compatibility path | `~/omarchy-local-ai` is a symlink to it, so `make sync`'s default `REGISTRY ?= ../local-ai-registry` resolves |
| Live plugin | `omarchy:~/.config/omarchy/plugins/sero.local-ai`, reset to `main`; it had drifted — six stale panel-v5-era files and a missing `test/ui.cjs` |
| Registry | `~/local-omarchy/local-ai-registry` |
| Removed | four duplicate clones/worktrees (two on the Mac, two on the box) and the registry's dead v4 `plugin/` tree |
| Preserved | two commits that existed only on disk, pushed as `origin/codex/recipe-catchup-256k` and `origin/v4-rebuild` |
| Evidence | today's validation material archived out of the working directories |

Two follow-ups worth knowing:

- **`panel-v5` is not merged.** Its context-retry (`fit_length`, a failed launch silently retrying at a
  smaller context) is deliberately absent from `main`: 5.0 refuses that behaviour and fails loudly
  instead. The branch is intact on `origin/panel-v5`.
- **A `test/all` fix** landed with the consolidation: `ROOT` is resolved with `pwd -P`, because the CLI
  resolves itself with `readlink -f`. A checkout reached through a symlink could otherwise fail the
  vendored-recipes assertion for a reason that has nothing to do with recipes.

While this wiki was being written, that checkout's `main` moved on: `317d619` released 5.0.0 and
`d38f8d2` released 5.0.1 — the `ui/` move, the runtime bundle, the embedded acceptance payloads and
full-screen mode. **These pages document `d38f8d2`.** Anything landed after it needs a re-read of the
pages it touches; `wiki/verify.py` fails the build when a path or a quoted message stops existing.

## Where things are, now

```
~/local-omarchy/
  local-ai-registry/        the registry (records, pipeline, published plugin/recipes.json)
  omarchy-local-ai/         this plugin, main
~/omarchy-local-ai -> ~/local-omarchy/omarchy-local-ai
omarchy:~/.config/omarchy/plugins/sero.local-ai    the live plugin
```

Branches on `origin`: `main`, `panel-v5`, `v4`, `v4-rebuild`, `codex/recipe-catchup-256k`, `stats`
(the traffic branch, written only by the daily workflow).

## Reading the design record

`docs/design.md` (called `DESIGN.md` in the repository root before 5.0.1) is the consolidated design
record: scope, every decided item with its date, the open items with recommendations, the release
contents and process. This wiki describes **what the code does**; the design record says **why it was
decided**. Where the two differ in emphasis, that is the reason: the wiki is descriptive, the design
record is deliberative.