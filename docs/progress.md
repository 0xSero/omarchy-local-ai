# Local AI: state and redesign

Rewritten 2026-09-22 after the consolidation pass. When this file and a repository disagree, the
repository is right.

## 1. What exists now (after cleanup)

| Directory here | Role | Edited? |
|---|---|---|
| `omarchy-local-ai` | **the live plugin** (marketplace `sero.local-ai`, v5.4.0). Card + backend + vendored recipes. Installed on the omarchy box and pop-os at this commit. | yes, but only on `main`, and nothing is pushed until a release is decided |
| `local-ai-registry` | **the data.** Recipes are authored, validated and exported here. `plugin/recipes.json` is the published export. | only for recipes (the checkout is 21 commits behind with 44 dirty files: your work, untouched) |
| `local-ai-images` | attested engine and gateway images, pinned by digest | rarely |
| `moonlight` | **new.** Your personal integrations (Moonlight bindings, macOS shortcut button and guide, the old Agents-panel patch and installer), moved out of the plugin | yours |
| `omarchy-native-local-ai` | worktree of the fork, branch `native-local-ai-agents`, the closed PR #12845. Kept only because it holds the card QML the redesign reuses. | no |
| `attic/omarchy-checkout-2026-09-22` | untracked leftovers swept out of `~/omarchy` (old `omarchy-serve-*` scripts, `plans/local-ai-registry`, `prod/`, a system map html). Delete when sure. | no |
| `harness-bridge`, `exo` | unrelated to this work | no |

`~/omarchy` (the fork checkout) is now clean, on `quattro`, with one worktree (`native-local-ai-agents`).

## 2. What was closed out today

| Item | Action |
|---|---|
| omacom/omarchy PR #12845 (draft, card-only, needed the plugin as backend) | closed with a comment; a single PR follows the redesign |
| omacom/omarchy PR #10643 (4,871-line vendored copy) | already closed as superseded |
| Fork branches `local-ai`, `local-ai-fixes`, `local-ai-v4`, `codex/localai-cli`, `feature/local-ai-plugin`, `cursor/local-ai-plugin-dc5e` | tagged `archive/<name>` on the fork, then deleted (local and remote) |
| Fork branch `native-local-ai-agents` | tagged `archive/native-local-ai-agents`, kept |
| `integrations/` in the plugin | moved to `moonlight/`; Makefile, bundle test, README, design doc and changelog updated; committed on `main`, **not pushed** |
| Nine old `0xSero/local-ai-*` repos from 2026-09-03 | already archived, nothing to do |

Still open, on purpose:

| Item | Why it stays open |
|---|---|
| marketplace issue #5990 (`needs-fixes`, target v5.4.0) | it is the live plugin's pending update; closing it abandons the listing update |
| plugin PR #15 and issue #12 (AlucarDWeb, AMD RX 7600 recipe) | an outside contributor authoring a recipe in the wrong repo; answer by pointing at the registry, do not merge into the plugin |
| registry PRs #73, #74 (Ornith recipes, green) | your own recipe work |
| marketplace PR #7346 (icon in the title tile) | unrelated to the plugin |

## 3. Why it got confusing

Three copies of one thing and a generator between them:

1. the card in the plugin (`ui/`, standalone popup **and** embedded presentation, 945 lines),
2. the same card generated into Omarchy's Agents panel (PR #12845, 852 lines) with a shim to find the backend,
3. the backend vendored only in the plugin (2,484 lines), reached by the Omarchy copy through the plugin registry.

Plus recipes vendored in the plugin, re-fetched at runtime from GitHub, and re-synced by a daily bot, three
mechanisms for one file. Plus five fork branches of earlier attempts.

## 4. Evidence: what Omarchy is, measured on 2026-09-22

Everything here was read from `omacom/omarchy` at `947e2fc0` (upstream `quattro`, fetched today) and from
GitHub through `gh`. Numbers are from the last 200 merged PRs (2026-08-13 to 2026-09-22).

