# Omarchy Local AI — design

Consolidated 2026-09-03. Decisions are recorded once agreed; open items carry a
recommendation and are settled one at a time, bottom-up.

## What it is

One Omarchy bar plugin that runs the one validated recipe for the user's GPU
and hands the served model to every installed coding agent. The user sees a
model name, Start/Stop, an agent selector, and a Tailscale share toggle.
Everything else is automatic and refuses out loud: hardware match, download,
launch, acceptance, agent wiring, rollback.

Three parts, one job:

- **Registry** (data, `0xSero/local-ai-registry`): validates one recipe per
  hardware id on the exact card and exports the file the plugin vendors.
- **Controller** (bash, `bin/omarchy-local-ai` + `lib/`): turns that recipe
  into a running, verified container and reports state.
- **Panel** (QML, `ui/Panel.qml`): renders the snapshot and issues the verbs.

## Scope (Sero, 2026-09-02)

Single GPU. NVIDIA and Intel Arc Pro B70. Five models by VRAM tier, 4-bit,
128K context everywhere and 256K where it fits, EXL3 on TabbyAPI or SGLang
ahead of llama.cpp:

| Tier | Model | Engine | Context |
|---|---|---|---|
| 8 to 10 GB | lfm2.5-2.6B bf16 | SGLang | 128K |
| 12 GB | Qwen3.5-9B EXL3 4bpw | TabbyAPI | 128K |
| 16 to 20 GB | Qwen3.5-9B EXL3 4bpw | TabbyAPI | 256K |
| 24 GB | Gemma-4-12B-it EXL3 4bpw | TabbyAPI | 128K |
| 32 GB and up | Qwen3.8-27B EXL3 4bpw (Qwen3.6-35B alternate) | TabbyAPI | 256K |
| B70 32 GB | Qwen3.8-27B Q4_K_M | llama.cpp SYCL | 128K |

Multi-GPU, AMD, and Mac follow once this ships. Target: PRs updated
2026-09-03, ready for review 2026-09-05.

## Decided

### 1.1 Registry data is vendored, not fetched
The registry build (`scripts/export_plugin_recipes.py`) emits `recipes.json`:
validated, recommended, single-GPU docker recipes, joined flat, keyed by
hardware id, stamped with the registry commit. Committed into the plugin; it
replaces `registry.pin`. No git or network at runtime for recipe data. The
safety gate still runs on every load. A sync step regenerates the file and
CI checks it matches the commit it claims.

### 1.2 Exact hardware id, one recipe per card
Each entry carries its own match data: backend, VRAM, normalized product
names. The export fails on two recommended recipes for one card
(`scripts/recommend.py` keeps exactly one by the tier map). No tier or family
inference in the plugin. A card not in the file is unsupported, and the panel
says so.

### 1.3 Coverage comes from validation on rented cards
`scripts/validate_rented.py` rents the exact card on Vast.ai, runs the
recipe's own digest-pinned image, materializes weights and config
in-container where the plugin would bind-mount them, runs the registry's
acceptance, and promotes. 34 hardware ids validated as of 2026-09-03 (branch
`runpod-validation`, worktree `~/local-registry/registry-runpod`, unpushed).
Missing: RTX 3080 12 GB (no rental stock), Intel B60 and DGX Spark (need
real hardware), RTX 2000 Ada's tier model (no stock; covered by its lfm
fallback).

### 1.4 Self-built, attested images where upstream cannot run the recipe
`0xSero/local-ai-images`, one directory per image, built only by a workflow
with BuildKit provenance, SBOM, and a GitHub build attestation. First image
`tabbyapi-exl3`: upstream TabbyAPI digest plus python3-dev, because Triton
cannot JIT ExLlamaV3's gated-delta-net kernels without Python.h. Recipes pin
the digest and carry `launch.provenance` linking the run.

### 1.5 Updates are checked in the background and applied by the user (2026-09-17)

