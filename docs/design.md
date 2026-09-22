# Omarchy Local AI — repository design, version 6

Written 2026-09-22. This replaces the version 4/5 design (in git history at `23e9b02`). It is the
design of the repository as it will be, derived from what Omarchy itself does; the evidence is
summarised in section 1 and detailed in `~/local-omarchy/PROGRESS.md` section 4.

The card's visible design does not change. Everything behind it does.

## 1. Constraints, each with its source

| Constraint | Source |
|---|---|
| One self-contained bash file per feature, no `lib/`; `#!/bin/bash`, `[[ ]]`, `(( ))`, two-space indent; `omarchy-cmd-missing` / `omarchy-pkg-add` rather than `command -v` / `pacman`; a `# omarchy:summary=` header, `# omarchy:args=`, `# omarchy:requires-sudo=true` | omarchy `AGENTS.md`, `docs/cli-router.md`, `test/shell.d/bin-style-test.sh` |
| Docker behind one polkit prompt per action: `pkexec <canonical path> __priv <action> <args>`; as root pin `PATH` and `LC_ALL`, take the caller from `PKEXEC_UID`, refuse a symlinked or foreign-owned home, never trust a caller-supplied path; `omarchy-sudo-docker` decides whether a prompt is needed at all | omarchy `bin/omarchy-windows-vm`, `bin/omarchy-sudo-docker` |
| Panel data model: bash writes a JSON record atomically (`mktemp` + `mv`), QML watches it with `FileView { watchChanges: true }`; setup and error states are strings in the record, rendered by generic QML; actions are `Process { command: [...] }`; launches go through `bar.run` and `omarchy-launch-tui` | omarchy `shell/plugins/agents/Main.qml`, `panels/tailscale/Service.qml`, `bin/omarchy-agent` |
| Pure logic in a `Model.js` with `module.exports`, tested under node with `run_node_test` | omarchy `docs/testing.md` |
| Tests: `test/shell.d/<name>-test.sh` with the `base-test.sh` preamble, shims by a scratch `bin/` on `PATH`, never a real docker or network | omarchy `docs/testing.md`, `test/shell.d/windows-vm-compose-test.sh` |
| Manifest `schemaVersion` 1 with `id name version kinds entryPoints`; `omarchy.*` reserved; packaged default plugins are `omacom.*` | omarchy `shell/services/PluginRegistry.qml`, `bin/omarchy-plugin-validate` |
| Security findings already ruled on: no host IPC, ptrace or unconfined seccomp; bind mounts canonical, read-only and confined to the caller's model directory; images digest-pinned with an attestation; the gateway key never in argv, ledger, snapshot or log; state files private; `HF_TOKEN` never logged; root never trusting a user-writable file for identity or paths | marketplace #4097 and #5990, rounds 1 to 6 |
| Anything installed needs an uninstaller | dhh, omacom/omarchy#1519 |
| What merges is small; the route for a plugin into Omarchy is a package plus a ~100-line PR | omacom/omarchy#12157 (Elsewhen) |

## 2. The tree

