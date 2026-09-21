# Local AI for Omarchy

Run validated local models, open coding agents and share endpoints from the Omarchy bar.

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai.git --enable
```

Click the new bar icon, choose a free GPU group and recipe, then press **Run**. The card shows the download size, context and capabilities before launch. When it says **ready**, the model has passed its acceptance checks.

## How it works

1. **Start** downloads the model validated for the card you picked, pulls its engine image, proves the model answers (correct model, keyed, fast enough, all three API dialects, a real tool call), and serves it on `127.0.0.1:12434`. Start another recipe on another card and it runs alongside on the next port; the card lists every running model with its own open-agent and stop.
2. **Open agent** starts any installed coding agent on it: claude, codex, pi, omp, opencode, ori, grok, agy, hermes, copilot, crush. The endpoint and key travel in the agent's environment. The launcher keeps its provider settings under plugin-owned state; it does not rewrite your normal agent configuration.
3. **Share on Tailscale** publishes the same keyed endpoint on your tailnet address. One click, no `tailscale serve`, no root.

Each GPU type opens its running models and compatible model list. Select a model
to reveal its Load action directly underneath, or open a running model for its agent,
stats and Stop controls. The overview keeps the selected agent's Open button visible.
Every breadcrumb is clickable, so you can jump straight to a GPU group or home.
The whole page scrolls, including folder editing and bottom actions. **Home/End** and
**Page Up/Down** navigate the viewport; **F11** expands the standalone panel.

Home also carries one **update** row. A background check reads the registry's recipe file and this plugin's own manifest, and the row appears when either has something newer — the plugin version, and how many new recipes are for the cards you actually have. Nothing is installed behind your back: pressing it applies the new recipes and updates the plugin through `omarchy plugin update`. With nothing to apply the row is just a re-check.

## Native Agents panel and Moonlight

To place Local AI inside Omarchy's existing Agents view, update the installed plugin,
then run on Omarchy:

```bash
omarchy plugin update sero.local-ai --yes
cd ~/.config/omarchy/plugins/sero.local-ai
python3 integrations/install-agents.py --moonlight
```

Omit `--moonlight` to keep your desktop keybindings. This uses the installed Agents panel, adds Local AI controls, and replaces its bar entry with a local customization.
A separate keyboard button in the OS bar opens the cheat sheet. System files
are unchanged; the installer prints the configuration backup location. It refuses
an incompatible native panel instead of applying a partial patch. Reapply after
an Omarchy update if you want the updated native panel.

The optional Moonlight shortcuts use **Ctrl+Space**, release, then **K** for help,
**I** for Local AI, **Enter** for a terminal, or **1–9 / 0** for workspaces.
**Ctrl+F1** opens the cheat sheet directly. Ordinary Ctrl shortcuts in apps remain
available. **Command+W** closes an app tab (a window in Foot); **Command+D**
bookmarks in browsers or opens another tiled terminal in Foot. Common Command
shortcuts for copy, paste, select, find, save, reload, undo and new tabs are mapped
to their app equivalents. Enable Moonlight's **Capture system keyboard shortcuts**
for Command keys to reach the host. **Ctrl+Alt+Shift+Q** disconnects the stream
and returns to Moonlight while leaving the remote desktop running. Ctrl+Space retains the desktop actions whose
Super bindings are replaced. Reload Hyprland and restart the running Quickshell instance after install.

The Mac profile uses click-to-focus, **Command+Tab** for the next window,
**Command+Space** for apps and **Control+Command+F** for fullscreen. Use
**Ctrl+Space, P** for the previous window (shifted Tab was unreliable through Moonlight).
The status-bar keyboard panel includes a visual guide with searchable shortcuts,
a window/workspace simulation, agent setup and stream escape instructions.
Its offline HTML lives at `~/.local/share/omarchy/guides/macos-controls.html`.

Local AI opens with an agent launcher and a **Deployments** section. Each GPU group shows its current model and status, with **Manage** or **Load model** as an explicit action. Deployment order stays stable. Below it, **Tokens by GPU** reports historical totals in the native Claude/Codex filled-row style; these bars are read-only and do not open controls. The usage section appears once history is available, and includes retained runtime logs and attributable older gateway receipts. vLLM totals carry ≈ because they are reconstructed from rounded rates.

Local AI keeps its GPU controls in those same rows. A running GPU opens its model's
**Stats & agents**; **Models** lists recipes for one or more of that GPU. Occupied
GPUs remain browsable, but loading requires enough free GPUs. **Launch agent** at
the top of the main screen expands the running-model and agent selectors, plus
the project folder. Choose a model and an installed compatible agent, then press
**Open** to start it in your terminal. Inside model details, each device has
temperature, usage and VRAM meters. NVIDIA uses nvidia-smi, Intel uses Level Zero
Sysman memory and DRM activity counters, and AMD uses amdgpu sysfs with SMI
inventory. Missing readings stay N/A. Python 3 is required for telemetry. Agent selection
and launch appear above the model statistics. For vLLM and llama.cpp, decode/prefill show the average
of non-zero engine log samples since local midnight, collected incrementally.
Generated-token totals include retained runtime logs and attributable older gateway
receipts. vLLM rates produce estimated totals, marked ≈. A shared ten-second cache
prevents duplicate scans from multiple panels. No inference requests are made for monitoring.

Click **Project folder** (or **Ctrl+O** in Local AI) before opening an agent. The
folder is remembered, defaults to home, and is entered inside the terminal after
UWSM starts it. OMP receives `--allow-home` when that folder is home. A missing folder refuses launch rather than falling back to `/tmp`.

## Requirements

- **Docker**, which Omarchy ships. You do not need to be in the `docker` group: Start, Stop, and Share ask for your password once, through Omarchy's own prompt. With *Sudoless Docker* enabled in Omarchy's security settings there is no prompt.
- **A GPU with a validated recipe in the catalog.** The catalog includes NVIDIA, Intel and AMD entries. A telemetry adapter alone does not qualify a model recipe for your hardware. The NVIDIA container toolkit is installed inside the same prompt when missing.
- **Hugging Face CLI (`hf`)** to download weights when the engine image lacks Python 3 or `huggingface_hub`. Other images can download weights themselves.
- Optional: `tailscale` for sharing.

No config file or API key to make.

## Commands

The card is the whole interface; the same verbs exist on the command line.

```
omarchy-local-ai snapshot                    the state the card renders
omarchy-local-ai load | unload [recipe]      start the selected recipe (downloading if needed) | stop one model, or all
omarchy-local-ai open-agent [name] [recipe]  open an agent on a running model
omarchy-local-ai share [--key <value>|-]     toggle tailnet sharing; replace the key (- reads stdin)
omarchy-local-ai gpu [auto|<backend:index>]  which detected card to use
omarchy-local-ai recipe [auto|<id>]          which validated recipe of that card to run
omarchy-local-ai recipes [update]            the recipe file in use; update fetches and adopts a newer one
omarchy-local-ai update [--check]            apply a staged registry copy and update the plugin; --check only fetches
omarchy-local-ai agent-dir <path>            the directory agents open in
omarchy-local-ai agent-args <name> [-- …]    extra flags for one agent
```

State: `~/.local/state/omarchy/local-ai/` (0700; `log` has every step). Weights: `~/.cache/omarchy/local-ai/` or the Hugging Face cache. Weights you already have under `~/models`, the Hugging Face cache, or the directories in `OMARCHY_AI_WEIGHTS_PATHS` (colon-separated) are verified file by file against the pinned revision and used, no download.

## Security

- **Recipes are gated before anything runs.** Digest-pinned image, pinned model revision, no host IPC, no extra capabilities, no weakened security profile, mounts canonicalized and confined to the plugin's two cache roots.
- **Two containers and a private network per model.** The engine is never reachable from the host; only the gateway listens, on loopback, and it requires a key on every request.
- **The key lives in one 0600 file** and enters no process argument, ledger, snapshot, or log.
- **Root does what you asked and nothing else.** Behind the password prompt the plugin's own script runs one batched phase; it takes your identity from pkexec, derives every path from your home, and verifies its inputs against hashes carried on the prompt's own command line.
- Six rounds of security review on the marketplace listing; the fixes are in the commit history.

Copying a share link opens an opaque overlay covering the panel. The URL and Copy/Close controls stay in the visible viewport even when model details are scrolled. It closes after a successful copy or when dismissed; copy errors remain visible.

## Current experience — v5.3.2

Local AI can live beside Claude and Codex in the native Agents view. The overview stays quiet: an expandable launcher and GPU status rows. Model selection, device meters, today's performance, sharing and Stop live in the detail views.

| Surface | Evidence and remaining work |
|---|---|
| Terminal launch | All 11 adapters pass the temporary-directory handoff fixture. OMP, Pi, OpenCode and Crush startup checked on Omarchy; Pi and OpenCode also completed real requests on NVIDIA and Intel. Full conversation/tool acceptance for every agent remains separate. |
| GPU telemetry | NVIDIA and Intel checked on physical hardware. AMD sysfs fixtures pass; physical AMD acceptance is still needed. |
| Runtime statistics | Retained vLLM/llama.cpp logs and attributable gateway receipts feed historical totals. vLLM counts are marked approximate; unsupported runtime statistics show N/A. |
| Native layout | Native styling, compact rows and QML load checked. The latest reduction in visible data still needs final visual acceptance. |
| Mac controls | Main window/app/workspace shortcuts checked through Moonlight. Previous window uses Ctrl+Space, P. The offline guide's browser rendering remains unverified. |

[Plugin guide](https://0xsero.github.io/omarchy-local-ai/) · [Releases](https://github.com/0xSero/omarchy-local-ai/releases)

## How we know it works

- 29 NVIDIA recipes ran the plugin's own Start path on rented cards, RTX 3060 through RTX 6000 Ada (`test/rented.py` is the harness; its per-card results stay outside the repository).
- Qwen TP2 has been checked on the mixed RTX 3090 and Arc Pro B70 host with 256K context.
- The shimmed tests cover the gate, download, start, acceptance, rollback, agents, sharing, key handling, and the no-docker-group path: `make test`, no GPU needed (Bash 4+ and Node.js).
- Installs, views, downloads, stars and every interaction GitHub records are collected daily on the `stats` branch and rendered at <https://0xsero.github.io/omarchy-local-ai/#17-stats>. No server and no client-side telemetry: they are GitHub's own counts of GitHub's own repository.

## Remove

If you installed the native integration, first restore the original Agents bar entry, remove the `sero.agents` and `sero.shortcuts` custom entries, and remove the Moonlight include from your Hyprland bindings if enabled. The installer prints a dated backup of those settings; restore selectively if you have since customized them. Restart the shell after restoring.


```bash
omarchy-local-ai unload            # stops the model, keeps downloads
omarchy plugin remove sero.local-ai
rm -rf ~/.cache/omarchy/local-ai ~/.local/state/omarchy/local-ai   # optional
```

## Development

Recipes come from the [local-ai registry](https://github.com/0xSero/local-ai-registry): `make sync REGISTRY=../local-ai-registry` regenerates `recipes.json`. [The design](docs/design.md) documents the controller; `python3 test/rented.py --list` is the rented-GPU harness.

Source layout: `ui/` contains the panel, `bin/` the entry point, `lib/` the controller, `test/` the checks, and `docs/` the design, and `integrations/` the optional native panel, shortcuts and guide.

`make bundle` builds `dist/omarchy-local-ai-<version>.tar.gz` from an explicit list of runtime files plus the license. `make test` unpacks that archive and runs the controller and UI checks against it. GitHub releases attach the same tested bundle; tests, docs, build files and recordings are excluded.

MIT. Self-built images carry a build attestation you can verify with `gh attestation verify`.

### Visual checks from a Mac

Capture the actual Quickshell panel over SSH, without Moonlight's video stream:

```sh
./test/visual omarchy --output HDMI-A-3 --action card:rtx-3090-24gb --action count:2 --action pick:qwen38-awq-int4-rtx3090-vllm-tp2 --save /tmp/local-ai.jpg
open /tmp/local-ai.jpg
```

Use the output containing the panel (`ssh omarchy hyprctl monitors` lists outputs); a Sunshine virtual output can differ from the physical panel output. `--action model:<recipe-id>` captures a running model. The helper only navigates, never starts or stops a model. Images come from the live desktop, so this checks the deployed QML and registry together. `make test` additionally checks the UI's row data and prevents loss of context and capability fields.
