# 13 — Tests

Four harnesses: shipped controller logic, real coding agents, GPU recipe qualification, and native panel captures.

## `test/agents` — installed agents against ready local models

Run on the inference host after loading the models to test:

```bash
python3 test/agents --out "$HOME/agent-check-$(date +%Y%m%d-%H%M%S)"
python3 test/agents --out "$HOME/agent-check-pi" --agents pi --features text tools vision
```

Use `--plugin` for a different checkout or installed plugin, `--state` for its state directory, and repeat `--recipe <id>` to select ready recipes. The script does not load models or install agents. It tests only installed, launchable agents and capabilities advertised by each ready model; it does not qualify other registry recipes.

Each case uses the real launcher with an isolated state and work directory. A loopback tracing proxy verifies the selected model and records HTTP outcomes without logging authentication headers. Tests require the actual final response, and file tests also verify the resulting file. Image tests require an image block in the inference request; Codex shell execution during an image test is rejected so pixel inspection cannot masquerade as vision. A failed tool call keeps the case failed even if the final answer succeeds. Agent notices are recorded separately as diagnostics.

The output contains `results.json`, per-case transcripts and API responses, plus generated test inputs. It is private and must be outside the repository. Exit status is nonzero when any case fails. This exercises real inference and file tools; it is separate from UI acceptance and a finite pass is not a guarantee of error-free model output.

## `make test` — the suite, run against the shipped archive

```bash
make test                 # bash test/bundle
make bundle               # dist/omarchy-local-ai-<version>.tar.gz
make check                # the tests, plus a recipes.json schema/commit/gateway sanity check
```