```
omarchy-local-ai/                    the plugin directory as installed (marketplace) or packaged (omacom)
├── manifest.json                    schemaVersion 1, kinds ["bar-widget"], entryPoints.barWidget "Panel.qml"
├── Panel.qml                        the card, unchanged design                          ~450 lines
├── Model.js                         every pure function behind the card                 ~250 lines
├── recipes.json                     the registry's export, verbatim, one entry per line  (data)
├── bin/
│   ├── omarchy-local-ai             the backend, one file                               ~850 lines
│   ├── omarchy-install-ai-local     Install › AI: toolkit for NVIDIA, first snapshot     ~30 lines
│   └── omarchy-remove-ai-local      stop everything, remove containers, images, weights ~30 lines
├── test/
│   ├── all                          runs every test/shell.d/*-test.sh and reports 1..N
│   ├── base-test.sh                 verbatim copy of omarchy's test/shell.d/base-test.sh
│   └── shell.d/
│       ├── local-ai-hardware-test.sh      detection, matching, gating
│       ├── local-ai-weights-test.sh       plan, download, verification, resume, adoption
│       ├── local-ai-start-test.sh         start, acceptance, rollback, stop, prompt mode
│       ├── local-ai-priv-test.sh          the root boundary: target, caller, inputs, policy
│       ├── local-ai-agents-test.sh        one launch per agent, key never in argv
│       ├── local-ai-snapshot-test.sh      the record the card reads, size bound, atomicity
│       ├── local-ai-model-test.sh         run_node_test over Model.js
│       ├── local-ai-panel-test.sh         PlainText scan, manifest contract, no forbidden imports
│       └── fixtures/local-ai/             shims: docker, curl, nvidia-smi, lspci, pkexec, agents
├── Makefile                         sync, sync-check, check, bundle
├── .github/workflows/               test.yml, release.yml, registry.yml
├── LICENSE, README.md, CHANGELOG.md, preview.png
└── docs/design.md                   this file
```

Gone from the tree: `lib/` (13 files), `ui/` (two presentations), `native/`, `scripts/`, `integrations/`,
`wiki/`, `media/`, `dist/`, `lib/*.py`. The repository is the plugin and nothing else.

Line budget of what ships: about 1,600 lines of code (850 bash, 450 QML, 250 JS, 60 installers) and
one data file, against 3,884 today. The count is a consequence of the drop list in section 8, not a
target that was cut to.

## 3. `bin/omarchy-local-ai`

### 3.1 Header and shape

```bash
#!/bin/bash

# omarchy:summary=Run the validated local model for this machine's GPU and open coding agents on it
# omarchy:args=<snapshot|load <recipe> [gpu...]|unload [model]|agent <name> [model]|install|remove>
# omarchy:requires-sudo=true
```

Sections, in file order, each a comment banner as in `omarchy-windows-vm`:

| Section | Functions | Lines |
|---|---|---|
| constants and paths | `STATE`, `MODELS`, `RECIPES`, `LABEL`, `PORT`; root pins `PATH` and `LC_ALL` | 25 |
| common | `log`, `fail`, `now`, `state_dir` (0700), `ledger_read`, `ledger_write` (jq + `mktemp` + `mv`), `lock`, `spawn` | 70 |
| recipes | `recipe_by_id`, `recipes_for_hardware`, `policy_check` (the gate), `expand_mount` | 90 |
| hardware | `nvidia_gpus`, `intel_gpus`, `amd_gpus`, `gpus_json`, `match_hardware` | 110 |
| weights | `hub_tree`, `weights_plan`, `weights_present`, `weights_fetch`, `weights_verify` | 130 |
| privilege | `docker_needs_prompt`, `priv_target`, `priv`, `resolve_caller`, `validate_inputs` | 90 |
| containers (root phases) | `phase_start`, `phase_stop`, `phase_toolkit`, `start_pair`, `accept`, `rollback`, `owned` | 190 |
| agents | `AGENTS` table, `agent_argv`, `agent_launch` | 80 |
| snapshot | `models_json`, `cards_json`, `snapshot_write` | 90 |
| dispatch | `usage`, `case "$1"` | 40 |

Everything runs as the user except the three `__priv` phases. `set -euo pipefail` at the top; every
`$(...)` of a function that can fail is guarded (`x=$(f) || ...`), because under `set -e` an unguarded
failure exits the script without reaching the card.

### 3.2 Verbs

