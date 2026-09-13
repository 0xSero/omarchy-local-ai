# Changelog

Versions follow semver and live in `manifest.json`. Every release is a tag `vX.Y.Z` on `main` and a GitHub release. The marketplace listing only ever targets a tagged release commit. See "Releasing" in `DESIGN.md`.

## [Unreleased]

### Changed
- The card is a command stack: one recessed state slab (state, title, the orb) over rows of noun and datum. Drill-down is a path stack (`local ai / options / registry`); esc and back pop one level. Idle shows the claimed card group, the next action and an options count; ready shows the primary command, `runtime · 3 · stats live` and stop; agent, stats and share sit one level deeper. Every state breathes through the orb, and a download grows its lit radius.
- Identical GPUs aggregate (`2× RTX 3090 · 48 GB total`); a recipe claims cards from its own group and the rest read idle. Recipes on disk say so and their action is `run`; a card reopened while a model runs opens in ready on the live recipe; a selection that differs from the running recipe offers `run · swap`; a running recipe the file no longer carries offers `update + restart`.
- Stats behind `runtime / stats`: decode and prefill speed measured at acceptance, tokens served by hour, day or week, VRAM in use.
- Snapshot 8 adds `cards`, `recipes`, `selected`, `port`, `stats`, `registryCount`, `registryList`, and `running.name` / `running.older`; nothing the old panel read has moved. A foreign listener on the gateway port is reported as a reason.

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