`make test` does not run the suite against the checkout. `test/bundle` builds the release archive from
the Makefile's explicit `RUNTIME` list, fails if the archive contains anything else (`Unexpected
release file: <path>`), unpacks it into a temp directory, checks that `manifest.json`'s
`entryPoints.barWidget` exists inside it, and only then runs

```bash
bash test/all "$work"      # the controller suite, rooted at the unpacked archive
node test/ui.cjs "$work"   # the row-data checks, reading $work/ui/ui.js
echo "Runtime bundle: verified"
```

Both suites take an optional root argument (default: the checkout), so the same assertions run against
either. The point is that a file the suite depends on but the bundle forgets is caught here, not by a
user.

No GPU, no docker, **no network**: it shims every external command and drives the real CLI end to end.
Needs `bash` and `jq`; the UI checks need Node.

`test/all` is TAP-flavoured: `ok <n> - <what>` per assertion, `not ok` plus a diagnostic and an
immediate exit on the first failure, and a final `1..<n>` plan.

### Isolation

```bash
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)          # canonical: the CLI resolves itself with readlink -f
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
OMARCHY_AI_USER_HOME=$TMP/home  OMARCHY_AI_STATE=$TMP/state  OMARCHY_AI_RECIPES=$TMP/recipes.json
OMARCHY_AI_MODEL_ROOT=…  OMARCHY_AI_CACHE_ROOT=…  OMARCHY_AI_HF_HOME=…
OMARCHY_AI_PORT=12434  OMARCHY_AI_POLL=0  OMARCHY_AI_TIMEOUT=5
OMARCHY_AI_FOREGROUND=1  OMARCHY_AI_NO_HOST_HF=1  OMARCHY_AI_DOCKER=direct
SHIM=$TMP/shim  OMARCHY_AI_DRI_PATH=$TMP/dri  PATH=$TMP/bin:/usr/bin:/bin
```

`PATH` deliberately excludes everything else, so the developer's own agents cannot leak into the
results. `bash` and `jq` are symlinked into `$TMP/bin` (the `jq` symlink is never `chmod`ed — its
target is not the suite's to change).

### The shims (`$TMP/bin`)

| Shim | Fakes |
|---|---|
| `nvidia-smi` | GPU rows plus the driver version; `SHIM_GPUS`, `SHIM_DRIVER` |
| `docker` | a container store under `$SHIM/containers/<name>` (labels, state, restart count), an image list, networks, `info`, `pull`, `run`, `inspect`, `logs`, `rename`, `rm`, `start`, `stop`, `ps`; refuses when `OMARCHY_AI_DOCKER=prompt` and `SHIM_ROOT≠1` |
| `curl` | the gateway: the engine/gateway container states decide whether a pair answers; dialects come from `SHIM_APIS`; the Hub's file tree from `$SHIM/tree.json`; the registry's recipes copy from `$SHIM/remote-recipes.json`; it logs its own argv, which is how the suite proves the key never reaches curl's command line |
| `tailscale` | `status --json` for four tailnets: default (v4+v6), `v6` (IPv6 only, no MagicDNS), `off` (logged in, stopped), `newip` (address changed) |
| `pkexec` | polkit: runs the command from a **clean environment** carrying only `SHIM_*` and `PKEXEC_UID`, or fails with 126 when `SHIM_PKEXEC_FAIL=1` |
| `lspci` | an Arc Pro B70 host whose `pci.ids` has no name for the card (two `8086:e223` devices plus one without a render node) |
| `ss` | a listener on 12434 when `SHIM_PORT_BUSY=1` |
| `pacman`, `nvidia-ctk`, `systemctl` | the toolkit install, logging to `$SHIM/toolkit.log` |
| `pi`, `claude`, `codex` | installed agents that echo their environment |
| `omarchy-launch-tui`, `omarchy-default-agent` | the terminal launcher and the default-agent query |

Knobs the assertions pull: `SHIM_PULL_SLOW`, `SHIM_PULL_FAIL`, `SHIM_PULL_ERR`, `SHIM_DOWNLOAD_SLOW`,
`SHIM_DOWNLOAD_FAIL`, `SHIM_RUN_FAIL`, `SHIM_CRASHLOOP[_UNLESS]`, `SHIM_LOGS`, `SHIM_REPLY`,
`SHIM_SERVED`, `SHIM_APIS`, `SHIM_CONTEXT`, `SHIM_TOKENS`, `SHIM_NO_USAGE`, `SHIM_SLOW`,
`SHIM_LEAK_THINK`, `SHIM_MEDIA_REPLY`, `SHIM_KEYLESS_GATEWAY`, `SHIM_DOCKER_DOWN`, `SHIM_RUNTIMES`,
`SHIM_PKEXEC_UID`, `SHIM_PKEXEC_FAIL`, `SHIM_TS`, `SHIM_PORT_BUSY`, `SHIM_FOREIGN_PORT`, `SHIM_LSPCI`,
`SHIM_GPUS`, `SHIM_DRIVER`, `SHIM_RECIPES_DOWN`, `SHIM_ROOT`.

### Fixtures

A synthetic `recipes.json` is generated by `recipe <id> <tools> <mountkind>` plus `write_recipes`,
`write_recipes_alts` (a recommended recipe plus alternates) and `write_recipes_two` (two card types).
Recipes are then mutated per test with `jq` — `.launch.networkMode="host"`, `.cards=2`,
`.launch.mounts[0].source="${MODEL_ROOT}/../../etc"`, and so on — which is how the gate's refusals are
exercised without inventing a second file format.

### What the 176 assertions cover

**Happy path and its report.** A fresh snapshot is idle; hardware matches the recipe; weights are
absent before any download; `load` reaches `ready`; the pull appears as its own step; weights land in
`<mount>/<subdir>`; the marker records it; the gateway publishes `127.0.0.1:12434` while the engine
gets a private network and alias; the recipe's asset is written from `recipes.json`, mounted
read-only, with the vendored content; all three dialects accepted; every installed agent launchable.

**Secrets.** The key is generated on first start and appears in `gateway.key` **only** — not in the
ledger, the snapshot or the log; the snapshot carries the key file's path and no key; the state dir is
0700 and every file in it 0600; assets stay 0644 for the engine's uid; `open-agent` argv for `claude`
and `codex` contains the key nowhere, and the environment it builds does; curl's argv never contains
it and the header comes from the 0600 file; no user config file is created.

**Sharing.** On with the tailnet URL; the gateway republished on the tailnet address with loopback
kept, running as this user; the engine untouched; `share --key` replaces the key and leaves no copy of
the old one anywhere under `$STATE`; off again; refused while tailscale is down, with the model still
ready; an IPv6-only tailnet without MagicDNS, bracketed for docker; an address change shown as *not
shared, with why*, and re-sharing binding the new address.

**Weights.** Deleted weights behind a marker stop counting as on disk and are fetched again (the log
says the marker was stale); a GGUF found under `~/models` is adopted after a checksum with no download
container at all; a same-named file with other bytes is refused and the pinned file fetched; a whole
directory is verified file by file against the Hub tree and adopted — into the recipe's directory, and
in the hub case as blobs plus snapshot links; one edited small file is enough to refuse it; the marker
rules let a TP2 variant reuse a downloaded model.

**Runs.** Two models on two cards side by side on 12434 and 12435, each with its own network and pair;
a Start on a card in use replaces only that model, and a failed Start restores it without touching the
other card; `unload <recipe>` stops one, `unload` stops everything and turns sharing off; the
set-aside pair is dropped on success and a stale one is dropped before the next set-aside; a failed
acceptance restores the previous pair and reports the reason; a crash-looping engine is caught in
seconds with its log line; an unforeseen worker death leaves a reason.

**Acceptance edges.** A CPU-speed decode fails the floor; with no usage reported the speed is measured
from the words written; a reply under 16 tokens skips the floor; a reasoning model leaking its think
tags is refused; a runtime advertising less context than the recipe fails; vision and video are
exercised and a wrong answer fails readiness; a keyless gateway never becomes ready.

**The gate.** Host networking, host IPC, an escaping mount, an escaping weights directory, a repository
name that is not a name, an unpinned image — each refused with its own sentence; the driver gate is
silent without a `minDriver` and refuses an older driver; an unmatched card says which card.

**Cards.** Detection listing one card, two cards, the largest with a recipe chosen, a pinned card
without a recipe saying so, `gpu auto` returning; Intel cards found by PCI id with an old `pci.ids`,
aggregating as `2× Arc Pro B70 · 64 GB`, with a card lacking a render node left out; identical cards
aggregating with their total and keys; claims of one, two and three cards (the last refused with its
count); a claim on a group with no card refused per group; a two-card recipe receiving
`--gpus "device=0,2"`.

**Recipes as data.** The vendored file is in use until a newer one is fetched; a newer file is adopted
0600 and reported as `live`; an older one ignored; a file that is not a recipes file refused; no route
reported as a sentence; `OMARCHY_AI_RECIPES_URL=` turning the fetch off; the snapshot refreshing in the
background once the TTL has passed; alternates listed with the recommended first, with a
shape-refused alternate not offered at all.

**Prompt mode** (socket unwritable). The card's refresh makes no docker call; a Start from nothing is
**one** pkexec for images, weights and both containers; the gateway runs as the uid pkexec reports and
never as a uid from a user-owned file; an env file that is not what the prompt was raised for runs
nothing; a recipe swapped under the prompt runs nothing; Stop and share are one prompt each; a
dismissed prompt is a reason on the card; a failed acceptance costs one more prompt for the rollback;
a missing NVIDIA toolkit is installed inside the same prompt.

**Misc.** A second operation while busy is refused; the busy state clears when the worker dies; a
worker killed without its exit trap is reported by the next refresh; `lastStartSeconds` is recorded and
becomes `operation.expectedSeconds`; refusals the panel invokes land in the ledger; a working launch
clears an earlier refusal; `agent-args` adds and clears flags; `agent-dir` records and refuses; a
broken recipes file still yields an error state; an install from before 4.1 has its ledger scrubbed of
the key and made 0600.

### What it deliberately does not cover

Real docker, real bind-mount realisation, a real GPU, driver behaviour, and the container image
contents. Those are the rented harness's job. The docker shim is a store, not a container runtime: a
test can prove the plugin *asked* for the right thing, not that docker *did* it.

## `test/rented.py` — the real cards

```bash
python3 test/rented.py --list
python3 test/rented.py <hardware-id>... [--provider vast|runpod] [--commit <sha>]
    [--registry ~/local-registry/local-ai-registry] [--gateway-commit main] [--disk 60]
    [--timeout 3600] [--keep] [--dry-run] [--parallel 1]