| Verb | Runs as | What it does |
|---|---|---|
| `snapshot` | user | pure read; rewrites `snapshot.json` and prints it |
| `load <recipe-id> [gpu-key...]` | user, detached worker | plan, fetch and verify weights, then one `priv start` |
| `unload [instance-id]` | user, detached worker | one `priv stop`; without an id, every running model |
| `agent <name> [instance-id]` | user | `exec omarchy-launch-tui` with the agent's argv (section 3.7) |
| `install` | user | NVIDIA hosts: one `priv toolkit`; then `snapshot` |
| `remove` | user | `unload`, then one `priv stop --purge` (containers, network, images) and delete `$MODELS` |
| `__priv <start\|stop\|toolkit> ...` | root, only via `priv` | section 3.5 |
| `__worker <load\|unload> ...` | user, detached | the body of `load` and `unload`; holds the lock |

The card issues `snapshot`, `load`, `unload` and `agent`. The menu entries issue `install` and `remove`.
`load` and `unload` return immediately after writing `op` into the ledger; the card sees `pending` on its
next snapshot. There is no `share`, `update`, `recipes update`, `gpu`, `agent-dir` or `agent-args` verb.

### 3.3 State

```
~/.local/state/omarchy/local-ai/        0700
├── state.json                          0600  the ledger: {op, slots, error, lastStartSeconds}
├── snapshot.json                       0600  what the card renders (section 5)
├── gateway.key                         0600  bearer secret; read with curl -H @file, never expanded
├── log                                 0600  one line per event, no secrets
├── trees/                              cached Hub file lists per repo@revision
└── agents/<name>/                      plugin-owned config dirs for agents that need one
~/.cache/omarchy/local-ai/models/<recipe-id>/   weights, one directory per recipe
```

`state.json` keeps the 5.x slot format (`engine`, `gateway`, `network`, `port`, `keys`, `recipeId`,
`baseRecipeId`, `startedAt`, `accepted`), so a 5.x `ledger.json` is adopted by rename on first run and a
model started by 5.x is seen, stoppable and reusable. `op` is `{name, recipeId, pid, startedAt, detail,
percent}`. Both files are written by `ledger_write` through `mktemp` in the state directory and `mv`.

### 3.4 Hardware

One detector per vendor, each printing one JSON object per GPU:
`{key, index, backend, product, vramGb, renderNode, driver, hardwareId}`.

- NVIDIA: `nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader`.
- Intel: `/dev/dri/by-path/pci-*-render` resolved to a device, product from `lspci -d 8086:` at that BDF.
- AMD: `amd-smi static --json` only. The `rocm-smi` and sysfs paths are gone.

`match_hardware` normalises the product name (lowercase, alphanumerics only) and looks it up in
`recipes.json` `.hardware[].match.names` with the same `backend`; `vramGb` breaks ties. A GPU with no
entry is reported with `hardwareId: ""` and the card says "no validated recipe for <product>". No tier or
family inference exists.

### 3.5 The root boundary

Copied from `omarchy-windows-vm`, reduced to what this feature needs.

```bash
priv() {                                   # priv <phase> <args...>: one prompt, or none in sudoless mode
  local target
  if ! omarchy-sudo-docker; then __priv_"$1" "${@:2}"; return; fi
  target=$(priv_target) || { fail "refusing to run a script root could not trust"; return 1; }
  pkexec "$target" __priv "$@"
}
```

- `priv_target` prefers `/usr/bin/omarchy-local-ai` when it exists, is a regular file, is root-owned and
  is not group- or world-writable on any path component (the packaged case). Otherwise it is this
  script's own canonical path (the marketplace case), which the prompt names. A `PATH`-resolved name is
  never used.
- As root, `resolve_caller` takes `PKEXEC_UID`, reads the account from `getent`, requires the home to be
  a directory the caller owns and not reached through a symlink, and sets `CALLER_UID`, `CALLER_GID`,
  `CALLER_HOME`. `MODELS` and `STATE` are derived from `CALLER_HOME` only.
- `validate_inputs`: the recipe id matches `^[a-z0-9][a-z0-9.-]{0,63}$`; each GPU key matches
  `^(nvidia|intel-xpu|amd-rocm):[0-9]{1,2}$`; nothing else crosses the boundary. There is no `root.env`,
  no `OMARCHY_AI_RUN_AS`, no hash on the command line: the caller comes from pkexec, and every path from
  the caller.
