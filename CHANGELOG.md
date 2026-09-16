# Changelog

Versions follow semver and live in `manifest.json`. Every release is a tag `vX.Y.Z` on `main` and a GitHub release. The marketplace listing only ever targets a tagged release commit. See "Releasing" in `DESIGN.md`.

## [5.0.0] - Unreleased

### Changed
- TP2 Qwen3.8 now has a verified 262,144-token context on two RTX 3090s or two Arc Pro B70s. The registry exporter retains supported multi-card recipes and their GPU count and KV capacity.
- Cards show context and chat, image, video, tools and reasoning capabilities before launch. Unknown capability metadata stays unknown. Pi/OMP and Crush receive the recipe's context instead of a hardcoded 128K; Pi/OMP also receive image support.
- A failed launch no longer silently retries at a smaller context. Readiness checks advertised runtime context and exercises image/video input through the gateway when the recipe claims them.
- Several models run at once. Every running model is its own engine+gateway pair (`omarchy-local-ai-<recipe>-engine` / `-gateway`) on its own private network, with the gateway on 127.0.0.1:12434 for the first model and the next free port for each further one. A Start replaces only the models on the cards it claims (its own earlier run included) and sets them aside until the new one is accepted; models on other cards keep running. `unload <recipe>` stops one model, `unload` stops all; `open-agent [name] [recipe]` opens an agent on a named model; share publishes every running model on its own port. The ledger is `ledger/2` (`slots`), the snapshot `snapshot/10` (`models[]`, `running`, `cards[].claimed` = in use).
- The card is three places. Home shows every card type with one cell per physical card (free with its temperature, the model on it, claimed, freeing, crashed) and one row per running model; a type with nothing on it opens the card view, a type holding a model is reached through its model row. The card view has a 1×/2× toggle when more than one card of the type is free and lists only the recipes that use exactly that many, one line each (name · size · on disk / download / resume / running); run, download + run or resume + run is pinned at the bottom. The model view opens on its numbers (decode, prefill, tokens today, KV cache and context, each card's temperature, load and VRAM), the model's capabilities, the agent (a dropdown; the pick is the one "open" launches), share on the tailnet (the link is copied when it comes up) and stop. Download, start, stop and share take the whole card over with the verb as the state word, a stepper (weights › image › engine › check) and the cells they touch reading claimed or freeing; starting and stopping can never show together. Back and the path live in the header; the card never grows past 720 px, only the list scrolls. `Panel.qml` draws; `ui.js` decides the rows; `CardRow.qml` and `Orb.qml` are the parts. 554 lines, from 702, with more on the card.
- Snapshot 10: `gpus[]` carry `tempC`, `utilPct` and `usedGb` (NVIDIA from nvidia-smi, Intel Arc temperature from the xe hwmon); recipes and models carry `caps` (chat, vision, tools, reasoning), `kvTokens` and `ctxTokens` from the registry (`serving.kvTokens` is new in the export), and models carry `tokensToday`, the completion tokens that model served through its gateway in the last day (`usage.jsonl` lines now name the recipe). The panel's `activate <action>` IPC verb runs any row action, for scripts and tests.
- The card's run is one controller verb, `run <recipe> [gpu]`, which pins the card and the recipe and starts in one process: one snapshot instead of three, and the card turns busy on the click itself instead of a second or more later. A snapshot costs half what it did (the weights path and the image check are asked once per recipe and image).
- An alternate recipe the launch gate would refuse on shape (host networking or IPC, extra capabilities, a weakened profile) is not offered any more; the recommended recipe still shows with its reason if it is refused. A verb that follows a worker still writing its last snapshot waits for the lock instead of failing with "another operation is running", and a worker gone before its pid was recorded no longer leaves a phantom op ("stopped unexpectedly while starting" over a plain refusal). A Start's own containers are no longer "adopted" mid-start.
- Trimmed: the single-model ledger migration and stray-pair adoption, the parsed pull percent (the pull is a step with a sweep), the controller-side start percent (the card times the start against the last one), the windowed token counters, and the local-recipe merger script the registry export made redundant. 2,220 lines of source, from 2,345, with nothing the card shows removed.
- A one-card recipe starts on the free card with the most memory free, and `gpu auto` prefers it: on a box whose first card drives the desktop (Hyprland alone holds 3 GB there) a vLLM recipe that asks for 97% of the card could never start while the second card sat empty. A vLLM recipe's `--gpu-memory-utilization` is lowered to the share actually free on the claimed cards, and a start that cannot fit its advertised context fails with the engine reason. The engine log kept at rollback is 400 lines, so the root cause is in the plugin's log, not only in a container that is gone.
- Two-card recipes are offered: the registry export dropped every multi-card recipe before it could be an alternate, and the RTX 3090 tensor-parallel recipes declared host IPC, which the gate refuses; they run on their 32g shared memory alone (verified: Qwen3.8-27B AWQ TP2 on two 3090s, 60 tok/s, 131K context).


### Fixed
- A "downloaded" marker no longer outranks the disk: weights deleted behind it (a cache wipe) are fetched again instead of launching the engine over an empty read-only mount, which crash-looped it.
- An engine that exits at once under docker's restart policy is reported within seconds with its last log line, instead of waiting out the whole acceptance timeout (an hour) as "loading the model · 95%".
- The pull-progress test waited a fixed 0.2 s for the shims; it now waits for the step.

### Changed
- Recipes are dynamic: the vendored file is the floor, and a newer copy is fetched from the registry repository (`recipes update`, the card's registry view, or a six-hourly background check), schema-checked, kept 0600 in the state dir, and used in its place. Every recipe is still gated at launch. `OMARCHY_AI_RECIPES_URL=` turns it off.
- The registry export now ships every validated recipe of a card, multi-card ones included (`cards`), so the 3090 pair offers its vLLM and SGLang TP2/TP4 recipes and the B70 pair its SGLang TP2: 76 recipes across 34 cards, from 34.
- Weights already on the machine are used: before a download the plugin looks under `~/models`, its model root, the HF cache, `~/.cache/llama.cpp` and `OMARCHY_AI_WEIGHTS_PATHS` for the recipe's files, verifies each against the Hub's tree of the pinned revision (size, then SHA-256 or blob id), and adopts a match by reflink into the recipe's directory or the HF cache's own layout. A same-named older quant, or one edited file, is refused and logged.
- Working card: the step is the subtitle, the status row carries the verb with its percent and elapsed time, and a Start past 1.5× its usual time says "longer than usual" instead of sitting at 95%.
- The card is a command stack: one recessed state slab (state, title, the orb) over rows of noun and datum. Drill-down is a path stack (`local ai / options / registry`); esc and back pop one level. Idle shows the claimed card group, the next action and an options count; ready shows the primary command, `runtime · 3 · stats live` and stop; agent, stats and share sit one level deeper. Every state breathes through the orb, and a download grows its lit radius.
- Identical GPUs aggregate (`2× RTX 3090 · 48 GB total`); a recipe claims cards from its own group and the rest read idle. Recipes on disk say so and their action is `run`; a card reopened while a model runs opens in ready on the live recipe; a selection that differs from the running recipe offers `run · swap`; a running recipe the file no longer carries is still listed from its slot record.
- Snapshot 10 carries `cards`, `recipes`, `selected`, `port` and `running.name`; the single-model `model` block, the windowed `stats`, the registry list and the `older` flag are gone with the views that read them. A foreign listener on the gateway port is reported as a reason.

## [4.1.0] - 2026-09-12

### Changed
- Docker without the docker group: Start, Stop and Share batch their docker calls into one polkit prompt through Omarchy's own agent; the NVIDIA container toolkit is installed inside that prompt when missing. The card's refresh never touches docker.
- The root phase trusts pkexec, not user-owned files: uid from `PKEXEC_UID`, every root derived from that user's home, inputs pinned by hashes on pkexec's own command line.
- Acceptance refuses a reasoning model whose thinking leaks into the answer; the four Qwen TabbyAPI recipes enable the reasoning parser.
- Claude launches with `ANTHROPIC_AUTH_TOKEN`, the bearer form meant for gateways.
- Every failure is a sentence on the card: missing tools, a broken recipes file, a worker killed without its exit trap, a gateway that stops, a controller that prints nothing. Ready requires the acceptance record.
- Gate: recipe ids, repositories, weight directories and served names are shaped; the gateway image must be digest-pinned; only tailnet addresses are bound; a same-named docker network of someone else's is refused; `share --key -` reads the key from stdin.
- Sharing: a failed publish falls back to loopback inside the same prompt; a dismissed Stop-sharing prompt keeps the card saying shared.
- Card: no dead 20 seconds after a pick; a running model of another recipe is named and Start replaces it.
- Listing: preview with how it works in three steps; vector logo under `media/`; README rewritten.

### Fixed
- The root-phase env parser dropped values containing `x`, `6` or `0`, so the gateway and downloader ran as root behind a prompt.
- Prompt-mode acceptance called docker as the user, reporting a slow-loading engine as exited.
- An engine that failed to start left the previous model set aside; rollback now happens in the same prompt, and a failed rollback is named.
- A lock loser could rewrite the winner's ledger; the parent's pending record is a compare-and-swap.

### Internal
- 112 shimmed tests; the docker shim refuses unprivileged calls in prompt mode and the pkexec shim starts from a clean environment.
- Clone and view traffic recorded daily on the `stats` branch.

## [4.0.0] - 2026-09-08

The snapshot verified on the Omarchy plugin marketplace (`3f447b9`). One validated model per GPU, one button on the bar; agents launch-only, nothing written to user config; keyed sharing on the tailnet; the GPU picker; rented-hardware validation of 29 NVIDIA recipes.