Two things above the user can move: this plugin's own release, and the registry's recipe file. One
detached check — `upstream_autocheck` from `snapshot`, at most once per `OMARCHY_AI_UPDATE_TTL`
(6 h) — reads both from one origin (`raw.githubusercontent.com`: the registry's
`plugin/recipes.json` and this repository's `manifest.json` on the tracked branch) and **stages**
them under `$STATE`. It never adopts. The snapshot stays a pure read: `upstream_json` derives the
`update` field from files the check left behind, so refreshing the card never touches the network.

The card's home footer then carries one row. Something staged → `update`, primary, naming the
release and the count of new recipes for the cards actually detected. Nothing staged → `update-check`
(plain re-check). The check off → no row at all. `omarchy-local-ai update` applies the staged
registry file and then updates the harness through Omarchy's own `omarchy plugin update <id> --yes`,
so plugin installation stays the platform's job, not ours.

Two constraints the implementation carries, both found in review. The staged copy is adopted only if it
is *still* newer than the file it replaces — the applier claims the staged file first and validates
what it actually holds, so a background check racing an update cannot downgrade the file in use. And
recipe files reach jq as `--slurpfile` inputs, never as arguments: the published `recipes.json` is
already past the 128 KiB cap Linux puts on one argument, so passing its contents would fail every
snapshot on Omarchy while passing cleanly on a Mac.

This replaces 5.0's `recipes_autorefresh`, which fetched and adopted silently every six hours. The
trade is deliberate and it is the conservative direction: what a user runs is the vendored file the
marketplace reviewed until they say otherwise, and a fetched file still passes `gate_reason` recipe
by recipe. It costs freshness for users who never press the row, which is why the row is loud and
why `recipes update` (fetch and adopt in one step) stays for scripts. A real client-side ping was
rejected: it would need a server, and the registry has none.

### 1.6 Analytics are GitHub-native and complete (2026-09-17)

The question — how many people use this, and where they come from — has only GitHub's own answers,
because there is no server and we are adding none. `traffic.yml` records daily to the `stats` branch:
clones (every `omarchy plugin add` is a clone — the install count), views, referrers, paths, the repo
counts, every release asset's cumulative `download_count`, one GraphQL interaction tally (stars,
forks, watchers, issues, PRs, discussions, commits), and the repo snapshot with its `day` archived
inside the file so a star timeline is derivable. `traffic/summary.json` aggregates them, and the wiki's [17 — Stats](wiki/17-stats.md) page renders
that one file in the browser.

What GitHub cannot give is per-user usage: raw content fetches are not counted and there is no
per-event log for views or downloads. So "who ran which recipe" is not answerable without client
telemetry, which is out of scope on purpose.

Two things the recorder must not do, both from review (2026-09-17): it must fail loudly rather than
publish numbers it did not get (hence `pipefail` — jq happily turns an error body into zeroed
counters), and a step that dies must not lose the day's traffic. The second is free: every per-day
file is a *window*, and the aggregations group by day across all files taking the maximum reading, so
the next successful run re-records a day this one missed.

### 1.7 The native view is generated from this repository (2026-09-22)

Omarchy's Local AI tab is this plugin's card drawn inside Omarchy's own Agents
panel, and it is the only version of the card that ships inside Omarchy. Its row
data, row component and token bars *are* `ui/ui.js`, `ui/CardRow.qml` and
`ui/TokenTotal.qml`; `native/backend-command.js` is the one part that is native
to it, and `shell/plugins/agents/LocalAi.qml` (the view inside that panel) and
`manifest.json` stay hand-written in Omarchy's tree.

Three files that are copies are three files that drift, so they are generated:

    make native OMARCHY=~/omarchy          # write them into an Omarchy checkout
    make native-check OMARCHY=~/omarchy     # fail when they have drifted

`test/native` checks the same contract without a checkout. Adopting Omarchy's own
explicit-`textFormat` rule in `ui/` is what makes the copies byte-identical
rather than merely equivalent: Omarchy's `qml-text-format-scan.py` requires an
explicit `textFormat` on every `Text` whose `text` is not a bare literal, because
`Text.AutoText` promotes a string that looks like markup and fetches `<img src>`
from it. `ui/CardRow.qml` and `ui/TokenTotal.qml` had the same hole and now
declare `Text.PlainText` on every one of them.

