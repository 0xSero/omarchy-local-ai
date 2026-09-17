# 7 — Containers

One running model is a **slot**: an engine container on a private bridge network of its own, and a
gateway container published on `127.0.0.1:<port>`. Only labelled containers are ever touched.

## Labels

| Label | Value |
|---|---|
| `io.omarchy.local-ai` | `1` — the ownership marker; every command filters on it |
| `io.omarchy.local-ai.recipe` | the recipe id |
| `io.omarchy.local-ai.registry` | the `registryCommit` the container was started from |
| `io.omarchy.local-ai.role` | `engine` or `gateway` |
| `io.omarchy.local-ai.download` | `1`, on the throwaway downloader container only |

Ownership is proven, never assumed: `owned <name>` requires the label to be exactly `1`. `set_aside`
refuses to touch `<name>-previous` unless it is ours, and `ensure_network` refuses a same-named network
that is not labelled — the engine is reachable on that network, so a foreign one is a security problem.

## Names and ports

| Thing | Name |
|---|---|
| engine | `omarchy-local-ai-<recipe-id>-engine` |
| gateway | `omarchy-local-ai-<recipe-id>-gateway` |
| network | `omarchy-local-ai-<recipe-id>` |
| set-aside copy | `<name>-previous` |

Ports run upward from `$PORT` (default `12434`): the lowest in `[$PORT, $PORT+15]` that no slot holds
*and* nothing listens on. A recipe that is already running keeps its port, so agents holding its
address survive a restart.

## The engine's argv — `engine_argv`

```
docker run --detach --name <slot.engine> --restart unless-stopped \
  --network <slot.net> --network-alias engine \
  --label io.omarchy.local-ai=1 --label ….recipe=<id> --label ….registry=<commit> --label ….role=engine
```

Per backend:

| Backend | Added |
|---|---|
| `nvidia` | `--gpus device=<i>`, or `--gpus "device=0,2"` for a multi-card claim — **quoted**, because docker parses the value as a csv and unquoted `device=0,2` reads as "device 0 plus count 1" (`cannot set both Count and DeviceIDs`) |
| anything else (Intel) | `--device <real>:<real>` for every `*-render` node under `/dev/dri/by-path` (symlinks resolved), plus `--volume /dev/dri/by-path:/dev/dri/by-path:ro`. No control nodes, never the whole `/dev/dri`; none found is `no render nodes found` |

Then `--shm-size` when the recipe sets `launch.shm`, the mounts, the environment, the entrypoint, the
image and the recipe's arguments.

Mounts resolve by kind: `${MODEL_ROOT}`/`${CACHE_ROOT}` are canonicalized and created with the
ordinary umask; `~/.cache/huggingface` likewise; `asset/*` becomes `$STATE/assets/<file>:ro`;
`/dev/dri/by-path` passes through. Anything else fails as `mount outside boundary: <src>` — the same
boundary `gate_reason` enforces, checked twice.

### The memory cap

A validated recipe asks for the share of the card it had on a bare machine — often
`--gpu-memory-utilization 0.97`. On a card that also drives the desktop (Hyprland alone holds
gigabytes) that share does not exist. `memory_cap` computes

```
min over the claimed NVIDIA cards of  floor(freeMiB / totalMiB × 100) / 100     (clamped to ≥ 0.1)
```

and `engine_argv` lowers any `--gpu-memory-utilization` above it, logging
`gpu memory utilization 0.97 lowered to 0.83: that is what is free on the card`. Nothing else is
rewritten: a context that does not fit must fail loudly rather than be silently downgraded.

## The gateway's argv — `gateway_argv`

```
docker run --detach --name <slot.gateway> --restart unless-stopped \
  --network <slot.net> --user <RUN_AS> --publish 127.0.0.1:<port>:12434 \
  --label … role=gateway   [--publish <tailnet ip>:<port>:12434 while sharing] \
  --env UPSTREAM=http://engine:<launch.containerPort> \
  --env MODEL=<model.servedName> \
  --env GATEWAY_KEY_FILE=/run/gateway.key \
  --volume <$STATE/gateway.key>:/run/gateway.key:ro \
  <gateway image>
```

