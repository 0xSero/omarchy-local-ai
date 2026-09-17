# omarchy-local-ai — the wiki

Everything this repository does, page by page. Every claim here is derived from the source in this
tree, not from intent: when the code and this wiki disagree, the code is right and the wiki is a
bug. References are given as `path` or `path:symbol` rather than line numbers, because line numbers
rot the moment anything above them moves and a symbol survives refactors — `grep -n 'name()' path`
is the lookup. `python3 wiki/verify.py` re-checks every path and every quoted message in these pages
against the tree, and the pages workflow runs it before publishing.

| | |
|---|---|
| **Documents** | `main` at `d38f8d2` — **Release v5.0.1** (2026-09-16) |
| **Plugin version** | 5.0.1 (`manifest.json`) |
| **Ledger / snapshot / recipes schema** | `omarchy-local-ai/ledger/2`, `…/snapshot/10`, `…/recipes/1` |
| **Published** | <https://0xsero.github.io/omarchy-local-ai/> |

These pages describe code, so the check is on the code:

```bash
git log -1 --format=%h -- bin lib ui manifest.json recipes.json
```

On `main` that prints the commit above. A commit that only touches `wiki/` changes what these pages
say without changing what they describe, so it leaves that hash alone.

This is the plugin only. The data it consumes comes from a second repository, `0xSero/local-ai-registry`
(see [15 — Registry and CI](15-registry-and-ci.md)).

## The 30-second version

A bar plugin. One button. It detects the GPUs on the machine, picks the one validated recipe for the
detected card from a vendored `recipes.json`, downloads the weights, starts **two** containers per
running model (an engine on a private docker network, and an attested gateway on loopback that
enforces an API key and speaks three API dialects), then proves the model actually works before it
calls it ready. Ready means: right model served, key enforced, decode not running on the CPU, all
advertised API dialects answering, tools working if claimed, images and video understood if claimed.
Anything that fails is rolled back to what was running before, and the reason lands on the card.

Nothing is written into your own config. Agents get the endpoint only when they are launched from
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
| 11 | [The panel](11-panel.md) | `ui/Panel.qml`, `ui/ui.js`, `ui/CardRow.qml`, `ui/Orb.qml`: the three views, compact and full-screen, the rows, the polling, the IPC |
| 12 | [CLI and environment reference](12-cli.md) | Every verb, every environment variable, every refusal |
| 13 | [Tests](13-tests.md) | The shim harness, what the 176 assertions cover, the rented-GPU harness, the visual helper |
| 14 | [Troubleshooting](14-troubleshooting.md) | Every message the plugin can print, what caused it, what to do |
| 15 | [Registry and CI](15-registry-and-ci.md) | The registry repository, the export, the three workflows, how a release is cut |
| 16 | [History](16-history.md) | How the code got here, what each version changed, the state of the work |

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

## Reading the source

| File | Lines | Role |
|---|---|---|
| `bin/omarchy-local-ai` | 227 | The whole CLI: every verb, the worker entry points, the root-phase entry point |
| `lib/common.sh` | 122 | Paths, ledger read/write, the op lock, logging |
| `lib/priv.sh` | 152 | Docker-without-the-docker-group: the pkexec phases and the root-side re-validation |
| `lib/hardware.sh` | 43 | `nvidia-smi` and Intel PCI enumeration |
| `lib/recipes.sh` | 150 | The recipe file, hardware match, the gate |
| `lib/weights.sh` | 278 | Destination, marker, adoption, download |
| `lib/runtime.sh` | 332 | Slots, container argv, acceptance, rollback |
| `lib/share.sh` | 100 | The key and the tailnet route |
| `lib/agents.sh` | 129 | Per-agent launch commands |
| `lib/snapshot.sh` | 167 | The derived read model |
| `ui/Panel.qml` | 267 | The card |
| `ui/ui.js` | 194 | Row data (no Qt) |
| `ui/CardRow.qml` | 83 | One row |
| `ui/Orb.qml` | 40 | The state orb |
| `test/all` | 613 | The shimmed suite |
| `test/bundle` | 18 | Builds the release archive and runs both suites against its contents |
| `test/ui.cjs` | 46 | Node checks of the row data |
| `docs/design.md` | 271 | The design record: decisions, scope, open items, the release process |
| `Makefile` | 28 | `sync`, `test`, `bundle`, `check` |
| `recipes.json` | 5732 | The vendored validated recipes |

Line counts are of `main@d38f8d2`; they are here for orientation, not as references.