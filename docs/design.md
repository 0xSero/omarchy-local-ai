# Local AI

A bar widget that runs the one model validated for each GPU in the machine and opens a coding agent on it. The plugin has four main parts:

| File | Role |
|---|---|
| `bin/omarchy-local-ai` | The backend: detect GPUs, download and check weights, start and stop containers, open agents, print a snapshot |
| `Model.js` | Pure functions: snapshot and ui state in, a view (rows and actions) out |
| `Panel.qml` | Draws the view; turns an action (`verb\|arg\|arg`) into a backend verb |
| `recipes.json` | The vendored recipes, one card kind per line: from [local-ai-registry](https://github.com/0xSero/local-ai-registry)'s `plugin/v2/recipes.json`, every recipe of each kind, best first: the first on one card is the kind's recommended model, and the rest are what a card's Config offers, on one card or across several (a group) |

## Flow

The widget polls `bin/omarchy-local-ai snapshot` (every 1.5 s while something starts, 5 s while open, 30 s closed). The snapshot joins the GPUs (`nvidia-smi`, the Arc Pro B70's PCI id and hwmon, `amd-smi`), the recipes and one folder per running model, `~/.local/state/omarchy/local-ai/deploy/<recipe>/` with `config.json` (cards, port, agent, folder) and `status.json` (step, detail, percent, error). `Model.build()` turns that into the page; nothing in the view model has side effects.

A recipe may carry `needs` (`host_ram_gb`, `disk_gb`, `fast_storage: "nvme"`) when it offloads to the host. The snapshot measures the host once (MemAvailable, free space under the models folder, and `lsblk -s` from that folder's filesystem down through dm-crypt or LVM to its drives) and gives each recipe an `unfit` reason, empty when it fits; `Model.js` picks the first recipe that fits and shows the others disabled with the reason, and `run` refuses an unfit one.

`run <recipe> <gpu>[,<gpu>...]` claims the cards and a port under a lock, writes `config.json`, and starts a detached worker. The worker downloads the weights as the user and checks every file's size and sha256 against the Hub listing at the pinned revision, starts the engine and a keyed gateway, waits for the model, and sends one request to check it returns an answer. Each step writes `status.json` and a desktop notification says when it starts, is ready, or failed and why.

The gateway (`ghcr.io/0xsero/gateway`, pinned by digest) listens on `127.0.0.1` only, requires a per-install bearer key, translates the Anthropic and Responses APIs to chat completions for Claude Code and Codex, and writes one usage line per answer. The widget's tokens, speeds, charts and activity grid come from those lines: each model keeps `summary.json` beside its log (tokens per hour, and the counts and sums the averages need), brought up to date from only the lines added since, so once built it costs a snapshot about the same with a million answers as with ten (building it from a large existing log takes a few seconds per 100,000 lines, once).

`open <recipe>` starts the chosen agent in a terminal, in the chosen folder, pointed at the gateway. The key is passed in the agent's environment or in a config file under the state folder that only the user can read; nothing in the agent's own config is changed.

## Privilege

Setup opens one terminal and validates sudo once. It turns on Omarchy's Sudoless Docker, sets the tailnet operator only when unset or already this user and adds the NVIDIA runtime when needed, refusing to restart Docker while containers are running. It removes the old per-user authorization files. Every later backend operation runs as the user.

A session carries the groups it logged in with, so setup grants the account read-write access to the Docker socket through an ACL; the docker group covers later logins. If Docker recreates the socket before the next login, the snapshot says `relogin` and the panel asks the user to log out and back in once. Setup is judged from machine state (`omarchy-sudo-docker --configured` and NVIDIA toolkit availability), never a plugin version marker.

The backend validates recipe arguments before starting, mounts paths owned by the user without symbolic links, and labels containers with the user's uid. Stop and remove retain deployment state if Docker cannot remove a container. Legacy 5.x containers without a uid are still adopted. Docker operations and panel polls have time limits; downloads fail on stalled transfers and keep partial files for resumption. Action and poll failures appear on the current page, including Config and unsupported-GPU pages.


## Why it is shaped this way

- **Validated models, vendored.** Every recipe was accepted on its exact card, or cards: download, load, a correctness check, speed at several context lengths. Recipes arrive through plugin updates or an explicit **Refresh models**. Refresh resolves a registry commit, validates its catalog and replaces the cache atomically; failures retain the previous catalog. The backend checks recipe arguments again before a start. A card without an accepted recipe shows Coming soon and links the list in `supported/`.
- **EXL3 first, engines that serve it in-process.** The registry recommends, per card, EXL3 weights on SGLang or vLLM ahead of TabbyAPI and llama.cpp, then vision, context and measured decode. On a 3090 that is Qwen3.8-27B on SGLang at 200K context and about 90 tok/s.
- **Containers, not packages.** Engines need exact CUDA, ROCm or oneAPI stacks; an image pinned by digest is the smallest thing that reproduces the accepted run.
- **A gateway in front.** Engines differ in API and none checks a key; the gateway gives every engine the same keyed endpoint and the same usage accounting.
- **The view is data.** `Model.js` is plain functions over the snapshot, so every page (home, a running model, a free card, Coming soon) is a function of state and can be rendered without the backend.

## Limits

- AMD cards are found through `amd-smi`, which comes with ROCm; without it they show Coming soon.
- A model has up to 30 minutes to become ready; repeated engine restarts fail sooner. Stop cancels the download or startup worker.
- A socket ACL lasts until Docker recreates the socket; an old login then needs to log out and back in once.
- Tailscale must be running and logged in for sharing; setup preserves another account’s operator. Failed unsharing is logged but never prevents stopping a model.
- `bin/omarchy-remove-ai-local` deletes models, containers, engine images, weights and settings; `omarchy plugin remove sero.local-ai` removes the plugin.