- The recipe is read from `RECIPES` next to the script. When packaged that file is root-owned. In the
  marketplace case it is user-owned, and root does not need it to be trusted: `policy_check` runs on it
  again as root, and the policy is fixed in the script. A recipe can only ever produce a container with a
  digest-pinned image from `ghcr.io/0xsero/`, no `--privileged`, no `--cap-add`, no `--ipc host`, no
  `--pid host`, no `--security-opt`, `--network` on a private bridge with no published port, and mounts
  drawn from exactly two templates: `${MODEL_ROOT}/<recipe-id>` read-only and `/dev/dri/by-path`
  read-only. `--device` entries are the caller's GPU render nodes only. Anything else is refused with a
  reason before docker is called. A swapped recipe therefore cannot widen what root does.
- Phases:
  - `start <recipe-id> <gpu-key...>`: create the network if absent; rename a running pair on the same
    cards to `-previous`; `docker run` the engine (`--user CALLER_UID:CALLER_GID`, labels
    `io.omarchy.local-ai=1`, `.recipe`, `.role`), then the gateway on `127.0.0.1:<port>`; wait for the
    gateway to answer; `accept`; on success remove `-previous`, on failure remove the new pair, restore
    `-previous`, and print `reason <sentence>`. Progress lines `step <word>` go to stdout, where the user's
    worker turns them into `op.detail`.
  - `stop [instance-id] [--purge]`: stop and remove the labelled pair(s) and their network; with
    `--purge` also the images and any `-previous` leftovers. Only containers carrying the label are ever
    touched.
  - `toolkit`: `omarchy-pkg-add nvidia-container-toolkit`, `nvidia-ctk runtime configure --runtime=docker`,
    `systemctl restart docker`. NVIDIA hosts only, and only when `docker info` lacks the runtime.
- Root writes nothing under the caller's home. Acceptance runs as root because it must be inside the one
  prompt, reading the key with `curl -H @"$STATE/gateway.key.header"`, a 0600 file the user's worker
  wrote before prompting.

### 3.6 Weights

As the user, never root, with the tools Omarchy already ships.

1. `hub_tree <repo> <revision>` fetches `https://huggingface.co/api/models/<repo>/tree/<revision>?recursive=1`
   once per revision into `trees/` and yields `path size sha256`.
