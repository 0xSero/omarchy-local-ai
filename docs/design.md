# Local AI

A bar widget that runs the one model validated for each GPU in the machine and opens a coding agent on it. It is these files, the same ones proposed for Omarchy in [omacom/omarchy#13036](https://github.com/omacom/omarchy/pull/13036); only where the backend finds itself and the Panel's module name differ:

| File | Role |
|---|---|
| `bin/omarchy-local-ai` | The backend: detect GPUs, download and check weights, start and stop containers, open agents, print a snapshot |
| `Model.js` | Pure functions: snapshot and ui state in, a view (rows and actions) out |
| `Panel.qml` | Draws the view; turns an action (`verb\|arg\|arg`) into a backend verb |
| `recipes.json` | The vendored recipes, one card kind per line: from [local-ai-registry](https://github.com/0xSero/local-ai-registry)'s `plugin/v2/recipes.json`, each kind's first recipe (its own model) and its first for each larger number of cards (a group: one model across that many cards of the kind) |

## Flow

The widget polls `bin/omarchy-local-ai snapshot` (every 1.5 s while something starts, 5 s while open, 30 s closed). The snapshot joins the GPUs (`nvidia-smi`, the Arc Pro B70's PCI id and hwmon, `amd-smi`), the recipes and one folder per running model, `~/.local/state/omarchy/local-ai/deploy/<recipe>/` with `config.json` (cards, port, agent, folder) and `status.json` (step, detail, percent, error). `Model.build()` turns that into the page; nothing in the view model has side effects.

`run <recipe> <gpu>[,<gpu>...]` claims the cards and a port under a lock, writes `config.json`, and starts a detached worker. The worker downloads the weights as the user and checks every file's size and sha256 against the Hub listing at the pinned revision, starts the engine and a keyed gateway, waits for the model, and sends one request to check it answers at GPU speed. Each step writes `status.json` and a desktop notification says when it starts, is ready, or failed and why.

The gateway (`ghcr.io/0xsero/gateway`, pinned by digest) listens on `127.0.0.1` only, requires a per-install bearer key, translates the Anthropic and Responses APIs to chat completions for Claude Code and Codex, and writes one usage line per answer. The widget's tokens, speeds and chart come from those lines.

`open <recipe>` starts the chosen agent in a terminal, in the chosen folder, pointed at the gateway. The key is passed in the agent's environment or in a config file under the state folder that only the user can read; nothing in the agent's own config is changed.

## Privilege

Omarchy keeps users out of the docker group, so starting containers needs root. The backend follows `omarchy-windows-vm`: when `omarchy-sudo-docker` says Docker needs sudo, it runs `pkexec <plugin>/bin/omarchy-local-ai __root <phase>`, and the password prompt names that file. As root it pins `PATH` and the locale, resolves the caller from `PKEXEC_UID` and the account database, re-reads the recipe from the file beside the script rather than taking it as an argument, checks every recipe string with `policy()`, and mounts only paths that resolve to themselves and belong to the caller. Engine containers run with `no-new-privileges` and carry the caller's uid as a label, so stop and remove touch only that user's containers. Sharing on the tailnet (`tailscale serve`) uses the same phase when the user is not the tailnet's operator.

## Why it is shaped this way

- **One model per card, vendored.** Every recipe was accepted on its exact card: download, load, a correctness check, speed at several context lengths. Nothing is fetched at runtime: a new recipe reaches you in a plugin update, and the privileged step checks every string of it with `policy()`. A card without an accepted recipe shows Coming soon and links the list in `supported/`.
- **EXL3 first, engines that serve it in-process.** The registry recommends, per card, EXL3 weights on SGLang or vLLM ahead of TabbyAPI and llama.cpp, then vision, context and measured decode. On a 3090 that is Qwen3.8-27B on SGLang at 200K context and about 90 tok/s.
- **Containers, not packages.** Engines need exact CUDA, ROCm or oneAPI stacks; an image pinned by digest is the smallest thing that reproduces the accepted run.
- **A gateway in front.** Engines differ in API and none checks a key; the gateway gives every engine the same keyed endpoint and the same usage accounting.
- **The view is data.** `Model.js` is plain functions over the snapshot, so every page (home, a running model, a free card, Coming soon) is a function of state and can be rendered without the backend.

## Limits

- AMD cards are found through `amd-smi`, which comes with ROCm; without it they show Coming soon.
- In the prompt path the backend cannot read Docker, so a crashing engine is reported when its 30-minute wait ends rather than on its second restart.
- `bin/omarchy-remove-ai-local` deletes models, containers, engine images, weights and settings; `omarchy plugin remove sero.local-ai` removes the plugin.
