# Local AI for Omarchy

Run the model validated for your GPU and open a coding agent on it.

![Local AI](preview.png)

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai --enable
```

On an NVIDIA machine, run `bin/omarchy-install-ai-local` from the plugin's folder once: it adds the NVIDIA container runtime, which Omarchy does not ship. Docker itself is part of Omarchy.

Omarchy keeps you out of the docker group, so every start and stop asks for your password once. With sudoless Docker (_Setup > Security_) it doesn't ask.

## What it does

- **One model per card.** `recipes.json` holds, for each of 36 card kinds, the one recipe that was accepted on that exact card in [local-ai-registry](https://github.com/0xSero/local-ai-registry): download, load, a correctness check and speed at several context lengths. EXL3 weights on SGLang or vLLM come first. A card without a recipe shows Coming soon and links the [supported list](https://github.com/0xSero/local-ai-registry/blob/main/supported/README.md).
- **Weights** are downloaded as you, from the pinned revision, and every file's size and sha256 is checked against the Hub before it is used. A matching copy in your Hugging Face cache is reused.
- **Containers.** The engine runs on a private network with no published port and `no-new-privileges`. A keyed gateway runs as you on `127.0.0.1`, speaks the OpenAI, Anthropic and Responses APIs, and logs one line per answer; the card's tokens, speeds and chart come from that log.
- **Agents.** pi, Claude Code, Codex, OpenCode, omp, Crush, Grok, Copilot and Hermes open in a terminal, in the folder you pick, pointed at the gateway. Nothing in their own config is touched. The last agent and folder you picked become the default.
- **Share** a running model on your tailnet with `tailscale serve` (tailnet only, still keyed).

Supported: NVIDIA RTX 30, 40 and 50 series, RTX A6000, RTX Ada and RTX Pro Blackwell, Intel Arc Pro B70, and AMD Instinct MI300X and Radeon RX 6800 XT (with ROCm's `amd-smi`).

## From a shell

```bash
bin/omarchy-local-ai snapshot                 # what the card draws, as JSON
bin/omarchy-local-ai run <recipe> <gpu>       # e.g. run qwen38-27b-exl3-3bpw-rtx3090-sglang-tp1 nvidia:0
bin/omarchy-local-ai stop <recipe>
bin/omarchy-local-ai open <recipe>            # the chosen agent on it, in a terminal
bin/omarchy-local-ai set agent|folder <value> [recipe]
bin/omarchy-local-ai share <recipe> [off]
bin/omarchy-local-ai log
```

Each running model answers on `http://127.0.0.1:<port>/v1` (ports from 12434); the key is in `~/.local/state/omarchy/local-ai/gateway.key`.

## Remove

`bin/omarchy-remove-ai-local` stops every model and deletes its containers, engine images, weights and settings. Then `omarchy plugin remove sero.local-ai`.

## Files

| File | Role |
|---|---|
| `bin/omarchy-local-ai` | The backend, one bash file |
| `Model.js` | Pure functions: the snapshot in, the view out |
| `Panel.qml` | Draws the view and runs the backend's verbs |
| `recipes.json` | The vendored recipes, one card kind per line (`make sync`) |

The same files are proposed for Omarchy itself in [omacom/omarchy#13036](https://github.com/omacom/omarchy/pull/13036); this plugin differs only in where it finds itself, and in taking over a model a 5.x install left running. `docs/design.md` has the design and `test/all` runs the tests.