2. `weights_plan` selects the files (the recipe's `weights.subdir` or pattern), sums their size, checks
   free space on `$MODELS`, and prints the plan into `op.detail` ("Qwen3.8-27B · 19 GB").
3. `weights_fetch` downloads each missing file with
   `curl -fL --retry 3 -C - -H @"$HF_HEADER" -o <path>.part https://huggingface.co/<repo>/resolve/<revision>/<path>`
   and renames it on completion, so a stopped download resumes. `HF_HEADER` is a 0600 file holding
   `Authorization: Bearer …` when `HF_TOKEN` is set; the token never appears in argv or the log.
4. `weights_verify` compares `sha256sum` of every file against the tree and deletes any mismatch. A
   directory that verifies is marked with `.verified@<revision>`; the next `load` skips the download.

The engine image is not used for downloading, and `hf` is not required. Model files from another
tool are never adopted unverified.

### 3.7 Agents

A table replaces the per-agent case block. Every agent gets the same three facts: the endpoint, the
key file, the model name. The differences are which variables carry them and whether a plugin-owned
config directory is needed.

| Agent | Endpoint variable | Key variable | Extra |
|---|---|---|---|
| claude | `ANTHROPIC_BASE_URL` | `ANTHROPIC_AUTH_TOKEN` | `ANTHROPIC_MODEL` and the three default-model variables |
| codex | `-c model_providers.local.base_url=` | `LOCAL_AI_KEY` via `env_key` | `-c model_provider=local -c model=<m>` |
| opencode | inline `OPENCODE_CONFIG_CONTENT` | `OMARCHY_LOCAL_AI_KEY` via `{env:…}` | `--model omarchy-local/<m>` |
| pi, omp | `models.json` in `agents/<name>/` | inside that file (0600, plugin-owned) | `PI_CODING_AGENT_DIR` / `OMP_CODING_AGENT_DIR` |
| crush | `crush.json` in `agents/crush/` | inside that file | `XDG_CONFIG_HOME` and `XDG_DATA_HOME` pointed at it |
| grok | `config.toml` in `agents/grok/` | `XAI_API_KEY` | `GROK_HOME` |
| copilot | `COPILOT_PROVIDER_BASE_URL` | `COPILOT_PROVIDER_API_KEY` | `--model <m>` |
| hermes, ori, agy, muse, cursor-agent | `OPENAI_BASE_URL` | `OPENAI_API_KEY` | `OPENAI_MODEL` |

The key reaches the agent through its environment or a plugin-owned 0600 file, never through argv. No
file the user owns is read or written: the finding that required "clear opt-in before modifying
third-party agent configs" is met by not modifying any. Launch is
`exec omarchy-launch-tui --app-id=org.omarchy.local-ai env VAR=… <agent> <args>` from the project directory
the card shows. Which agents are launchable follows from the model's accepted dialects: `chat` for all,
`messages` for claude, `responses` for codex.

### 3.8 Snapshot

`snapshot_write` produces the record in section 5 from the ledger and reality:

- with the socket reachable (`omarchy-sudo-docker` fails), each slot is checked with `docker inspect`;
- otherwise the gateway answering on its port is the evidence, and docker is never called from a read.

The record is bounded: the producer writes through `head -c 262144` and the card refuses a larger file.
The Hub, GitHub and the registry are never contacted from `snapshot`.

## 4. `manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "sero.local-ai",
  "name": "Local AI",
  "version": "6.0.0",
  "author": "Sero",
  "license": "MIT",
  "description": "<the marketplace pitch, ≤ 500 characters, names the hardware and recipe count>",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Panel.qml" },
  "barWidget": {
    "displayName": "Local AI",
    "description": "The model validated for your GPU, one click, and every coding agent on it.",
    "category": "AI",
    "aliases": ["local-ai", "local-model"],
    "allowMultiple": false,
    "defaults": { "projectDir": "" },
    "schema": [
      { "key": "projectDir", "type": "path", "label": "Project folder for agents", "defaultValue": "" }
    ]
  }
}
```

When omacom packages the plugin the id becomes `omacom.local-ai`; nothing in the tree depends on the id.

## 5. The record the card reads (`snapshot.json`)

`schemaVersion: "omarchy-local-ai/snapshot/11"`. Fields the card renders today are kept with their
names; fields of dropped features are removed (`share`, `update`, `registryFile`, `gpuUsage`,
`decodeTps`, `prefillTps`, `tokensToday`).

```
state        idle | download | starting | ready | unload | error
error        one sentence, or ""
operation    {name, recipeId, detail, percent, startedAt, expectedSeconds}
statusText   "" or a short status the card shows in its subtitle ("Setup required", "Unsupported GPU")
helpText     "" or the one sentence that tells the user what to do
hardwareId   the matched id, or ""
gpus         [{key, index, backend, product, vramGb, renderNode, driver, hardwareId, chosen}]
cards        one per GPU type: {hardwareId, backend, product, name, vramGb, count, totalGb, keys, recipe, claimed, idle}
recipes      one per recipe of a detected card: {id, name, engine, sizeGb, precision, ctxTokens, kvTokens, caps, onDisk, partialBytes, hardwareId, cards, claims, recommended, running}
models       one per slot: {recipeId, baseRecipeId, name, port, endpoint, keys, cards, state, note, servedModel, apis, caps, ctxTokens, kvTokens, acceptedAt, startedAt, launchable}
running      the focused model {recipeId, name, cards, port, state} or null
selected     the recipe the card looks at, or null
agents       {default, directory, installed, launchable}
port         {number, busy, listener}
registry     {commit, generatedAt}
updatedAt
```

`statusText` and `helpText` are the Agents-panel pattern: the backend decides the words, the card only
shows them. "Docker is not running", "Install the NVIDIA container toolkit from Install › AI", "Another
program is using port 12434" all arrive this way.

## 6. `Panel.qml` and `Model.js`

`Panel.qml` is the standalone card of 5.4.0 with these changes only:

- it no longer knows two presentations; `embedded`, `embeddedActive`, `overlayHost` and the native
  `Loader` contract are gone;
- rows for share and update are gone with their features;
- theming uses exactly the Agents panel's contract (`bar.foreground`, `bar.urgent`, `bar.fontFamily`,
  `Color.popups.background`, `Color.accent`, `Style.selectedFillFor`, `Style.space`);
- `FileView { path: stateDir + "/snapshot.json"; watchChanges: true; onFileChanged: reload() }` is the
  only input; `Process { command: [cli].concat(args) }` and `bar.run(cli + " agent " + name)` are the
  only outputs; a 60 s idle poll and a 1 s pending poll call `snapshot`;
- every `Text` whose `text` is not a literal declares `textFormat: Text.PlainText`;
- `import "Model.js" as Model`.

`Model.js` holds what `ui/ui.js` holds today, minus share, update and telemetry: `gb`, `kb`, `mmss`,
`ago`, `capabilityWords`, `opWord`, `models`, `cardByHw`, `freeKeys`, `loadPlan`, `fits`, `where`,
`cardRows`, `launchRows`, `buildView`. It ends with
`if (typeof module !== "undefined") module.exports = { … }` and has no Qt reference, so
`run_node_test` exercises every view against fixture snapshots.

## 7. `recipes.json`

The registry's `plugin/recipes.json`, taken verbatim by `make sync` and written one hardware entry per
line:

```
{"schemaVersion":"omarchy-local-ai/recipes/1","registryCommit":"…","generatedAt":"…",
 "gateway":{…},
 "assets":{
  "qwen3827b-exl3-4bpw-128k-q4-tabbyapi-config.yml":"…",
  …},
 "hardware":{
  "rtx-4090-24gb":{"match":{…},"recipe":{…},"recipes":[…]},
  "rtx-5090-32gb":{…},
  …}}