The 4,871-line alternative — the whole plugin vendored into Omarchy's tree — was
closed in favour of this view. There is one repository to edit, one release number
across the plugin, the view and the marketplace listing, and one command between an
edit and the copy Omarchy ships.

## The vendored file contract (`recipes.json`)

Per hardware id: `match {backend, vramGb, names[]}` and `recipe`:

- `id`, `model {id, name, repository, revision, servedName, precision, sizeGb}`
- `engine`, `capabilities`, `serving {ctxTokens, concurrency}`, `speed {tps}`
- `weights.subdir`: where the download goes under a `${MODEL_ROOT}` mount
  (TabbyAPI loads `<mount>/<model_name>`)
- `image {provenance, attestation}`
- `launch {image, containerPort, entrypoint, arguments, environment, mounts,
  shm, ipc, networkMode, capAdd, securityOpt}`
- `validated {harness, acceptedAt}`

The file is the floor, not the ceiling: `recipes update` (and the card's
registry view, and a six-hourly background check from `snapshot`) fetches the
registry repository's copy over HTTPS from one fixed origin, size-capped,
schema-checked, accepted only when its `generatedAt` is newer than the file
in use, kept 0600 under the state dir, and used in place of the vendored one.
Every recipe is still gated at launch, so a fetched file can add validated
recipes but never widen what a launch may do. `OMARCHY_AI_RECIPES_URL=`
turns the fetch off; `OMARCHY_AI_RECIPES` names a file and turns it off too.

Mount sources are one of: `${MODEL_ROOT}/<dir>` (plugin downloads the
instance there, read-only into the container), `~/.cache/huggingface` (the
engine fetches into the shared HF cache), `asset/<file>` (registry asset,
must be shipped with the file; not yet exported, see open item 3c).

## Findings that constrain the runtime

- **CPU fallback looks like success.** A host whose driver cannot init the
  image's CUDA serves from the CPU at under 1 tok/s while every health check
  passes. Acceptance needs a decode floor; launch needs a driver check.
- **Images pin a CUDA version, cards pin a driver.** The SGLang image is CUDA
  12.9, TabbyAPI cu13 with forward-compat, llama.cpp newer than 12.4. The
  recipe must declare the minimum driver and the plugin must gate on it.
- **TabbyAPI weights layout is part of the contract** (`weights.subdir`).
  The old plugin put files at the mount root and could never have started a
  TabbyAPI recipe.
- **Host networking is refused by the gate**; all V1 recipes are bridge.
- **RunPod cannot pull ghcr.io images**; Vast can. Irrelevant to users,
  relevant to validation.

## Open, bottom-up, with recommendations

### 2. Ledger and lock
Persist one tiny JSON: current op `{name, recipeId, pid, startedAt, detail,
percent}`, `error`, `lastAccepted {recipeId, servedModel}`. Written only by a
worker holding `flock` on a file whose fd is closed in every child (the old
orphaned-lock bug). "Busy" derives from the op's pid being alive, never from
a string. Nothing derived lives in the ledger.

### 3. Runtime
- 3a Weights: the plugin downloads for every recipe (`hf download` into
  `${MODEL_ROOT}/<dir>/<subdir>` or into the HF cache), writes a marker with
  the revision after a verified download; presence is the marker plus the
  bytes it promises (a marker that outlives a deleted directory is dropped and
  the fetch repeats). Before a download the plugin looks for the weights on
  the machine (`~/models`, its own model root, the HF cache, `~/.cache/llama.cpp`,
  `OMARCHY_AI_WEIGHTS_PATHS`), verifies every file against the Hub's tree of
  the pinned revision (size, then SHA-256 or blob id), and adopts a match by
  reflink into the layout the engine expects (the recipe's directory, or HF
  cache blobs plus snapshot links). Containers never download.
- 3b Driver gate: `recipe.minDriver` in the export (from the image's
  `NVIDIA_REQUIRE_CUDA`), checked against `nvidia-smi` before launch.
- 3c Assets: config assets are exported inline (base64) in `recipes.json`
  and written to a plugin-owned path at launch, mounted read-only.
