# omarchy-local-ai — the wiki

Everything this repository does, page by page. Every claim here is derived from the source in this
tree, not from intent: when the code and this wiki disagree, the code is right and the wiki is a
bug. References are given as `path` or `path:symbol` rather than line numbers, because line numbers
rot the moment anything above them moves and a symbol survives refactors — `grep -n 'name()' path`
is the lookup. `python3 wiki/verify.py` re-checks every path and every quoted message in these pages
against the tree, and the pages workflow runs it before publishing.

| | |
|---|---|
| **Documents** | Release v5.3.1 (2026-09-21) |
| **Plugin version** | 5.3.1 (`manifest.json`) |
| **Ledger / snapshot / recipes schema** | `omarchy-local-ai/ledger/2`, `…/snapshot/10`, `…/recipes/1` |
| **Published** | <https://0xsero.github.io/omarchy-local-ai/> |

The release tag pins the implementation. The site is built from the documentation on main; its workflow checks paths and quoted messages before publication.

This is the plugin only. The data it consumes comes from a second repository, `0xSero/local-ai-registry`
(see [15 — Registry and CI](15-registry-and-ci.md)).

## The 30-second version

A bar plugin, optionally inside the native Agents panel. It detects the GPUs on the machine and lets you choose a validated recipe for one or more cards from a vendored `recipes.json`, downloads the weights, starts **two** containers per
running model (an engine on a private docker network, and an attested gateway on loopback that
enforces an API key and speaks three API dialects), then proves the model actually works before it
calls it ready. Ready means: right model served, key enforced, decode not running on the CPU, all
advertised API dialects answering, tools working if claimed, images and video understood if claimed.
Anything that fails is rolled back to what was running before, and the reason lands on the card.

Agent provider settings are isolated under plugin-owned state. The optional native integration does change your shell layout and, when requested, Hyprland bindings, with dated backups. Agents get the endpoint only when they are launched from
the panel. Sharing publishes the gateway's own port on the tailnet address, with the key.

## Pages

| # | Page | What it answers |
|---|---|---|
| 1 | [Architecture](01-architecture.md) | The three parts, the processes, the containers, the trust boundary, the data flow |
| 2 | [Install and file layout](02-install-and-layout.md) | What installs where, every file on disk, the permission model, how to remove it |
| 3 | [Recipes, matching, gating](03-recipes.md) | The `recipes.json` contract, hardware detection and match, how a recipe is chosen, what the gate refuses, how a newer file is fetched |
| 4 | [State: ledger and snapshot](04-state.md) | The two state files, every field, the state rule, the lock, the housekeeping |
| 5 | [The Start path](05-start-path.md) | Click to ready, step by step, including rollback and every way it can stop |
| 6 | [Weights](06-weights.md) | Where weights go, the completion marker, partial downloads, adopting weights you already have |
| 7 | [Containers](07-containers.md) | Slot layout, labels, the exact engine and gateway argv, ports, setting aside and restoring |
| 8 | [Acceptance](08-acceptance.md) | Every probe the plugin runs before it says ready, with its exact threshold |
| 9 | [Agents](09-agents.md) | The eleven agents, their dialects, the exact environment each one gets, and how the key stays out of argv |
| 10 | [Sharing on the tailnet](10-sharing.md) | The key, the publish, IPv6, address changes, why not `tailscale serve` |
| 11 | [The panel](11-panel.md) | `ui/Panel.qml`, `ui/ui.js`, `ui/CardRow.qml`: the three views, compact and full-screen, the rows, the polling, the IPC |
| 12 | [CLI and environment reference](12-cli.md) | Every verb, every environment variable, every refusal |
| 13 | [Tests](13-tests.md) | The shim harness, what the assertions cover, the rented-GPU harness, the visual helper |
| 14 | [Troubleshooting](14-troubleshooting.md) | Every message the plugin can print, what caused it, what to do |
| 15 | [Registry and CI](15-registry-and-ci.md) | The registry repository, the export, the three workflows, how a release is cut |
| 16 | [History](16-history.md) | How the code got here, what each version changed, the state of the work |
| 17 | [Stats](17-stats.md) | The installs, views, downloads, stars and interactions GitHub records, read live from the `stats` branch |