```

Rents the exact card, and runs **the plugin's own Start path** on it. Rented containers have no docker
daemon, so the recipe's own image *is* the container: an onstart script materialises weights and assets
at their mount targets (the registry's `validate_rented.py` plan) and then runs
`test/rented-inside.sh`, which drives the shipped CLI at `--commit` behind a docker shim — the plugin's
engine argv launches the engine as a process, its gateway argv starts `gateway.py`, and the plugin's own
acceptance chain decides. The gateway source is pinned to a commit **and** to the SHA-256 of the bytes
at that commit. Results land in `test/rented-results/<hardware-id>.json` (git-ignored: it is data).

Provider notes, from the registry's validator: RunPod community hosts cannot pull `ghcr.io` images, so
TabbyAPI recipes go to Vast; SGLang recipes (Docker Hub) run on either. Credentials come from
`~/.config/vastai/vast_api_key` and `~/.runpod/config.toml`.

What it does **not** cover: docker itself, bind-mount realisation, and the previous-model rollback.

## `test/visual` — the real panel

```bash
./test/visual omarchy --output HDMI-A-3 --action card:rtx-3090-24gb --action count:2 --save /tmp/panel.jpg
```

Over SSH it exports `XDG_RUNTIME_DIR`/`WAYLAND_DISPLAY`, calls the panel's IPC (`open`, then each
`activate <action>`) and captures the output with `grim`. Only **navigation and presentation** actions are accepted
(`home`, `back`, `expand`, `agent-toggle`, `card:<hw>`, `count:<n>`, `pick:<id>`, `model:<id>`) — the
helper can never start or stop a model. The host name and every action are regex-validated before they reach a shell. Because
the image comes from the live desktop, this checks the deployed QML and the deployed `recipes.json`
together; that is the only test that does.

`ssh omarchy hyprctl monitors` lists outputs — use the one containing the panel, since a Sunshine
virtual output can differ from the physical panel output.

## `test/ui.cjs` — the row data

Runs `ui/ui.js` in a Node VM (stripping the QML pragma) and asserts the things that can silently rot:

- capability chips: a `true` capability is not struck through, a `false` one is, an unknown one reads
  `<name> ?`;
- the card view for a two-card recipe: a *context* row reading exactly `256K per request`, and a video
  chip that is not off;
- **home grouping**: the first section is `gpus`; two running models appear as `child` rows under the
  groups that hold them, in group order; an occupied group's datum is `2 locked` with every cell
  marked `locked` and no action, while a free group's action is `card:<hardwareId>`;
- a crashed model's row reads `crashed ›` while its group's cells read `crashed`.

It runs in `make test` — against the unpacked archive — and in CI on every push.
