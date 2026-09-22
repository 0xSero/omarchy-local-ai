# Local AI for Omarchy

Run validated local models, open coding agents and share endpoints from the Omarchy bar.

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai.git --enable
```

Click the new bar icon, choose a GPU group and recipe, then press **Load model** (or **Swap model** for occupied GPUs). The card shows the download size, context and capabilities before launch. When it says **ready**, the model has passed its acceptance checks.

## How it works

1. **Start** downloads the model validated for the card you picked, pulls its engine image, proves the model answers (correct model, keyed, fast enough, all three API dialects, a real tool call), and serves it on `127.0.0.1:12434`. Start another recipe on another card and it runs alongside on the next port; the card lists every running model with its own open-agent and stop.
2. **Open agent** starts any installed coding agent on it: claude, codex, pi, omp, opencode, ori, grok, agy, hermes, copilot, crush. The endpoint and key travel in the agent's environment. The launcher keeps its provider settings under plugin-owned state; it does not rewrite your normal agent configuration.
3. **Share on Tailscale** publishes the same keyed endpoint on your tailnet address. One click, no `tailscale serve`, no root.

Each GPU type opens its running models and compatible model list. Select a model
to reveal its Load or Swap action directly underneath, or open a running model for its agent,
stats and Stop controls. The overview keeps the selected agent's Open button visible.
The entire actionable row is clickable. A swap names the models it will replace, preserves models on other GPUs, and restores the previous model if the new one fails acceptance.
Every breadcrumb is clickable, so you can jump straight to a GPU group or home.
The whole page scrolls, including folder editing and bottom actions. **Home/End** and
**Page Up/Down** navigate the viewport; **F11** expands the standalone panel.

Home also carries one **update** row. A background check reads the registry's recipe file and this plugin's own manifest, and the row appears when either has something newer — the plugin version, and how many new recipes are for the cards you actually have. Nothing is installed behind your back: pressing it applies the new recipes and updates the plugin through `omarchy plugin update`. With nothing to apply the row is just a re-check.

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

Source layout: `ui/` contains the panel, `bin/` the entry point, `lib/` the controller, `test/` the checks, and `docs/` the design.

`make bundle` builds `dist/omarchy-local-ai-<version>.tar.gz` from an explicit list of runtime files plus the license. `make test` unpacks that archive and runs the controller and UI checks against it. GitHub releases attach the same tested bundle; tests, docs, build files and recordings are excluded.

MIT. Self-built images carry a build attestation you can verify with `gh attestation verify`.

### Visual checks from a Mac

Capture the actual Quickshell panel over SSH, without Moonlight's video stream:

```sh
./test/visual omarchy --output HDMI-A-3 --action card:rtx-3090-24gb --action count:2 --action model:qwen38-awq-int4-rtx3090-vllm-tp2 --save /tmp/local-ai.jpg
open /tmp/local-ai.jpg
```

Use the output containing the panel (`ssh omarchy hyprctl monitors` lists outputs); a Sunshine virtual output can differ from the physical panel output. `--action model:<recipe-id>` captures a running model. The helper only navigates, never starts or stops a model. Images come from the live desktop, so this checks the deployed QML and registry together. `make test` additionally checks the UI's row data and prevents loss of context and capability fields.