## Vocabulary

These words are used precisely throughout; the wiki uses them in exactly this sense.

| Word | Meaning |
|---|---|
| **recipe** | One validated way to run one model for one card: image digest, model revision, launch arguments, mounts, capabilities. Data, never code. |
| **hardware id** | The key a card is matched to, e.g. `rtx-4090-24gb`, `intel-arc-pro-b70-32gb`. |
| **gate** (`gate_reason`) | The launch-time refusal function in `lib/recipes.sh`. Fail-closed: anything malformed or out of policy is refused. This is the reviewed trust boundary. |
| **slot** | One *running* model: a recipe id plus its port, its private network, its engine and gateway container names, the cards it holds, and its acceptance record. Lives in `ledger.json` under `.slots`. |
| **engine** | The container that actually serves the model (TabbyAPI, SGLang, llama.cpp, vLLM). Never published; reachable only from its slot's gateway. |
| **gateway** | The attested container that listens on `127.0.0.1:<port>`, enforces the key, translates chat / Anthropic Messages / OpenAI Responses, and forwards to the engine. |
| **op** | One running worker operation: `download`, `starting`, `unload`, `share`. `.op` in the ledger; busy while its pid is alive. |
| **ledger** | `$STATE/ledger.json`. The only authoritative state. |
| **snapshot** | `$STATE/snapshot.json`. A derived read model, rewritten from the ledger plus reality on every `snapshot` verb. The panel watches this file. |
| **worker** | A detached `omarchy-local-ai <verb>` process that holds the op lock and reports through the ledger. |
| **phase** | The root side of one batched privileged action (`_root <phase>`): `start`, `restore`, `drop`, `stop`, `restart_gateway`, `toolkit`. |
| **marker** | `$STATE/weights/<recipe-id>.json`. A promise that a specific repository revision was downloaded to a specific path. Never trusted alone: the files must be there too. |

## Current experience

Version 5.3.1 brings Local AI into the native Agents panel with the same section styling as Claude and Codex. Start from an expandable agent launcher and one status row per GPU type, with historical token totals in the same filled rows as the native provider model totals. Open a group for models or running-model statistics; temperature, usage and VRAM meters stay in the details.

| Area | Verified | Still to verify |
|---|---|---|
| Agents | All eleven adapter handoffs tested; OMP, Pi, OpenCode and Crush terminal startup on Omarchy; real Pi/OpenCode requests on NVIDIA and Intel | Full conversation and tool acceptance for every agent |
| GPU readings | Physical NVIDIA and Intel; AMD sysfs fixtures | Physical AMD hardware |
| Today's statistics | Incremental vLLM/llama.cpp logs and counters | Other engines are unavailable; first-day history is not reconstructed |
| Native panel | Shared native styling, row-data checks, QML loading | Final visual acceptance of the latest compact overview |
| Mac/Moonlight | Window switching, apps, fullscreen, workspaces and help binding | Offline guide rendering; shifted Command+Tab uses Ctrl+Space, P instead |

See [11 — The panel](11-panel.md) for the interface and [2 — Install](02-install-and-layout.md) for setup, updating and restoration.

## Reading the source

| Path | Role |
|---|---|
| `bin/omarchy-local-ai` | CLI verbs and worker entry points |
| `lib/` | Controller, hardware scans, agent adapters and incremental telemetry |
| `ui/Panel.qml` | Standalone or embedded panel and action dispatch |
| `ui/ui.js` | Pure row data and navigation choices |
| `ui/CardRow.qml` | Shared row, disclosure and meter rendering |
| `integrations/` | Native Agents patch, installer, Mac controls and offline guide |
| `test/` | Controller, telemetry, terminal handoff, UI and bundle checks |
| `docs/design.md` | Design record and release process |
| `recipes.json` | Vendored catalog from the local-ai registry |