| Question | Finding | Where |
|---|---|---|
| How big is a merged feature PR? | median **57** added lines, p90 572. Every merged PR above ~1,000 lines is a release, a security hardening, or maintainer/bot-authored agent work. #10643 (+4,871) was larger than any PR merged in the window. | `gh pr list --state merged` |
| Did a maintainer ever engage with the Local AI PRs? | No. Six PRs (#8193, #8309, #8694, #8836, #10643, #12845): zero comments, reviews or labels from dhh, ryanrhughes, spencerbull or acrogenesis. All six were closed by us. | PR threads |
| What does dhh think local models are for? | The manual defines AI as coding agents. Its whole "Local LLMs" section is two sentences pointing at LM Studio and Ollama. On Ollama: "Not sure there's enough value there" (#1519); he also required an uninstaller for anything installed. | `manual/17-ai.md`, #881, #1519 |
| How does a plugin become part of Omarchy? | The Elsewhen precedent (#12157, +108 lines, merged silently): a package `elsewhen` in the omacom repos, `omacom.elsewhen` under `/usr/share/omarchy/shell/plugins/`, a 12-line migration that symlinks it into `~/.config/omarchy/plugins/` and runs `omarchy-bar put`, one line in `install/omarchy-base.packages`, one default entry in `config/omarchy/shell.json`. | `migrations/1790042972.sh` |
| How does Omarchy run Docker? | Users are **not** in the docker group (#8056: the group is root-equivalent). `omarchy-sudo-docker` answers "does this session need a prompt". `omarchy-windows-vm` (1,614 lines, one bash file) re-execs itself as `pkexec /usr/bin/omarchy-windows-vm __priv <action>` for one prompt per action, pins PATH and locale as root, derives the caller from `PKEXEC_UID`, refuses symlinked or non-caller-owned homes, and only ever lets root consume files in a root-owned tree. It has 700 lines of shim tests. | `bin/omarchy-windows-vm:1-200`, `test/shell.d/windows-vm-*` |
| GPU in containers? | Never done anywhere in Omarchy. `nvidia-container-toolkit` is not packaged. | grep of `bin install config shell` |
| How does a bar panel get data? | Agents panel: bash collectors write one JSON record per provider under `~/.local/state/omarchy/agents/usage/`, atomically (`mktemp` + `mv`); QML watches with `FileView { watchChanges: true }`; setup states are two strings in the record (`usageStatusText`, `authHelpText`) rendered by generic QML. Tailscale panel: `Process` polling plus one `pkexec tailscale set --operator` for a one-time grant. | `shell/plugins/agents/Main.qml`, `panels/tailscale/Service.qml:348` |
| Script conventions | `#!/bin/bash`, `[[ ]]` and `(( ))`, two-space indent, `omarchy-cmd-missing` / `omarchy-pkg-add` instead of `command -v` / `pacman`, `# omarchy:summary=` mandatory, `# omarchy:requires-sudo=true`, no `lib/` (every script self-contained), median script 28 lines. Tests: `test/shell.d/<name>-test.sh`, median 88 lines, `base-test.sh` preamble, shims by prepending a scratch `bin/` to PATH, never docker or network. Pure logic in a `Model.js` with `module.exports` for node tests. | `AGENTS.md`, `docs/testing.md`, `test/shell.d/bin-style-test.sh` |
| Plugin ids | `omarchy.*` is reserved for in-tree plugins; packaged default plugins use `omacom.*`. `schemaVersion` 1, required `id name version kinds entryPoints`. | `bin/omarchy-plugin-validate:53`, `PluginRegistry.qml:52` |
| Security review already paid for | Six rounds on the marketplace required: no host IPC / ptrace / unconfined seccomp; canonical, read-only, narrowly-owned bind mounts; digest-pinned images with a GitHub attestation; a bounded snapshot producer; the gateway key never in argv, ledger, snapshot or logs (`curl -H @file`); private state modes; `HF_TOKEN` never logged; root never trusting a user-writable file (the `root.env` finding). | marketplace #4097, #5990 |

Two conclusions follow directly:

1. **A 1,000-line self-contained Local AI PR has no precedent of being merged and no maintainer signal
   behind it.** The size that merges is ~100 lines, and the route that exists for a plugin is Elsewhen's.
2. **Vendored recipes are the security design, not just the simple one.** In the Windows VM script root
   only consumes a root-owned compose. A recipe fetched at runtime into the user's home can never be the
   input to a root `docker run` without reopening the file-swap-to-root hole the reviewer found. A recipe
   file that is part of the package under `/usr/share/omarchy` is root-owned, so root can read it directly,
   and the whole hash-pinning-on-the-pkexec-command-line layer in `lib/priv.sh` becomes unnecessary.

## 5. The design

The full repository design is `omarchy-local-ai/docs/design.md` (version 6). This section is the summary.

**One product, shaped like Omarchy, delivered two ways.** The product is the plugin, restructured until
it looks like something Omarchy wrote. Delivery to Omarchy is then the ~100-line Elsewhen route, and the
marketplace listing keeps shipping the same tree in the meantime. Building it does not wait on maintainers.

```
omarchy-local-ai (repo → package "omarchy-local-ai", installed under /usr/share/omarchy)
  bin/omarchy-local-ai                 ONE bash file, windows-vm style              ~850 lines
  bin/omarchy-install-ai-local         Install › AI entry: toolkit + first snapshot  ~30 lines
  bin/omarchy-remove-ai-local          the uninstaller dhh asks for                 ~30 lines
  shell/plugins/omacom.local-ai/
    manifest.json                      schemaVersion 1, kinds ["bar-widget"]
    Panel.qml                          THE CARD, design unchanged                   ~450 lines
    Model.js                           row/plan/label logic, node-testable          ~250 lines
    recipes.json                       the registry export, verbatim, one entry per line (data)
  test/shell.d/local-ai-test.sh        shim tests in Omarchy's own form
  test/shell.d/local-ai-model-test.sh  run_node_test over Model.js
```

### 5.1 The backend: `bin/omarchy-local-ai`

Modelled line for line on `omarchy-windows-vm`, because that is the one Docker feature Omarchy has
merged and hardened.

| Concern | Design | Omarchy evidence |
|---|---|---|
| Shape | one self-contained file, no `lib/`; header `# omarchy:summary=`, `# omarchy:args=<snapshot|load [recipe] [gpu]|unload|agent <name>>`, `# omarchy:requires-sudo=true`; group `local` in `GROUP_DESCRIPTIONS` | `AGENTS.md`, `docs/cli-router.md` |
| Privilege | `priv()`: if `omarchy-sudo-docker` says no prompt is needed, run the phase directly; else `pkexec /usr/bin/omarchy-local-ai __priv <phase> <recipe-id> <gpu-index>`. As root: pin PATH and `LC_ALL`, `resolve_caller` from `PKEXEC_UID` with the home-ownership and symlink checks copied from windows-vm, inputs validated by regex (`[a-z0-9-]+`, `[0-9]+`), recipe read **only** from the packaged root-owned `recipes.json`. No `root.env`, no hash pinning: there is no user-writable input left. | `bin/omarchy-windows-vm:76-200`, `bin/omarchy-sudo-docker` |
| Phases behind one prompt | `start` (network, engine, gateway, acceptance, rollback), `stop`, `toolkit` (NVIDIA only: `omarchy-pkg-add nvidia-container-toolkit`, `nvidia-ctk runtime configure`, restart docker) | plugin `lib/priv.sh` phases, reduced |
| Containers | one engine on a private bridge network, port never published; the attested gateway on `127.0.0.1:12434` with `--user <caller uid>`; labels `io.omarchy.local-ai=1/.recipe/.role`; only labelled containers ever touched; digest-pinned images only; no `--ipc host`, no `cap-add`, no `seccomp=unconfined`; mounts limited to the caller's model dir (read-only) and `/dev/dri/by-path` (read-only) | reviewer rounds 1 to 3; `runtime.sh` header |
| Weights | downloaded **as the user** (never root) with `curl` from the Hub at the pinned revision, verified against the LFS sha256 of each file, into `~/.cache/omarchy/local-ai/models/<recipe>`; partial files resumed; `HF_TOKEN` passed as a header file, never logged | reviewer round 4; Omarchy ships curl and jq, not `hf` |
| Acceptance | one chat completion through the gateway with a floor on tokens and speed, rollback to the previous container on failure; the key via `curl -H @file` | reviewer round 5 |
| State | `~/.local/state/omarchy/local-ai/` mode 0700: `state.json` (ledger, 0600), `snapshot.json` (what the card renders, written with `mktemp` + `mv`), `gateway.key` (0600), `log`. The snapshot carries `statusText` / `helpText` like an Agents record so the card needs no error logic. | `omarchy-agent-usage-update:49-51`, Agents `usageStatusText` |
| Hardware | `nvidia-smi` for NVIDIA, `/dev/dri/by-path` plus `lspci` for Intel, `amd-smi` only for AMD; match by exact hardware id from `recipes.json`; a card not in the file is "unsupported" on the card | plugin `lib/hardware.sh`, trimmed to one path per vendor |
| Agents | a table of the thirteen agents the manual lists, exporting the OpenAI-compatible base URL and the key file to the agent's environment and `exec omarchy-launch-tui`; no agent config file is ever edited (the reviewer's "clear opt-in" finding, solved by not writing) | `manual/17-ai.md`, `bin/omarchy-agent:108`, reviewer round 3 |
| Long operations | `setsid` a detached worker of the same script; the card polls the snapshot | plugin `spawn()` |

Dropped from the product, on evidence, not taste: runtime recipe fetch and self-update (a fetched file
can never feed root; Omarchy updates the package), Tailscale share (a second privilege surface; Omarchy's
tailscale panel already owns tailnet exposure), the Python telemetry adapters (VRAM comes from the
engine), "load another instance" and swap previews (one model per GPU group is the manual's frame), two
of three AMD paths, and the generator/shim pair (one copy of the card).

### 5.2 The card: `shell/plugins/omacom.local-ai/`

The design does not change. What changes is where the logic lives and how it is fed.

- `Panel.qml` is the standalone presentation that exists today, using only the theming contract the
  Agents panel uses (`bar.foreground`, `bar.urgent`, `Color.popups.background`, `Style.selectedFillFor`,
  `Style.space`, `bar.fontFamily`), `textFormat: Text.PlainText` on every non-literal `Text`.
- Data arrives by `FileView { path: stateDir + "/snapshot.json"; watchChanges: true }`, actions go out by
  `Process { command: ["omarchy-local-ai", verb, ...] }` and agent launches by `bar.run(...)`. That is the
  Agents panel's read model plus the Tailscale panel's action model.
- `Model.js` holds every pure function now in `ui/ui.js` (rows, plans, fits, labels) with
  `module.exports`, so the tests run under node the way Omarchy's do.
- Placement: its own bar widget, put before `omarchy.agents` by the migration, exactly like Elsewhen before
  the clock. Becoming a tab inside the Agents panel would need in-tree QML (the 81-line `Panel.qml` change in
  #12845) and is therefore a later, separate, small PR once the widget is in.

### 5.3 The data

`recipes.json` stays the registry's export, verbatim, so the registry remains the only place a recipe is
authored and validated. It is committed one hardware entry per line (a recipe change is a one-line diff)
and ships inside the package under `/usr/share/omarchy`, root-owned. Updates reach users through
`omarchy-update`, the same way every other Omarchy file does. The daily registry-to-plugin bot commit
stays; a package release is cut when it moves.

### 5.4 The PR to Omarchy (the Elsewhen route, ~100 lines)

| File | Lines | Content |
|---|---|---|
| `install/omarchy-base.packages` | 1 | `omarchy-local-ai` (or an Install › AI entry instead, if opt-in is preferred) |
| `migrations/<ts>.sh` | ~14 | `omarchy-pkg-add`, symlink `/usr/share/omarchy/shell/plugins/omacom.local-ai` into `~/.config/omarchy/plugins/`, `omarchy-shell -q shell rescanPlugins`, `omarchy-bar put omacom.local-ai --before omarchy.agents` |
| `config/omarchy/shell.json` | 3 | the default bar entry |
| `default/omarchy/omarchy-menu.jsonc` | ~6 | Install › AI › Local AI, Remove › AI › Local AI |
| `manual/17-ai.md` | ~6 | a paragraph under "Local LLMs" |
| `test/shell.d/local-ai-default-migration-test.sh` | ~70 | mirrors `elsewhen-default-migration-test.sh` |

It needs the package to exist in the omacom repositories, which is a maintainer decision. If they prefer
opt-in, the migration line becomes an Install › AI entry and the PR shrinks further. The whole PR is in the
size band that merges, and it asks the maintainers for one thing: to package a tree that already follows
their rules.

### 5.5 What this means for the live plugin

The marketplace plugin keeps working as it is until the restructured tree is green. The restructure is a
major release (6.0.0): same card, same recipes, one script, no runtime fetch (users run
`omarchy plugin update`, which is what the marketplace documents anyway). The box and pop-os stay on 5.4.0
until then. Nothing changes for anyone by surprise.

### 5.6 Decisions needed

1. Accept the drop list in 5.1 (share, telemetry, multi-instance, extra AMD paths, runtime fetch).
2. Placement: own bar widget before Agents (recommended, zero in-tree QML) or a tab inside Agents (needs
   in-tree QML, later).
3. Default install (base package + migration) or opt-in (Install › AI). Recommendation: opt-in first; it is
   the smaller ask and matches how OpenClaw and Ollama are offered today.

### 5.7 Order of work

1. Restructure the plugin repo into the tree in section 5: one script, one panel, `Model.js`, vendored
   recipes, upstream-style tests. Keep every reviewer finding as a test.
2. Port the plugin's 243 assertions into `test/shell.d/` form; run them on the box in prompt mode.
3. Release 6.0.0, retarget the listing.
4. Open the ~100-line PR with the migration, the menu entries and the manual paragraph.

## 6. Commands

```bash
# repo state
for r in omarchy-local-ai local-ai-images; do git -C ~/local-omarchy/$r status -sb | head -1; done
git -C ~/omarchy branch; git -C ~/omarchy worktree list      # quattro is now current with upstream

# plugin suite (macOS: run with TMPDIR=/private/tmp, because mktemp returns /var/... and readlink -f gives /private/var/...)
cd ~/local-omarchy/omarchy-local-ai && TMPDIR=/private/tmp bash test/all > /tmp/suite.log 2>&1; tail -1 /tmp/suite.log

# machines
ssh omarchy 'cd ~/.config/omarchy/plugins/sero.local-ai && git log --oneline -1 && jq -r .version manifest.json'
```
