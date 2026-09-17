# 14 — Troubleshooting

## Where to look, in order

| Source | Command | Shows |
|---|---|---|
| the ledger | `jq . ~/.local/state/omarchy/local-ai/ledger.json` | the op, the last error, every running slot with its acceptance record |
| the snapshot | `omarchy-local-ai snapshot \| jq '{state, error, reason, models: [.models[] \| {name, state, note}]}'` | exactly what the card sees |
| the log | `less +G ~/.local/state/omarchy/local-ai/log` | every worker step, docker argv, rollback, adoption, refusal |
| the containers | `docker ps -a --filter label=io.omarchy.local-ai=1` | what is really running, and what was set aside |
| an engine | `docker logs --tail 200 <name>-engine` | the engine's own words |
| the panel | the card's `log ›` row, or `omarchy-launch-tui --app-id=org.omarchy.local-ai-log less +G …/log` | the same log in a terminal |

The log is the authority on *why*. The card deliberately shows one sentence; the log has the sequence.

## Every message the plugin can print

### Hardware and recipes

| Message | Cause | Fix |
|---|---|---|
| `no supported GPU detected` | no NVIDIA driver `nvidia-smi`, no PCI-id-matched Arc with a render node | install the driver; check `nvidia-smi` runs as your user |
| `no validated recipe for <product> yet` | the card is detected but no hardware id matches | check `recipes update`; else that card genuinely has no validated recipe |
| `recipe refused: <reason>` | the launch gate | see [3 — Recipes](03-recipes.md); the reason names the rule |
| `recipe needs 2 rtx-3090-24gb cards, 1 detected` | a multi-card recipe with too few cards | add the second identical card, or pick a one-card recipe |
| `recipe claims cards of different backends` | a claim spanning NVIDIA and Intel | not runnable in one container; pick another recipe |
| `needs NVIDIA driver 575.0 or newer` | the image's CUDA needs a newer driver | update the driver, or use a recipe for your driver |
| `port 12434 is in use by something else` | a foreign listener on the gateway port | find it (`ss -ltnp "sport = :12434"`), stop it, or unload stale containers |
| `recipes.json is missing or broken: reinstall the plugin` | the vendored file is gone or invalid | reinstall, or `make sync` in a checkout |
| `missing tool: jq (sudo pacman -S jq)` | `jq`/`curl` absent | install them |
| `recipes: could not fetch the registry (…); keeping <source>` | no route to the registry | not fatal — the file in use stays in use |

### Docker

`docker_reason` translates docker's own last line into the sentence that fixes it.

| Message | Cause | Fix |
|---|---|---|
| `Docker refuses your user: sudo usermod -aG docker $USER, then log out and in` | the socket is not writable and prompt mode was bypassed | enable Omarchy's *Sudoless Docker*, or leave it to the prompt |
| `Docker is not running: sudo systemctl enable --now docker` | the daemon is down | as printed |
| `the NVIDIA container toolkit is not set up: sudo pacman -S nvidia-container-toolkit; sudo nvidia-ctk runtime configure --runtime=docker; sudo systemctl restart docker` | the runtime is missing | the plugin installs this itself inside the same prompt, when it can; this appears when the prompt was dismissed |
| `out of disk space for <what>` | the disk filled mid-pull or mid-download | free space; a partial download resumes |
| `the registry refused the pull: run docker logout ghcr.io and try again` | bad registry credentials | as printed |
| `no route to the image registry: check the network and try again` | DNS/TLS/timeout | as printed |
| `the pinned image is missing from the registry: report this` | `manifest unknown` for a digest | the digest was deleted upstream — report it |
| `the password prompt was dismissed; nothing was changed` | polkit returned 126/127/128+ | retry, and keep the prompt open |
| `docker network <n> exists but is not managed by this plugin` | a foreign network with our name | remove or rename it: `docker network rm <n>` |
| `<name> exists but is not managed by this plugin` | a foreign container with our name | `docker rm -f <name>`, or rename it |
| `mount outside boundary: <src>` | a mount the gate also refuses, caught a second time | recipe bug: report it |

### Starting, acceptance, rollback

| Message | Cause | Fix |
|---|---|---|
| `engine exited during startup (docker logs <name>)` | the engine's process died | read the log; the error is usually a bad config asset or a missing mount |
| `engine keeps crashing: <last line> (docker logs <name>)` | a crash loop under `--restart unless-stopped` | the quoted line is the cause — commonly a read-only mount the engine tries to write into |
| `engine did not answer within <n>s` | the model is too slow to load for `OMARCHY_AI_TIMEOUT` | raise the timeout, or check the engine log |
| `served model <a> is not <b>` | the engine loaded something else | wrong file in the mount, or the wrong revision |
| `runtime context <n> is below the recipe's <m> tokens` | the engine silently truncated the context | fix the recipe's `--ctx-size`, or the memory cap lowered the share too far (see the next row) |
| `gateway answers without the key` | the gateway cannot read the key file | check `$STATE/gateway.key` exists and the gateway runs as your uid (`docker inspect -f '{{.Config.User}}' <gateway>`) |
| `reasoning leaks into the answer: the engine's reasoning parser is off for this model` | think tags in `content` | the engine needs its reasoning parser on for that model |
| `decode <n> tok/s is below the <f> tok/s floor: the GPU is not being used (driver too old for this image?)` | CPU fallback | update the driver, or use a recipe whose image matches your driver |
| `vision acceptance failed` / `video acceptance failed` | the model did not read the red fixture | an incorrect multimodal path — report it with the log |
| `tool-call acceptance failed` | the gateway did not scrub a tool schema the grammar cannot take | report it with the log |
| `rollback: <why>` | a failed Start is restoring what it replaced | informational; the reason follows |
| `the previous model could not be restored (see $LOGFILE)` | rollback failed | inspect `docker ps -a`; the set-aside pair is named `<name>-previous` |
| `gpu memory utilization 0.97 lowered to 0.83: that is what is free on the card` | the card also drives the desktop | informational; an engine that then cannot fit its context fails loudly rather than silently downgrading |
| `stopped unexpectedly while <detail>; press Start again (see $LOGFILE)` | a worker died without its exit trap | read the end of the log; Start again |
| `the worker could not start (see the log)` | the spawned worker was gone before its first word | read the log |

