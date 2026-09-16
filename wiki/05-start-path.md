# 5 — The Start path

What happens between pressing Start and the word **ready**. Everything below is
`w_load` in `bin/omarchy-local-ai` plus the functions it calls; the class names in brackets are the
`op.detail` strings the card shows.

## The verb

```
omarchy-local-ai load                      # the selected recipe and card
omarchy-local-ai run <recipe> [<backend:index>]   # pin both and start, one process, as the card's run row does
```

`load` refuses immediately when `busy_pid` finds a live worker: `another operation is running`.
Otherwise it waits up to 5 s for the lock, then `spawn`s a `_worker-load` process and records it with
`op_pending`, so the panel's next snapshot is already busy. The worker is started with `setsid` when
available, so closing the panel never kills it.

`run` additionally validates the recipe id against the file (`run <recipe> [gpu], as listed in the
snapshot`), writes `$STATE/recipe-pick` and optionally `$STATE/gpu` **without** a snapshot each, then
spawns the same worker. One `run` therefore costs one process and one snapshot, instead of three
verbs.

## Inside the worker

### 1. Take the lock, arm the trap

`guard` (flock on `$STATE/op.lock`), `trap worker_exit EXIT`. From here on, any unexpected death leaves
a reason on the card.

### 2. Check the GPU and the recipe — `op download "" "checking the GPU and recipe"` `[checking]`

`current_recipe`:

1. `match_hardware` → a hardware id, or the reason (`no supported GPU detected` / `no validated recipe for <product> yet`);
2. `recipe_for <id>` → the picked or recommended recipe;
3. attach `gpuIndex` and `match.backend`;
4. `gate_reason` → `recipe refused: <reason>` on failure;
5. `claimed_indexes` → the device indexes; a short claim fails with its sentence;
6. `driver_ok <have> <minDriver>` → `needs NVIDIA driver <min> or newer`.

Any failure goes through `oops`, which writes `.error` and exits: the card shows the reason and the
previous model, if any, is untouched.

### 3. Docker and the toolkit `[checking]`

In direct mode, `docker_ok <backend>` asks `docker info`: a failure is translated by `docker_reason`
into the sentence that fixes it (see [14 — Troubleshooting](14-troubleshooting.md)). One failure is
special-cased: a missing NVIDIA container toolkit is not fatal, because it can be installed behind the
same prompt. The worker sets `op download <id> "setting up the NVIDIA container toolkit (your password)"`
and runs the `toolkit` phase. In prompt mode this check happens *inside* the start phase instead, so it
costs no extra prompt.

### 4. Weights

- if the marker exists but the files do not: log `weights for <id> are marked complete but the files
  are gone; fetching again` and delete the marker;
- `weights_present` → weights are already there (marker + files);
- else `weights_find`: a verified copy already on this machine is adopted, and nothing is downloaded
  (see [6 — Weights](06-weights.md));
- `weights_plan` computes the destination, the expected size `WEXP`, the free-space check and the
  download pattern; running out of space fails as `need <n> GB free under <path>`.

### 5. Prepare: `mount_dirs`, `write_assets`, `ensure_key`

Host mount roots are created with the ordinary umask (the container's uid must traverse them), the
recipe's `asset/*` files are written from `recipes.json` into `$STATE/assets/` (0644, mounted
read-only), and the gateway key is generated if this is the first Start.

### 6. Slot planning

`slot_plan` allocates the slot in the recipe JSON: port, network name, engine and gateway container
names, and **`victims`** — the slots this Start will replace, which are its own earlier run of the same
recipe plus every slot holding one of the cards it claims. The plan is written to `$STATE/recipe.json`
(0600) so a root phase can read exactly what it was asked to run, and the log gets
`start <id> replaces <names> (same cards)` when there is anything to replace.

The port rule: a recipe that is already running keeps its port (so agents holding the old address keep
working); otherwise the lowest free port from `$PORT` (12434) to `$PORT+15` that no slot holds **and**
nothing listens on — `no free port between $PORT and $((PORT + 15))` when none is free.

### 7. Download

Two paths, and the first is preferred:

- **host `hf`** (`download_host`), when the `hf` CLI is installed and `OMARCHY_AI_NO_HOST_HF` is unset:
  `hf download <repo> --revision <rev>` with `--local-dir` for local-dir recipes and `HF_HOME` for hub
  recipes, plus `--include <file> --include *mmproj*` for single-file GGUF recipes. Runs as the user,
  no docker, no prompt. Progress is computed from the directory's size against `WEXP`.