Three load-bearing details:

- `--user <RUN_AS>` (`uid:gid`, from pkexec in prompt mode): the image's own uid (10001) cannot read
  the 0600 key file, and a gateway that cannot read its key silently serves keyless.
- The key is mounted as a file, never passed as an `--env`.
- The publish is bound to `127.0.0.1` explicitly, or to the tailnet address while sharing. The engine
  has no published port at all: the only way in is the gateway.

## Building argv safely — `read_argv`

`engine_argv` and `gateway_argv` run in a subshell and can fail halfway (a mount root that cannot be
made, a missing field). A process substitution would hand docker the truncated half. `read_argv` runs
the builder into a temp file, checks the builder's own status first, then reads the NUL-separated
words; `((${#ARGV[@]}))` guards an empty result.

## HTTP to a slot

```
api  <path> [secs]  curl -fsS --max-time ${2:-30} --max-filesize 1048576  -H @<auth file> http://127.0.0.1:$PORT/v1/<path>
post <path> <body>  curl -fsS --max-time 600 --max-filesize 4194304 -H 'Content-Type: application/json' -H @<auth file> -d <body> …
```

The bearer header travels as a **file** (`-H @file`, 0600), never as an argument: argv is readable by
every local account through `/proc/<pid>/cmdline` while the request runs. `auth_file` regenerates
`$STATE/gateway.auth` whenever the key changes.

## Lifecycle operations

| Function | Does |
|---|---|
| `start_pair` | `ensure_network`, then engine, then gateway; any failure returns non-zero |
| `start_gateway` | one slot's gateway only; used by share toggling |
| `restart_gateways` | rewrites `gateway.recipe.json` from every slot, then one privileged `restart_gateway` phase that removes and re-runs each slot's gateway with a fresh publish list — engines untouched. Waits up to 15 poll intervals for the first gateway to answer |
| `set_aside` | per victim: remove an older `-previous`, stop the running container, `docker rename <name> <name>-previous` |
| `restore_previous` | remove the new pair, `rename` + `start` every `-previous` back; non-zero if one could not be restored |
| `drop_previous` | remove every `*-previous` of ours — after a successful Start, or from a Start that died |
| `stop_slot` | that slot's engine, gateway, `-previous` and network; fails if a container survives |
| `stop_all` | every labelled container; fails if any survives |

`restore_previous` and `drop_previous` derive their container names from the **recipe file**, so a
phase acts on exactly what it was asked to act on — and in prompt mode that file's hash is pinned on
pkexec's own command line.

## What root re-checks

A prompt-mode phase does not trust the recipe file it is handed. Before any docker call, `phase_start`
runs:

1. `pinned_read` — the file must hash to the value on pkexec's argv (`reason <file> changed while the
   password prompt was open; nothing was run`);
2. `RUN_AS` must match `^[0-9]+:[0-9]+$`, else `reason internal: the user id did not reach the root phase`;
3. `gate_reason` again — `reason recipe refused: <why>`;
4. `slot_ok` — engine, gateway and network names must match `^<CTR>(-[a-z0-9-]+)?-(engine|gateway)$`
   and `^<NET>(-[a-z0-9-]+)?$`, the port must be 1024–65535, and every victim must be shaped the same.

Only then does it pull, set aside and start.

## Group operations

| Verb | Containers touched |
|---|---|
| `load`, same recipe | that recipe's pair is set aside, the new pair starts, the set-aside pair is dropped on success |
| `load`, different recipe on the same card | the other recipe's pair is a victim: set aside, restored on failure, dropped on success |
| `load`, different card | nothing — models on other cards keep running |
| `unload <recipe>` | that slot's pair and network |
| `unload` | everything labelled |
| `share` | every slot's **gateway** only, re-published with or without the tailnet address |
| `snapshot` | none, ever |