- 3d Acceptance: `/v1/models` matches, one completion, tool call when the
  recipe claims tools, and decode ≥ one fifth of the recipe's recorded speed.
- 3e Rollback stays: previous container set aside, restored on failure.
- 3f The B70 path (render nodes, SYCL) stays as built.

### 4. Snapshot
**Detection of an already-running recipe is agreed (2026-09-03):** the
container carries labels `io.omarchy.local-ai=1`, `.recipe=<id>`, and
`.registry=<commit>`. On every snapshot the controller finds owned
containers by label, reads the recipe id from the label, probes
`/v1/models`, and reports ready without touching it, even if that recipe is
no longer in the vendored file (then: "running <id> from an older registry;
Stop to update"). Weights already present, from a previous run or placed by
hand, are found by the idempotent download step, not re-fetched. A container
on the port without our label is never touched and is reported as
"port busy: not managed by this plugin".

A pure function of ledger + reality (container state, `/v1/models`,
tailscale, installed agents) + `recipes.json`. Never stored, never mutated
during a read. State rule: op pid alive → busy; else error in ledger → error;
else container running and API answering → ready; else container running →
starting; else idle. Fields: state, error, model (name, sizeGb, downloaded)
or `reason` why none, operation, share, agents. About a dozen fields.

### 5. Agents: launch-only (agreed 2026-09-03)
The local model reaches an agent only when the agent is launched from the
panel. The controller passes the endpoint by environment variables and
flags at launch; nothing on disk is edited, so nothing has to be restored,
and an agent typed in a terminal keeps its own provider. Stop kills the
container; running agent sessions lose their endpoint and say so. The
agent selector lists installed agents whose API dialect the running engine
serves (see open item 5a).

### 5a. One gateway, always, for every engine (agreed 2026-09-03; one pair per model since 5.0)
Every running model is two owned containers: the engine on a private network
of its own and the **gateway** on 127.0.0.1:<port> (12434 for the first
model, the next free port for each further one), from a tiny attested image
in `local-ai-images`. The ledger's `slots` map (recipe id → port, network,
container names, cards claimed, acceptance) is the list of running models; a
Start replaces only the slots holding the cards it claims and sets them aside
until acceptance, so models on other cards keep running. The gateway serves OpenAI chat completions,
Anthropic Messages, and OpenAI Responses and translates all of them,
including tool calls and streaming, to the engine's chat completions. It
runs for every engine, no per-engine special cases, so every agent and the
Tailscale share talk to one endpoint with one behavior. Codex needs
Responses; it no longer works over chat. Acceptance probes all three
dialects through the gateway; an agent whose dialect fails is hidden from
the selector. The gateway shares the engine's labels, lifecycle, and
rollback. The registry validates engine plus gateway as one recipe.

### 5a. Docker without the docker group (agreed 2026-09-10)
Omarchy leaves users out of the docker group on purpose and reaches the
daemon through a polkit prompt; polkit there is `auth_admin` without keep.
So: direct docker when the socket is writable; otherwise the docker work of
one action (Start, Stop, share) runs as ONE `pkexec` of this script
(`_root <phase>`, `lib/priv.sh`), one prompt, the way
`omarchy-launch-docker-tui` does it. The card's refresh never calls docker in
that mode. A root phase creates no file under the user's state; progress and
reasons come back on stdout. The set-aside pair is dropped by the next phase,
so a successful Start costs one prompt. A missing NVIDIA container toolkit is
installed inside the same prompt.

### 5b. Tailscale share is keyed, auto-configured, user-changeable (agreed 2026-09-03)
Loopback is keyless. The first Share generates a random key, stores it in the
plugin's state directory (mode 600), and the gateway, which reads the key
file on each request, requires it as `Authorization: Bearer` or `x-api-key`.
The key lives in that file only: not in the ledger, not in the snapshot the
panel reads, not in the log (revised 2026-09-04 after marketplace review).
The state directory is 0700 and every file in it 0600, since agent launch
configs there embed the key. The key enters no process argument: the
acceptance probes hand curl the header as a 0600 file (`-H @file`), and an
agent launch is a two-word bash stage that reads the key file into the named
variables and execs the agent, so `/proc/<pid>/cmdline` carries the file's
path and variable names only. The share dialog shows the URL and the key file;
`share --key <value>` (and a panel field) replaces it without a restart.
The route is the gateway's port published on the machine's tailnet address
(`docker run --publish 100.x.y.z:12434:12434`), never `tailscale serve`: serve
refuses a plain user until root names them the operator, and the panel cannot
escalate (no polkit agent runs on Omarchy). WireGuard already encrypts the
tailnet, so plain http there is as private as serve's https. Toggling restarts
the stateless gateway with or without the second publish. Stop sharing drops
it; the key stays for next time. (revised 2026-09-03 evening)