- **the recipe's own image** (`download_run`, inside the start phase): a `docker run --rm` of the
  engine image with `--entrypoint python3 -c "from huggingface_hub import snapshot_download …"`,
  labelled `io.omarchy.local-ai.download=1` (which is what makes `unload` able to kill it),
  `HF_HOME=/tmp/hf` for local-dir recipes and `/hf` for hub ones. Root's side reports `step downloading
  weights` and the user's side turns the directory's growth into a percentage each `POLL` seconds.

A finished download writes the marker (`weights_mark`).

### 8. Start the pair — `phase_run start` inside the phase

Everything docker-touching in one phase, so prompt mode costs **one** password prompt:

1. `docker_ok` (and toolkit installation if needed, in prompt mode);
2. `ensure_image` for the engine image, then for the gateway image — `docker pull` once each, by
   digest; `step pulling image` is what the card shows as *pulling*;
3. `download_run` if weights are still needed;
4. `drop_previous` — any stale `*-previous` pair from an earlier died Start is removed;
5. `set_aside` — every victim's engine and gateway are `docker rename`d to `<name>-previous`
   (stopping the running one first, removing any older `-previous`), after `owned` proves they are
   the plugin's containers. A container of that name that is **not** the plugin's is a refusal.
6. `start_pair` — network (created if absent, labelled; a same-named foreign network is refused), then
   the engine, then the gateway.

The user's side watches `phase.out` and turns `step …` lines into card detail text and percentages
(`phase_run` in `lib/priv.sh`). While waiting in prompt mode it shows
`waiting for your password`.

### 9. Record the slot

Before acceptance, the slot is recorded in the ledger with `accepted: null` and written to
`$STATE/slots/<id>.json`; the previous record for that recipe is copied to `.prev`. This is what makes
a model appear on the card as *never verified; press Start* if the worker dies here, rather than as a
silent success. `slots_file` regenerates `gateway.recipe.json`.

### 10. Acceptance, and rollback

`accept` runs the full battery described in [8 — Acceptance](08-acceptance.md).

- **pass** → `.slots[<id>].accepted` is written; the loop breaks.
- **fail** → `log "rollback: <why>"`, tell the card `op starting <id> "rolling back"`, append the
  failed engine's own last 400 log lines to `$STATE/log` (so the root cause is still readable after the
  container is gone), then `privileged restore` puts every victim's `-previous` pair back in the same
  prompt, and the slot record is restored from `.prev` or removed. The worker then `oops`es with the
  acceptance reason — so the card shows *ready* (the restored model) **and** the reason beside it.

An engine that starts crashing at once under `--restart unless-stopped` is caught in seconds rather
than at the timeout: `engine_alive` fails on `State.Restarting` or `RestartCount ≥ 2` and reports the
engine's last meaningful log line.

### 11. Finish

- Victims that are not the new recipe are forgotten from the ledger and their slot files removed.
- In direct mode `drop_previous` removes the set-aside pairs — the replaced models are gone for good,
  and no second prompt is spent on success.
- `.lastStartSeconds = SECONDS - t0` (first container step to accepted) is recorded for the next
  Start's progress bar.
- `op_done` + `log "ready <id>"`.

## Stop

```
omarchy-local-ai unload [<recipe>]
```

- **with an id**: the slot record must exist (`no model <id> is running`), `op unload <id> "stopping <name>"`,
  then the `stop` phase removes that slot's engine, gateway and any `-previous`, and its network. The
  slot is forgotten; if it was the last one, `share_forget` drops the share marker — only once the
  published gateways are really gone.
- **without an id**: `op unload "" "stopping"`, the `stop` phase removes **every** container carrying
  the plugin's label, `share_forget`, `.slots = {}`, `$STATE/slots/` removed.
- In prompt mode the card first shows `waiting for your password`; a dismissed prompt is
  `the password prompt was dismissed; nothing was changed`.

Downloads are not containers of a slot: while a `download` op is live, `unload` is routed to
`cancel_download`, which (unless the download is running behind a prompt, where it cannot be reached)
sets `$STATE/cancel`, TERMs the worker's process group, escalates to KILL after 10 s, removes any
labelled downloader container, clears the op and logs `download stopped; partial weights kept`. Partial
weights stay on disk unmarked, and the next Start resumes them.

## `share` while a model runs

`share` is an op too (`op share "" "stopping the tailnet route"` / `"publishing on the tailnet"`), so the
toggle shows progress. It is never on the critical path of a Start: it only restarts gateways. See
[10 — Sharing](10-sharing.md).

## Every way a Start can stop, and what you see

| Stage | Failure | `.error` |
|---|---|---|
| recipe | gate | `recipe refused: <reason>` |
| recipe | short card claim | `recipe needs 2 rtx-3090-24gb cards, 1 detected` |
| recipe | driver | `needs NVIDIA driver 575.0 or newer` |
| docker | not in the group | `Docker refuses your user: sudo usermod -aG docker $USER, then log out and in` |
| docker | daemon down | `Docker is not running: sudo systemctl enable --now docker` |
| docker | toolkit missing | `the NVIDIA container toolkit is not set up: …` |
| disk | no space | `need <n> GB free under <path>` |
| pull | registry | `the registry refused the pull: run docker logout ghcr.io and try again` |
| pull | network | `no route to the image registry: check the network and try again` |
| download | failure | `weight download failed for <id> (see $LOGFILE)` |
| start | engine died | `engine exited during startup (docker logs <name>)` |
| start | crash loop | `engine keeps crashing: <last log line> (docker logs <name>)` |
| acceptance | any | the acceptance sentence, with the previous model restored |
| any | worker killed | `stopped unexpectedly while <detail>; press Start again (see $LOGFILE)` |