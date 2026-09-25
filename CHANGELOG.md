# Changelog

Versions follow semver and live in `manifest.json`. Every release is a tag `vX.Y.Z` on `main` and a GitHub release. The marketplace listing only ever targets a tagged release commit. See "Releasing" in `docs/design.md`.

## [6.1.6] - 2026-09-25

### Fixed
- Hermes opens on the running model. It takes its endpoint from its own `config.yaml` and ignores `OPENAI_BASE_URL`, so it used to start on whatever provider that file named. It now starts with `--provider custom`, `--model` and `CUSTOM_BASE_URL` for this session only: its `config.yaml`, memory and sessions are untouched, and only the gateway key is sent (thanks @Zodomo on omacom/omarchy#13036).

## [6.1.5] - 2026-09-25

### Fixed
- A start on an NVIDIA card whose CDI spec (`/etc/cdi/nvidia.yaml`) names device numbers that no longer match `/dev` now stops at once with the command that regenerates it, instead of loading until the 30-minute limit: Docker passes the cards through that spec, and after a driver update moved `/dev/nvidia-uvm` the engine saw no CUDA device (#17, thanks @carlbme).
- The activity grid files tokens under the local calendar day, so a daylight-saving change no longer moves an hour into the day before or after (the same bug @saitakarcesme found in the 5.x telemetry, #16).

## [6.1.4] - 2026-09-25

### Changed
- A faster snapshot: 5 jq runs instead of 29, about 130 ms instead of 220 ms on a machine with four GPUs and a running model. Each running model is read once and joined to its recipe in the last step, the GPU listings are parsed where they are matched, and a usage log that has not changed since its summary is not read again.
- The panel draws fewer frames: the border glow steps ten times a second and the Coming soon wave twenty, instead of sixty frames each, which is a quarter of the rendering while the panel is open on home. The glow runs only while a chart is on screen and the activity grid keeps its squares across refreshes.
- The log keeps its last 5,000 lines once it passes 1 MB.

### Fixed
- A model without a shipped logo (Gemma) no longer logs a missing-file warning each time its page is drawn.

## [6.1.3] - 2026-09-24

### Changed
- The listing's preview shows the 6.1 panel: home with your activity and the running models, a running model's page, and a card's Config with its models.

## [6.1.2] - 2026-09-24

### Changed
- Recipes at registry 0362dbdf: the Arc Pro B70's recommended Qwen3.8-27B EXL3 runs on exl3xpu 86276b00 with exact 1600-token KV blocks, 4096-token prefill chunks and prefix caching (272,570 KV tokens; thinking on, 16 streams 344-410 tok/s, up from about 295-349; a repeated 14K-token prompt answers in 1.8 s instead of 11.1 s).

## [6.1.1] - 2026-09-24

### Changed
- The store description and README say what 6.1 does: validated models per card, the recommended one first, and groups across cards.

## [6.1.0] - 2026-09-24

### Added
- Home leads with your lifetime: all-time tokens and requests over an activity grid of the last 20 weeks (a column a week, a row a weekday, each day shaded by its tokens), whether or not a model runs; hovering a day shows its date and tokens. A first run, with no answers yet, has none.
- A card's Config lists every model validated for it (the bundle now carries every recipe of the registry, 97 instead of 40), the recommended one checked; choosing another changes the page and what Run starts. A group's page does the same for models validated on that many cards.
- Groups: one model across several free cards of a kind, as their own row under AVAILABLE (e.g. "2 × RTX 3090") with Run and a Config page. `run <recipe> <gpu>,<gpu>` checks every card and gives the engine exactly those.
- An "all GPUs" page: every card as home's rows, so any of them, busy ones too, opens to its buttons and Config.

### Changed
- Buttons say what they do: "View logs" and "Stop model". A crashed row opens to Run again, View logs and Config; dismiss is on the row itself.
- The Hugging Face logo, in one colour, marks a model's weights.
- A group (one model across several free cards of a kind) is its own row under AVAILABLE, e.g. "2 × RTX 3090", with Run and a Config page for the group; a single GPU's row no longer offers groups.
- Icons instead of dotted lists: a model's page shows its format, cards, context, vision and size as icon chips; agent (a terminal prompt), folder, this machine and tailnet rows lead with an icon,; agent and folder open with a chevron and mark the chosen one with a check. A running card reads "Arc Pro B70  32 GB", with speed and tokens as icons in its corner.
- With no card to run on, the panel shows a thin square wave drifting left instead of a chip.
- Home is running and available: running models as cards (tall, with their token line drawn dim, speed and tokens small in the bottom-right corner), then the available GPUs as rows, free ones first, then crashed ones. A GPU already running a model is not listed again; cards another program holds or with no model are behind "all GPUs".
- A GPU row has one quick action on the right (run its model, or run again after a crash, with dismiss beside it); clicking the row opens it: its details or crash reason, then buttons like a model card's: Run (or Run again), Run on N cards, Config, Log, Dismiss (dismiss stops it, freeing the card).
- Model cards sit a little above the page, with a slow glow on their border; "now" sits at the chart's right edge. A vision model shows an eye on its page.
- The tailnet address stays hidden, small and dim, until clicked; "copy" is always beside it and copies it in one click.
- The header shows a smaller, dimmer version. Loading reads "loading".
- A model's page is the same for a running model and a free card: its token line and figures appear when it runs, its cards are the GPUS section (ticked to choose which a free one runs on), then Run or Log and Stop.
- The token line runs from the first answer to the last, so the latest growth sits at the right edge; its right label says how long ago that was.

### Removed
- Unused snapshot fields (`unsupported`, a kind's name, most of a group's fields) and the panel's dead row types.

### Fixed
- A snapshot no longer re-reads every usage log: each model keeps a summary beside its log (tokens per hour, counts and sums for the averages) that only reads the lines added since. With a million requests logged, a snapshot takes about 0.1 s instead of 5 s; the first read of an existing large log builds the summary once, 100,000 lines at a time.
- `run` refuses a recipe on a card of another kind.
- The panel flickered on every refresh: its rows were rebuilt each time. They now update in place.

## [6.0.3] - 2026-09-24

### Changed
- A design pass on the panel by Gil Rodrigues (0xSero/omarchy#2): every text and line colour is solved for an APCA contrast target from the active theme (the model's name and the primary action 90, values 80, labels 60, lines 15), so any theme stays readable; text starts and ends on one gutter; two type sizes; secondary buttons are outlined in the same ink as the primary fill.
- Home lists the running models, then the other cards under a GPUS heading: free cards with their run action, cards held by another program, cards with no validated model yet. Figure labels are lower case; a model's capabilities are one line.

## [6.0.2] - 2026-09-24

### Changed
- The password prompt says what it is for: "Local AI needs your password to start a model on your GPU", "to stop a model", "to change what your tailnet can reach", "to remove its models, containers and engines", instead of the backend's full path and arguments. `bin/omarchy-install-ai-local` installs `local-ai.policy` (the same polkit actions Omarchy's own Local AI ships) pointed at this plugin's backend; `bin/omarchy-remove-ai-local` removes it.
- The backend's privileged phases are `__start`, `__stop`, `__share` and `__purge`, one first argument each, so polkit can tell them apart.

## [6.0.1] - 2026-09-24

### Fixed
- A model a 5.x install left running showed as another program's, holding its card with nothing able to stop it. It is now taken over on the first snapshot: it shows as running and Stop takes it down.
- On a machine with two cards of the same kind, the free card's Run failed with "already running". A second copy of the model now runs on it, on its own port.
- A second copy's load percentage reached 95 in a minute and sat there; loads are now paced by the recipe's last load on any card.
- A snapshot the panel cannot read is shown as an error instead of as a machine with no GPU.
- Intel cards show how much memory they have instead of an estimate of what is used; the xe driver does not report it.

### Changed
- The bar mark is nine dots: faint when idle, lit when a model is ready, red when one failed, a ripple while one starts.
- No supported GPU is one line, a drawn chip and the link to the supported cards.

### Recipes
- Intel Arc Pro B70: the same Qwen3.8-27B recipe on the newer exl3xpu engine image (faster batched decode).
- RTX 4090: Qwen3.8-27B EXL3 on SGLang, the RTX 3090 recipe, in place of TabbyAPI.

### Added
- CI builds the panel's views from the backend's own snapshots under node, and scans the tree for secrets with gitleaks.

## [6.0.0] - 2026-09-23

Version 6 is a rebuild: the same files proposed for Omarchy itself in omacom/omarchy#13036, one bash backend, one view model, one panel and one data file. A model 5.x left running is taken over on the first snapshot: it shows as running and Stop takes it down.

### Changed
- One validated model per card. `recipes.json` is the first recipe of each card kind in the registry's export (EXL3 on SGLang or vLLM first), 36 card kinds, one per line. On an RTX 3090 that is Qwen3.8-27B on SGLang at 200K context with CUDA graphs on.
- The backend is `bin/omarchy-local-ai` alone. `run <recipe> <gpu>` claims a card and a port, then a detached worker downloads and checks the weights, starts the engine and the gateway, and sends one request to confirm the model answers at GPU speed. Each step is a line on the card and a notification says when it starts, is ready, or failed and why; loading shows a percentage paced by the last load.
- Without the docker group, a start, stop or share is one `pkexec` of this file; as root it takes the caller from `PKEXEC_UID`, re-reads and checks the recipe, and mounts only plain paths the caller owns. Engines run with `no-new-privileges`.
- The panel: one row per running model with its all-time token line, speed and tokens, and Open and More; a dashed row per free card kind that runs its model in one click; a bordered warning for a card another program holds or one with no validated model; Coming soon with the list of supported cards when nothing here can run. More shows the chart, six figures (decode, prefill, first token, session, week, up), the cards, the agent and folder, links to the weights and where the model answers.
- Agents: pi (the default), Claude Code, Codex, OpenCode, omp, Crush, Grok, Copilot and Hermes. The last agent and folder picked become the default; the last six folders are offered again.
- Share on the tailnet with `tailscale serve`, tailnet only and still keyed.
- Speeds are averages over every run of the model, from the gateway's usage log.

### Removed
- `CardRow.qml`, the stats and open pages, keyboard navigation, the `load`/`unload`/`agent` verbs and the Model.js node test. The ori, agy, muse and cursor agents are not offered.

## [5.4.0] - 2026-09-22

### Added
- Omarchy's native Local AI tab is generated from this plugin instead of copied by hand. `make native OMARCHY=<checkout>` writes its row data, row component and token bars from `ui/`, `make native-check` fails when the copy has drifted, and `test/native` checks the same contract without a checkout. A card change is now made once here and published with one command.
- `native/backend-command.js` holds the one part of the native view that is native to it: resolving the installed controller from Omarchy's plugin registry.

### Changed
- The native view's backend gate requires 5.4.0 or newer, so it runs only against a controller whose rows it was generated from. `test/native` covers the boundary: 5.4.0, 5.4.1 and 5.10.0 launch, 5.3.7 and everything older or newer does not, and a missing backend never does.
- `recipes.json` is now taken verbatim from the registry's published export (`make sync`), and `make check` fails when the vendored copy has fallen behind it, so the registry is the only place a recipe is authored. `make sync-check` compares the two with the two provenance fields removed, so a registry re-stamp is not drift while a withdrawn or changed recipe still is, and it names the cards that differ. It reads the registry's *published* export — the file committed at its `origin/main`, not whatever a checkout has in its working tree, which can be ahead of it or behind it — and falls back to the working-tree file only when there is no such ref. `test/sync` covers all three cases without a registry checkout. The plugin's CI checks out the registry to run that comparison, a daily job commits the export when it moves, and the release runs the same checks before it publishes — the same export the plugin already stages at runtime, so an installed plugin sees new recipes without waiting for a release. 82 recipes across 37 cards now, five more than 5.2.0's catalog.
- Each model is one row on a GPU page, and that row is the action: **Download & run**, **Load**, **Resume & load**, **Load another** or **Swap**, naming its size, with its context and capabilities beside it. Selecting a model no longer reveals a separate button underneath, and a model whose load would replace a running one names the models being replaced in its own row.
- A GPU page no longer repeats the card as a row. Its title and breadcrumb already name the card, so the per-card state moves into the subtitle.

### Validation
- The 128 KiB fixture asserts that the snapshot names the recipe file it used rather than a stamp from that file, so a registry refresh cannot break it.
- The suite now reads the same on jq 1.6 (Ubuntu 22.04, Pop!_OS) and on 1.7+: its argv conversion drops the trailing field only when it is empty, because jq 1.6 strips the final NUL in `-Rsc` where 1.7 and later keep it.
- The click suite passes on Omarchy: 42 scroll cases, 2 hit-area cases, 2 flow cases and 2 breadcrumb cases, no failures.

### Fixed
- `manifest.json`'s `description` — the listing's own words — names the supported hardware and the validated recipe count again: 82 recipes across 37 cards, NVIDIA RTX 30/40/50, RTX Ada, RTX Pro Blackwell, Intel Arc Pro B70 and AMD ROCm. 5.2.0 replaced the paragraph that named them with one that did not, and the listing reads this field at the published commit.
- Every `Text` in `ui/CardRow.qml` and `ui/TokenTotal.qml` whose `text` is not a bare literal now declares `textFormat: Text.PlainText`. Omarchy's own scan requires it, and the native copies already did: `Text.AutoText` promotes a string that looks like markup and fetches `<img src>` from it, and a model name, a device label, a share URL or a refusal sentence can carry the opening `<`.

## [5.3.7] - 2026-09-21

### Fixed
- Keep a running recipe available when another GPU can host it. Load another instance with a separate endpoint, without stopping the first model.
- Expose only assigned Intel render devices so a launch on GPU 1 cannot fall back to the busy GPU 0.
- Track deployment instances separately from recipe identity, preserving targeted agent launch, restart, unload, rollback and recipe running status.

## [5.3.6] - 2026-09-21

### Fixed
- Make the whole actionable row clickable, including indented choices and device meters; nested Copy buttons activate only their own action.
- Offer Swap model when a selected model needs occupied GPUs. Show which running models will be replaced, then use the controller's existing load and rollback path. Models on other GPUs keep running.

## [5.3.5] - 2026-09-21

### Fixed
- Reveal capacity guidance when selecting a model while its GPUs are occupied, matching the automatic reveal of an available Load action.

## [5.3.4] - 2026-09-21

### Fixed
- Give every GPU row the same destination: its running models and compatible model list. Remove the duplicate Models / Stats & agents navigation buttons; use the direct breadcrumb links to move between levels.
- Put a selected model's details and Load action immediately below that model, revealing the action on selection. Running models open directly and appear only once; remove the disconnected picker footer.
- Keep the home agent-launch action visible even when its configuration is collapsed, with the selected model shown above it.

## [5.3.3] - 2026-09-21

### Fixed
- Scroll the full standalone page, including headers, folder editing and footer actions; use the native Agents viewport when embedded. Add Home/End and Page Up/Down, reveal keyboard selections, and clamp scrolling after resize.
- Make every breadcrumb a direct link, wrapping on narrow screens. Clicking the current destination also returns to the top. Allow browsing during deployment work with a visible return-to-progress action and conflicting operations disabled.
- Add native wheel, keyboard and breadcrumb regression checks across both presentations and three viewport sizes.

## [5.3.2] - 2026-09-21

### Fixed
- Separate deployment management from token reporting. The overview shows stable GPU deployment rows with the running model, visible status, and explicit Manage or Load model actions.
- Move historical token totals into a separate read-only section below deployments. Usage bars no longer launch model controls or take keyboard focus; hide the section when no usage has been recorded.

## [5.3.1] - 2026-09-21

### Fixed
- Lead the overview with historical GPU token totals using the same filled-row geometry, typography and colors as the native Claude/Codex model totals. Remove the separate activity graphs; zero and unavailable usage remain compact rows.
- Backfill retained vLLM and llama.cpp logs plus attributable older gateway receipts, including models no longer running. Avoid overlapping receipts, preserve totals across unloads and midnight, and read new log output incrementally.
- Mark vLLM totals as estimates from rounded runtime rates. Keep today's generated-token count and non-zero runtime speed averages in model details, and show today's count with GPU status on hover.

## [5.3.0] - 2026-09-21

### Added
- Compact token activity graphs under each GPU group in the overview. Each has a fixed 24-hour axis, observed-token total and a time/value readout on hover.
- Fifteen-minute token buckets collected by the existing ten-second telemetry cache. Histories survive model unloads and reset at local midnight; a multi-GPU model is counted once per group. Earlier unrecorded intervals remain blank.

## [5.2.0] - 2026-09-21

### Added
- Optional Local AI tab inside the native Agents panel, using its typography, section headers and separators. The overview has a compact agent launcher and one status row per GPU type; expand or open a model for details.
- Agent, running-model and project-folder selection at the top of the overview and model view. GPU groups remain browsable while occupied.
- NVIDIA, Intel Level Zero/DRM and AMD sysfs telemetry adapters with temperature, usage and VRAM meters in model details. Missing sensors show N/A.
- Incremental vLLM and llama.cpp statistics: today's average non-zero decode/prefill log samples and generated-token counter deltas, with a shared ten-second cache. Other engines show unavailable statistics.
- Optional Mac/Moonlight bindings and a separate OS status-bar shortcut button with an offline visual guide. The integration installer backs up user configuration and leaves system files untouched.

### Fixed
- Show share URLs in a fixed full-panel overlay until copied or closed; keep failures and actions visible above the fold.
- Enter the selected project directory inside the terminal after UWSM starts it; explicitly allow OMP to run in home instead of relocating to a temporary directory.
- Pass Pi's thinking option as separate arguments and set OpenCode's main and small model in its launch configuration.
- Replace acceptance-only token totals and fixed acceptance speeds with runtime measurements. The first day's token count starts when tracking begins.
- Add telemetry and all eleven agent handoff checks to the shipped-bundle tests; include integration assets in the release archive.

### Validation boundaries
- Pi, OpenCode and Crush terminal startup was checked on the mixed NVIDIA/Intel desktop; all eleven launch adapters have fixture coverage. Startup is not full conversation or tool acceptance for every agent.
- NVIDIA and Intel telemetry was checked on hardware. AMD has fixture coverage and still needs physical-device acceptance.
- The final compact layout passed row-data and QML loading checks; final visual acceptance remains open. The offline guide's browser rendering also remains unverified.

## [5.1.0] - 2026-09-17

### Added
- One update row on the card's home, and one verb behind it. A background check — at most once per six hours, never on the card's critical path — reads the registry's recipes and this repository's own `manifest.json`, stages what is newer, and adopts nothing; the row says `v5.1.1 + 3 for your card ›` when something is staged. `omarchy-local-ai update` applies the staged registry copy and then updates the harness through Omarchy's own `omarchy plugin update <id> --yes`. `update --check` fetches and stages only.
- Analytics: the daily `traffic` workflow now records every release asset's cumulative `download_count`, a per-day interaction tally (stars, forks, watchers, issues, PRs, discussions, commits on the default branch) from one GraphQL call, and the repository snapshot with its date archived inside the file, so a star timeline is derivable. [17 — Stats](https://0xsero.github.io/omarchy-local-ai/#17-stats) renders `traffic/summary.json` live.

### Changed
- The registry copy is no longer adopted silently. The background check only stages it (`$STATE/recipes.next.json`) and reports what it holds — whether a newer copy is waiting, how many recipes it adds, and how many of those are for the cards actually detected. A newer copy that changes recipes without adding any still reads as staged, so it can be applied from the card. What runs is the marketplace-reviewed vendored file until the user applies the update. `recipes update` still fetches and adopts in one step.

### Fixed
- `traffic.yml`'s jq program had been invalid since `d6828f9`, so the scheduled run of 2026-09-17 failed and the daily record had been reporting only clones and views. The step now runs with `pipefail`, so a failing `gh` fails the run instead of letting jq turn an error body into zeroed counters. Its `actions/checkout` is pinned by commit like the repository's other workflows.

### Internal
- `OMARCHY_AI_RECIPES_TTL` becomes `OMARCHY_AI_UPDATE_TTL` (it now clocks both checks); `OMARCHY_AI_UPDATE=0` or an empty `OMARCHY_AI_MANIFEST_URL` turns the release check off. `recipes_autorefresh` is replaced by `upstream_autocheck`, and the repository root is computed once in `lib/common.sh`.
- Recipe files reach jq as file inputs, never as arguments: the published `recipes.json` is past the 128 KiB cap Linux puts on one argument, so passing its contents would have failed every snapshot on Omarchy. Adopting a staged copy now re-validates the file it is about to move, so a check that races an update cannot downgrade the file in use.

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
