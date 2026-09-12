<p align="center">
  <img src="media/logo-256.png" width="112" height="112" alt="">
</p>
<h1 align="center">Local AI for Omarchy</h1>
<p align="center">
  The model validated for your GPU, one button on the bar.
</p>
<p align="center">
  <a href="https://omarchyplugins.com/plugin.html?id=sero.local-ai"><img alt="Omarchy marketplace" src="https://img.shields.io/badge/omarchy-marketplace-111?style=flat-square"></a>
  <a href="https://github.com/0xSero/omarchy-local-ai/releases"><img alt="release" src="https://img.shields.io/github/v/release/0xSero/omarchy-local-ai?style=flat-square&color=111"></a>
  <a href="https://github.com/0xSero/omarchy-local-ai/actions/workflows/test.yml"><img alt="tests" src="https://img.shields.io/github/actions/workflow/status/0xSero/omarchy-local-ai/test.yml?style=flat-square&label=tests&color=111"></a>
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-111?style=flat-square"></a>
</p>

![How it works](preview.png)

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai.git --enable
```

Click the new bar icon, press **Start**. The card names the model chosen for your GPU and its download size before anything lands on disk. When it says **ready**, the model has passed every check below.

## How it works

1. **Start** downloads the model validated for your card, pulls its engine image, proves the model answers (correct model, keyed, fast enough, all three API dialects, a real tool call), and serves it on `127.0.0.1:12434`.
2. **Open agent** starts any installed coding agent on it: claude, codex, pi, omp, opencode, ori, grok, agy, hermes, copilot, crush. The endpoint and key travel in the agent's environment. Nothing of yours under `~/.config` is read or written.
3. **Share on Tailscale** publishes the same keyed endpoint on your tailnet address. One click, no `tailscale serve`, no root.

Every detected GPU is listed; the largest card with a recipe is the default and any can be picked. Anything the plugin cannot do is a sentence on the card, never a dead button.

## Requirements

- **Docker**, which Omarchy ships. You do not need to be in the `docker` group: Start, Stop, and Share ask for your password once, through Omarchy's own prompt. With *Sudoless Docker* enabled in Omarchy's security settings there is no prompt.
- **An NVIDIA GPU (8 GB and up) or an Intel Arc Pro B70.** The NVIDIA container toolkit is installed for you inside that same prompt when missing.
- Optional: `tailscale` for sharing, `hf` for faster downloads.

No model to pick, no config file, no API key to make.

## Commands

The card is the whole interface; the same verbs exist on the command line.

```
omarchy-local-ai snapshot                    the state the card renders
omarchy-local-ai load | unload               start (downloading if needed) | stop, keep downloads
omarchy-local-ai open-agent [name]           open an agent on the running model
omarchy-local-ai share [--key <value>|-]     toggle tailnet sharing; replace the key (- reads stdin)
omarchy-local-ai gpu [auto|<backend:index>]  which detected card to use
omarchy-local-ai agent-dir <path>            the directory agents open in
omarchy-local-ai agent-args <name> [-- …]    extra flags for one agent
```

State: `~/.local/state/omarchy/local-ai/` (0700; `log` has every step). Weights: `~/.cache/omarchy/local-ai/` or the Hugging Face cache.

## Security

- **Recipes are gated before anything runs.** Digest-pinned image, pinned model revision, no host IPC, no extra capabilities, no weakened security profile, mounts canonicalized and confined to the plugin's two cache roots.
- **Two containers, private network.** The engine is never reachable from the host; only the gateway listens, on loopback, and it requires a key on every request.
- **The key lives in one 0600 file** and enters no process argument, ledger, snapshot, or log.
- **Root does what you asked and nothing else.** Behind the password prompt the plugin's own script runs one batched phase; it takes your identity from pkexec, derives every path from your home, and verifies its inputs against hashes carried on the prompt's own command line.
- Six rounds of security review on the marketplace listing; the fixes are in the commit history.

## How we know it works

- 29 NVIDIA recipes ran the plugin's own Start path on rented cards, RTX 3060 through RTX 6000 Ada ([per-card logs](test/rented-results/)).
- The Intel Arc Pro B70 recipe runs daily on a mixed RTX 3090 + B70 host, where [every feature was recorded](media/features.mp4) (4 min) and [eight agents shared one model](media/demo.mp4) (6 min).
- 112 shimmed tests cover the gate, download, start, acceptance, rollback, agents, sharing, key handling, and the no-docker-group path: `bash test/all`, no GPU needed.

## Remove

```bash
omarchy-local-ai unload            # stops the model, keeps downloads
omarchy plugin remove sero.local-ai
rm -rf ~/.cache/omarchy/local-ai ~/.local/state/omarchy/local-ai   # optional
```

## Development

Recipes come from the [local-ai registry](https://github.com/0xSero/local-ai-registry): `make sync REGISTRY=../local-ai-registry` regenerates `recipes.json`, and CI fails if the file and its recorded commit disagree. [`DESIGN.md`](DESIGN.md) is the design; [`demo/`](demo/README.md) has the recordings and brand assets (`media/logo.svg`, `media/logo-mark.svg`); `python3 test/rented.py --list` is the rented-GPU harness.

MIT. Self-built images carry a build attestation you can verify with `gh attestation verify`.
