# Changelog

Versions follow semver and live in `manifest.json`. Every release is a tag `vX.Y.Z` on `main` and a GitHub release. The marketplace listing only ever targets a tagged release commit. See "Releasing" in `docs/design.md`.

## [5.0.7] - 2026-09-17

### Changed
- The marketplace listing: `preview.png` now carries the Local AI banner, the supported GPUs, recipe count, agents and sharing, and two live captures of the card (Qwen3.8-27B on 2× RTX 3090 and on 2× Arc Pro B70). The description names the supported GPU families and the agents outright. `docs/preview.py` composes the image from `media/banner.png` and two captures.

## [5.0.6] - 2026-09-17

### Fixed
- The README's rented-card link pointed at `test/rented-results/`, which is measurement data and lives outside the repository; the wiki named the wrong manifest version and library count, and overstated what a GitHub source archive carries; `docs/preview.py` hardcoded one home directory in its font lookup.

### Internal
- `agent_dialect()` and `container_recipe()` were defined and called nowhere; removed.

## [5.0.5] - 2026-09-16

### Fixed
- Keep OMP image attachments in PNG/JPEG using its supported WebP exclusion setting. Local llama.cpp decoders do not support WebP; the same image passed as PNG but produced incorrect answers as WebP.

- Require image blocks in live image-test requests and reject Codex shell workarounds during vision acceptance.

## [5.0.4] - 2026-09-16

### Fixed
- Preserve image attachments through the Claude Messages and Codex Responses gateway routes, including images returned by Claude's file reader.
- Configure Grok as a custom local model with the selected model, endpoint, context and key. A cloud proxy override could retain Grok's cloud model and OAuth credentials.
- Pass image support to OpenCode and Crush, and the selected context window to OpenCode and Codex.
- Resolve Crush's installed binary before changing its configuration directory, including Omarchy's mise install wrapper.

### Added
- `test/agents` exercises installed agents against ready models with real text, file read/write/verification and image requests. Evidence stays outside the repository; failed tool calls remain failures even when an agent recovers.

## [5.0.3] - 2026-09-16

### Fixed
- OMP uses the serving model's default reasoning settings instead of inferring an unsupported effort from its name. Refresh its migrated YAML configuration on every launch so switching models uses the selected model and endpoint.
- Pin the corrected gateway: rejected streaming requests retain their HTTP status and error body instead of appearing as successful empty streams.

## [5.0.2] - 2026-09-16

### Fixed
- The marketplace listing gets its image and its words back. `preview.png` returns to the repository root, cut from a live capture of the v5 card by `docs/preview.py`, and `manifest.json` carries a description that names what the card actually does. 5.0.1 removed the preview and the old description, which would have published a listing with no image and a v4 paragraph.

## [5.0.1] - 2026-09-16

### Fixed
- Remove demo recordings, recording scripts, logos and the obsolete preview from the repository. Embed the tiny vision/video readiness inputs in the controller so those checks need no loose media files.
- Keep UI source in `ui/` and design documentation in `docs/`.
- Publish a runtime-only archive and run the full test suite against its unpacked contents. Exclude development files from source archives as well.

## [5.0.0] - 2026-09-16

### Changed
- Run several models at once on separate GPU groups. Each has its own engine, gateway and port; starting a model replaces only models on the GPUs it claims, with rollback if acceptance fails.
- Home groups running models beneath their GPU type and marks occupied GPUs locked. Free GPU groups open the recipe picker, with a GPU-count selector and download, resume or run actions.
- Model details show decode and prefill speed, tokens today, KV capacity, context, GPU telemetry and capabilities, plus agent selection, sharing and Stop.
- Expand to a full-screen view from any page. The compact/full-screen control and F11 switch views without losing your selection; Escape returns to compact first.
- Qwen3.8 TP2 recipes use verified 262,144-token context on two RTX 3090s or two Arc Pro B70s. Context and chat, vision, video, tools and reasoning capabilities appear before launch; unknown metadata stays unknown. Pi/OMP and Crush receive recipe context, and Pi/OMP receive image support.
- Recipes update from the registry, including supported multi-card recipes. Existing local weights are reused only after verification against the pinned Hub revision.
- A single-GPU recipe prefers the free GPU with most available memory. vLLM memory utilization accounts for memory occupied by the desktop.

### Fixed
- The dot grid has a clear, continuous breathing animation while the panel is open.
- Agent and Stop buttons stay inside the screen on short displays and when the agent picker expands; only the body scrolls.
- Launch no longer silently retries at a smaller context. Acceptance checks runtime context and exercises advertised image/video input through the gateway.
- Deleted weights are downloaded again even if an old downloaded marker remains.
- Crashing engines report their failure promptly, with logs retained for diagnosis. Worker locking no longer leaves phantom operations or adopts a model during its own start.

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