### Weights and downloads

| Message | Cause | Fix |
|---|---|---|
| `need <n> GB free under <path>` | not enough disk | free space; a partial resumes |
| `weights for <id> are marked complete but the files are gone; fetching again` | the marker outlived the files | not fatal; the download repeats |
| `weight download failed for <id> (see $LOGFILE)` | the downloader failed | the log has docker's own reason |
| `the download runs behind the password prompt and cannot be stopped from here` | `unload` during a prompt-mode download | wait for it, or stop it from the prompt's own session |
| `cannot list <repo>@<rev> on the Hub (offline?); nothing adopted` | no cached tree and no network | not fatal; the download proceeds |
| `found <cand> but <path> is missing or its size differs from the pinned file; skipped` | an older quant or an incomplete copy | informational; the pinned files are fetched |
| `found <cand> but <path>'s checksum differs from the pinned file; skipped` | an edited or corrupted copy | informational |
| `could not place the copy from <cand>; downloading instead` | the reflink/link/copy failed | check free space and permissions on the destination |

### Sharing

See [10 — Sharing](10-sharing.md). The short version: `tailscale is not installed or not logged in`,
`tailscale is not connected`, `load a model first`, `tailnet address changed; share again`,
`still shared: could not restart the gateway (see $LOGFILE)`,
`could not publish on the tailnet: <docker's line>`.

### Agents

| Message | Cause | Fix |
|---|---|---|
| `load a model first` | no ready model | Start one |
| `<name> cannot use this model: its API dialect did not pass acceptance` | the engine does not serve that dialect | pick another agent, or a recipe whose engine serves it |
| `<name> is not installed` | the binary is not found | install it, or place it in `~/.local/bin` |
| `could not open a terminal for <name>: omarchy-launch-tui is missing` | no launcher | install Omarchy's launcher |
| `could not open a terminal for <name>: the uwsm app daemon is not answering` | uwsm is wedged | restart uwsm; the plugin already tried the plain client |
| `agent-args <agent> [-- flags...], one of: …` | wrong agent name | use a name from the list printed |
| `agent-dir: not a directory: <path>` | the path does not exist | create it first |

## Procedures

**Stop everything, including strays**

```bash
omarchy-local-ai unload
docker ps -a --filter label=io.omarchy.local-ai=1     # should be empty
docker rm -f $(docker ps -aq --filter label=io.omarchy.local-ai=1)   # only if it is not
```

**A busy card that is not actually busy.** The busy flag is `.op.pid` being alive.

```bash
jq '.op' ~/.local/state/omarchy/local-ai/ledger.json
ps -p <that pid>          # gone?
omarchy-local-ai snapshot # the next snapshot clears a vanished worker and says so
```

If a worker really is stuck, `kill <pid>`; its exit trap writes the reason, and the next snapshot
clears the op either way. Never delete `op.lock`: `flock` releases it when the owner dies.

**Force a re-download for one recipe**

```bash
rm ~/.local/state/omarchy/local-ai/weights/<recipe-id>.json
omarchy-local-ai run <recipe-id> <backend:index>
```

Weights already on disk are still adopted if they verify, so this is cheap.

**Force the adopted-copy search to be skipped** — nothing to configure: delete the cached trees
(`~/.local/state/omarchy/local-ai/trees`) and the search still runs, but it can no longer verify, so it
adopts nothing and downloads. Set `OMARCHY_AI_WEIGHTS_PATHS=` (empty) to remove the extra roots.

**See exactly where the plugin would put things**

```bash
OMARCHY_AI_NO_HOST_HF=1 omarchy-local-ai snapshot | jq '.selected'
```

**Read a phase's own output.** `$STATE/phase.out` holds the last root phase's stdout (`step …`,
`reason …`), and `$STATE/gate.err`, `accept.err`, `agent.err` hold the last gate, acceptance and agent
errors. They are written for exactly this.

**A model is running but the card says it is stopped.** The snapshot's model state comes from the
gateway answering and the acceptance record, not from docker. Check the gateway:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:12434/v1/models          # expect 401
curl -s -H "Authorization: Bearer $(cat ~/.local/state/omarchy/local-ai/gateway.key)" \
     http://127.0.0.1:12434/v1/models | jq -r '.data[0].id'                        # expect the served model
```

**Reset the panel without touching the model**

```bash
quickshell ipc --any-display -p /usr/share/omarchy/shell call sero.local-ai refresh
```

**Start over completely** (models stopped, downloads kept)

```bash
omarchy-local-ai unload
rm -rf ~/.local/state/omarchy/local-ai
```

The next Start regenerates the key, the assets and every marker; weights under
`~/.cache/omarchy/local-ai/` are untouched and re-verified on adoption.