### 6. Commands
`snapshot`, `load`, `unload`, `open-agent [name]`, `share [--key]`, `gpu`,
`agent-dir`, `agent-args`; nothing else. The last three are settings, never
workers. Workers log to `$STATE/log`.

### 7. Panel
Since 5.0 the card is a tree of three places, home › card › model, with work
(download, start, stop, share) and error taking the card over in between. The
tree, every word on it, and every state side by side were designed first
(2026-09-15) and the QML follows that gallery. `ui/ui.js` turns the snapshot plus
the navigation state into header, path, rows and a pinned footer as plain
data; `ui/Panel.qml` draws it and runs the verbs; `ui/CardRow.qml` is the one row
component, `ui/Orb.qml` the state orb. Rows are one line (a noun and a datum),
with a second line only for a card type's cells. Home nests each running model
under its GPU group and labels occupied GPUs locked. The compact card fits the screen
with a 720 px ceiling; full-screen mode uses the available area beside the bar.
The list scrolls while the header, path and footer stay. The header control or
F11 toggles the size without changing navigation; Escape returns to compact first.

### 8. Repo hygiene
Bash + QML as before; the same isolated shim tests; `make sync` pulls
`recipes.json` from a registry commit and CI diffs it. Design doc is this
file; CONTEXT.md is retired into it.

## Status 2026-09-03

Built. Plugin on branch `v4` of `0xSero/omarchy-local-ai` (draft PR), registry
on `runpod-validation` (draft PR), gateway and TabbyAPI images attested in
`0xSero/local-ai-images`. Not yet run on real hardware: the Omarchy box is
held by a GLM-5.3 job. Open items: live run, gateway re-validation per engine
family (in progress), driver floors are per image family rather than measured.

## Releasing

`main` is always green and always releasable; nothing lands on it without the suite passing. A
release is a version in `manifest.json`, a `CHANGELOG.md` section, and a signed-off commit
"Release vX.Y.Z" on `main`, tagged `vX.Y.Z`. Pushing the tag runs the suite again, checks the
version and the changelog section, and publishes the GitHub release. The marketplace update
request (omacom/omarchy-plugin-marketplace) targets that tagged commit and nothing else, so what
the marketplace verifies is always a release. Patch for fixes, minor for behaviour, major for a
change to what the card does or to the state files.

## The listing image

The marketplace renders one image per listing — the detail page at up to 1600 px, the browse card at
up to 720 — and it reads that image from `preview.png` in the repository root **at the tagged commit
the update request targets**. A release that drops it publishes a listing with no picture, and the
listing's description is `manifest.json`'s `description` at that same commit. So `preview.png` and
the description travel with the release, not with the submission.

`docs/preview.py` composes the image from the Local AI banner (`media/banner.png`), the supported
hardware facts written in the script, and two full-screen captures of the open card, one on NVIDIA
and one on Intel Arc (`test/visual` captures one over SSH). It finds the panel by its own background
colour, so any resolution works, and fails loudly rather than clipping when a line no longer fits.

    python3 docs/preview.py --banner media/banner.png --nvidia nvidia.png --intel intel.png --out preview.png

## Release contents

`make bundle` packages only the manifest, recipe catalog, license and files in
`bin/`, `lib/` and `ui/`. The release workflow uploads that archive after
`make test` unpacks and tests it. Development tests and docs remain in their
own directories in the repository; they are not installed from the bundle.
Tiny multimodal acceptance payloads are embedded in `lib/runtime.sh`.
