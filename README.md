# Local AI for Omarchy

Run a local model on your own GPU or CPU and open a coding agent on it. Local AI picks a model that was tested on your card (NVIDIA, Intel Arc Pro, AMD) or an x86-64 AVX2 CPU, downloads the weights from a pinned Hugging Face revision and checks them, and serves the model in Docker behind a keyed, OpenAI-compatible gateway on 127.0.0.1. From the bar you open pi, Claude Code, Codex, OpenCode, omp, Crush, Grok, Copilot or Hermes on it in a folder you choose, without editing their config. The panel shows GPU temperature, VRAM and token use, and can share a running model on your tailnet.

![Local AI](preview.png)

## Start

```bash
omarchy plugin add https://github.com/sybil-solutions/omarchy-local-ai --enable
```

Then open Local AI in the bar and click **Set up Local AI** (once per machine; Omarchy asks for your password), choose a model on your card and **Run**, and pick a coding agent to open on it. [Install](#install) says what setup does, [Requirements](#requirements) what it needs, and [Remove](#remove) how to take it all back out.

## Install

```bash
omarchy plugin add https://github.com/sybil-solutions/omarchy-local-ai --enable
```

Open Local AI in the bar and click **Set up Local AI**. A terminal opens and runs two of Omarchy's own commands; Local AI itself runs nothing as root, and adding or updating the plugin never runs setup.

- `omarchy-setup-security-sudoless-docker`, Omarchy's Sudoless Docker: it explains what that means, asks you to confirm, then asks "Password for *you* to turn on Sudoless Docker for Local AI". This login reaches Docker through the new group at once, so Local AI needs no logout or reboot (Omarchy may still suggest one at its next update).
- NVIDIA only: `omarchy-pkg-add nvidia-container-toolkit`, asking "Password for *you* to install NVIDIA container support for Local AI"; already installed, it asks nothing. The package describes your GPUs to Docker in `/etc/cdi/nvidia.yaml`, which Docker reads when a model starts, so Docker's configuration is untouched and it is not restarted.

Setup ends by checking what the panel will show. Sharing a model on your tailnet needs you as Tailscale's operator; Omarchy's Tailscale install sets that, and setup tells you when it is not. After setup, starting, stopping, sharing, refreshing and removing never ask for a password. Sudoless Docker is root-equivalent, as Omarchy's own warning says; turn it off in Setup > Security.

## Requirements

- Omarchy with the Quattro shell and its bar. Local AI calls Omarchy's own commands: `omarchy-setup-security-sudoless-docker`, `omarchy-pkg-add`, `omarchy-hw-nvidia`, `omarchy-launch-tui`, `omarchy-launch-browser`, `omarchy-notification-send` and `omarchy-cmd-present`.
- Docker, `jq`, `curl`, `flock` and `sha256sum`.
- A supported GPU (below), or an x86-64 CPU with AVX2 and enough RAM for its recipe. NVIDIA needs the driver and `nvidia-smi`; setup adds the container toolkit. Docker 25 or later (Omarchy ships 29). AMD needs ROCm's `amd-smi`.
- Optional: Tailscale, to share a model; a Hugging Face token in `~/.cache/huggingface/token`, used for downloads when it exists.
- Network access to `huggingface.co` (weights), `ghcr.io/0xsero` and `ghcr.io/ggml-org` (the engine and gateway images, pinned by digest), and `api.github.com` and `raw.githubusercontent.com` (**Refresh models**).

## What it does

- **Validated models per card, or one across several.** `recipes.json` holds, for each supported hardware kind, every recipe accepted on that exact card or across 2 or 4 of them in [local-ai-registry](https://github.com/sybil-solutions/local-ai-registry): download, load, a correctness check and speed at several context lengths. EXL3 weights on SGLang or vLLM come first and are recommended; a card's Config lists the rest. A card without a recipe shows Coming soon and links the [supported list](https://github.com/sybil-solutions/local-ai-registry/blob/main/supported/README.md).
- **What the machine needs.** A recipe that keeps experts in system RAM or reads from disk while it serves (Qwen3.8-Flash-Next on a 3090 or a B70) says how much free RAM and disk it needs and whether the models folder must be on NVMe; it is offered only on a machine that has them, and Config says what is missing.
- **Weights** are downloaded as you, from the pinned revision, and every file's size is checked against Hugging Face, and the SHA-256 of every large (LFS) file, before it is used. A matching copy in your Hugging Face cache is reused.
- **Containers.** The engine runs on a private network with no published port and `no-new-privileges`. A keyed gateway runs as you on `127.0.0.1`, speaks the OpenAI, Anthropic and Responses APIs, and logs one line per answer; the tokens, speeds, charts and the activity grid on Home come from that log, summed once per new line rather than on every refresh.
- **Agents.** pi, Claude Code, Codex, OpenCode, omp, Crush, Grok, Copilot and Hermes open in a terminal, in the folder you pick, pointed at the gateway. Nothing in their own config is touched. Choose an agent on its full row, **Make default** for new models, or **Update** to update its existing installation. Click the folder row to open a folder picker. **Open** launches the selected agent directly from the model page. Agent choices on a running model do not change the default; the last folder picked remains the folder default. Updates use mise when it manages that agent, the native updater for standalone omp, Hermes, Claude Code and OpenCode, or npm for an existing npm installation. Existing sessions keep running.
- **Share** a running model on your tailnet with `tailscale serve` (tailnet only, still keyed). **Stop sharing** on its page removes that share. Tailscale must be running and logged in. Setup preserves another account’s operator; ask that account to manage sharing. A failed unshare is logged and does not prevent stopping the model.

Supported: x86-64 AVX2 CPUs (LFM2.5-2.6B in system RAM), NVIDIA RTX 30, 40 and 50 series, RTX A6000, RTX Ada and RTX Pro Blackwell, Intel Arc Pro B70, and AMD Instinct MI300X and Radeon RX 6800 XT (with ROCm's `amd-smi`).

## From a shell

```bash
bin/omarchy-local-ai setup                    # one-time machine setup
bin/omarchy-local-ai registry                 # refresh the validated catalog
bin/omarchy-local-ai forget <recipe>          # remove stopped managed weights
bin/omarchy-local-ai snapshot                 # what the card draws, as JSON
bin/omarchy-local-ai run <recipe> <gpu>[,<gpu>] # e.g. run qwen38-27b-exl3-3bpw-rtx3090-sglang-tp1 nvidia:0
bin/omarchy-local-ai stop <recipe>
bin/omarchy-local-ai open <recipe>            # the chosen agent on it, in a terminal
bin/omarchy-local-ai update <agent>           # update the installed harness
bin/omarchy-local-ai set agent|folder <value> [recipe]
bin/omarchy-local-ai share <recipe> [off]
bin/omarchy-local-ai log
```

CPU recipes use system RAM and start without GPU devices. Recipes that offload GPU work into RAM or NVMe remain hardware-specific and list their requirements.

Each running model answers on `http://127.0.0.1:<port>/v1` (ports from 12434); the key is in `~/.local/state/omarchy/local-ai/gateway.key`.

## Remove

`bin/omarchy-remove-ai-local` stops this user’s managed models and deletes their containers, engine images, weights and settings. Then `omarchy plugin remove sero.local-ai`.

## Files

| File | Role |
|---|---|
| `bin/omarchy-local-ai` | The backend, one bash file |
| `Model.js` | Pure functions: the snapshot in, the view out |
| `Panel.qml` | Draws the view and runs the backend's verbs |
| `recipes.json` | The vendored recipes, one card kind per line (`make sync`) |

`docs/design.md` has the design and `test/all` runs the tests.

### Container boundary

Images are pinned by SHA-256. The gateway runs as the calling user, with no
Linux capabilities, a read-only root filesystem, a bounded temporary directory
and external DNS disabled. Docker service discovery still resolves the engine;
usage records remain writable in their dedicated directory. Existing containers
receive these restrictions when stopped and started again.

Model engines still have writable container filesystems and outbound network
access. Digest pins and build attestations establish image identity; they do
not make untrusted code safe. Engine restrictions need per-engine hardware
validation before rollout. Disabling gateway DNS does not block outbound IP
connections.

### Refresh and remove models

Use **Refresh models** at the bottom of Local AI to fetch the latest published
registry for your GPUs without reinstalling the plugin; the catalog lives in your
cache (`~/.cache/omarchy/local-ai`). Downloads are pinned to a registry commit,
validated before an atomic replacement, and failures keep the previous catalog.
Refreshing does not stop running models or download model weights. Offload
recipes are offered only when their RAM, disk and storage requirements fit.

Choose a GPU's **Config**, select a model, then **Run** to download and start it.
**Remove download** deletes that model's managed weights after it is stopped;
shared weights in use by another managed model are protected. The recipe stays
available to download again. Files in your separate Hugging Face cache are kept,
so hard-linked files there may continue to occupy disk space.

The equivalent commands are `omarchy-local-ai registry` and
`omarchy-local-ai forget <recipe>` (or the plugin's `bin/omarchy-local-ai`).

## License

[MIT](LICENSE). The agent and GPU-maker logos in `preview.png` are trademarks of their owners, shown to identify compatibility only; Local AI is not affiliated with or endorsed by any of them.