```

A recipe change is a one-line diff, and the file is small enough to read in a review. `make sync-check`
compares content with the two provenance fields removed, as today. The registry remains the only place a
recipe is authored or validated; this repository never edits one. The daily `registry.yml` job commits the
export when it moves. There is no runtime fetch: an installed copy changes only when the plugin (or the
package) updates.

## 8. What is dropped, and where it went

| Dropped | Why | Where it lives now |
|---|---|---|
| runtime recipe fetch and staged update (`lib/update.sh`, `recipes_fetch`) | a fetched file can never feed the root phase; Omarchy updates packages, the marketplace updates clones | git history |
| plugin self-update | same | git history |
| Tailscale share (`lib/share.sh`) | a second privilege surface; Omarchy's own tailscale panel owns tailnet exposure | git history |
| telemetry adapters (`lib/intel-metrics.py`, `lib/runtime-metrics.py`) | 293 lines of Python for meters; VRAM is in the engine's own logs | git history |
| "load another instance", swap previews, set-aside of a different card's model | one model per GPU group is the frame; start replaces what is on those cards, with rollback | git history |
| `rocm-smi` and sysfs AMD paths | `amd-smi` is enough | git history |
| the native generator, `native/backend-command.js`, the embedded presentation | one copy of the card | git history; the closed PR's QML is tagged `archive/native-local-ai-agents` on the fork |
| `integrations/` | one person's desktop | `~/local-omarchy/moonlight/` |
| `wiki/`, `media/`, `dist/`, `docs/preview.py` | not the plugin | git history |
| `hf`-in-container download | curl and sha256 do it with what Omarchy ships | replaced by section 3.6 |
| hash-pinned `root.env` and recipe hash on the pkexec line | identity comes from pkexec, paths from the account, policy from the script | replaced by section 3.5 |

## 9. Tests

`test/all` runs every `test/shell.d/*-test.sh` and prints `1..N`; each file uses the copied
`base-test.sh` (`pass`, `fail`, `require_command`, `run_node_test`). The 5.4.0 suite's 243 assertions
are re-homed by area into the eight files in section 2, with the shims in `fixtures/local-ai/`:

- `docker` records argv to a log and answers `inspect`, `ps`, `run`, `rm`, `network` from a fake state
  file; in prompt mode it refuses when not called through the `pkexec` shim;
- `pkexec` runs the target with `env -i` and `PKEXEC_UID`, so the boundary is really crossed;
- `curl` serves the Hub tree, file downloads with known sha256, and the gateway's `/v1/models` and
  `/v1/chat/completions` from fixtures, and asserts that no `Authorization:` value is in its argv;
- `nvidia-smi`, `lspci`, `amd-smi` return fixture hardware;
- agents are stub executables that dump their environment and argv.

Every security finding from the six review rounds is one named assertion: key never in argv (GET and
POST), state files 0600, symlinked home refused, foreign recipe id refused, `--ipc host` refused,
mount outside the model directory refused, unpinned image refused, oversized snapshot refused, token
absent from the log.

`local-ai-panel-test.sh` runs the same scans Omarchy runs on its own plugins: `textFormat` on every
non-literal `Text`, the manifest contract, and no import outside Quickshell and the shell's `Ui`.

CI (`test.yml`) runs `bash test/all` on `ubuntu-latest` and `make check`. On this Mac run the suite with
`TMPDIR=/private/tmp`, because `mktemp` returns `/var/…` while `readlink -f` returns `/private/var/…`.

## 10. Release and delivery

- A release is one commit "Release vX.Y.Z" (manifest version, changelog section, tag). `release.yml`
  runs the suite against the bundle it publishes. 6.0.0 is the first release of this tree; it is a major
  because the state files and the verbs change.
- The marketplace listing (#5990) is retargeted to the 6.0.0 tag. The box and pop-os move to 6.0.0 with
  `omarchy plugin update sero.local-ai --yes` after a live prompt-mode run.
- The PR to omacom/omarchy is the Elsewhen route, about 100 lines: a package line, a 14-line migration
  that symlinks the packaged plugin and runs `omarchy-bar put`, a `shell.json` default, Install › AI and
  Remove › AI menu entries pointing at `omarchy-install-ai-local` and `omarchy-remove-ai-local`, a
  paragraph under "Local LLMs" in `manual/17-ai.md`, and a migration test modelled on
  `elsewhen-default-migration-test.sh`. Opt-in (menu entries only) is the smaller first ask and is what
  the PR proposes; the migration is offered in the description as the follow-up.

## 11. Order of work

1. `bin/omarchy-local-ai`: write it top to bottom from section 3, porting functions from `lib/` where
   they already satisfy the design, and the shim tests alongside each section.
2. `Model.js` from `ui/ui.js`, then `Panel.qml` from `ui/Panel.qml`, with the node and panel tests.
3. `recipes.json` formatter in `make sync`; `registry.yml` unchanged.
4. Installers, README, CHANGELOG 6.0.0, `preview.png` recaptured from a host on 6.0.0.
5. Live run on the box in prompt mode (the polkit rule trick in the skill), then on pop-os.
6. Release 6.0.0, retarget the listing, open the upstream PR.
