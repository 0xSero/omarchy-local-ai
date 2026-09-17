# 4 — State: the ledger and the snapshot

Two files, two roles. The **ledger** is the only authoritative state — everything the plugin knows
because it did it. The **snapshot** is derived: a pure function of the ledger, reality, and
`recipes.json`, rewritten wholesale on every `snapshot` verb so the panel can watch one file.

## The ledger — `$STATE/ledger.json` (`omarchy-local-ai/ledger/2`)

```json
{
  "schemaVersion": "omarchy-local-ai/ledger/2",
  "op": { "name": "download", "recipeId": "qwen38-…", "pid": 12345,
          "startedAt": "2026-09-16T12:04:00Z", "detail": "3 / 18 GB", "percent": 16 },
  "error": "",
  "slots": {
    "qwen38-…": {
      "port": 12434, "net": "omarchy-local-ai-qwen38-…",
      "engine": "omarchy-local-ai-qwen38-…-engine",
      "gateway": "omarchy-local-ai-qwen38-…-gateway",
      "keys": ["nvidia:0"], "name": "Qwen3.8 27B", "startedAt": "…",
      "accepted": { "servedModel": "…", "registry": "<sha40>", "apis": ["chat","messages","responses"],
                    "tps": 61, "prefillTps": 812, "contextTokens": 262144, "at": "…" }
    }
  },
  "lastStartSeconds": 94
}
```

| Field | Meaning |
|---|---|
| `.op.name` | `""` (idle), `download`, `starting`, `unload`, `share` |
| `.op.pid` | the worker's pid. **Busy is derived from this pid being alive**, never from a string |
| `.op.detail` / `.op.percent` | what the card shows for the running step |
| `.op.startedAt` | preserved across `op` calls with the same name, so elapsed time survives step changes |
| `.error` | the last refusal, one sentence. Cleared by `op` and `op_done` |
| `.slots` | every running model, keyed by recipe id |
| `.slots[].accepted` | `null` until acceptance passed; its presence is what makes a model *ready* |
| `.lastStartSeconds` | how long the last successful Start took; the next Start's progress bar |

There is deliberately **no derived data** in the ledger. A ledger written before 4.1 carried the
gateway key in `.share.key`; every `snapshot_write` deletes it (`del(.share)`) wherever it is met.

### Who writes it

`lwrite <jq-filter> [args]` is the only writer: an atomic read-modify-write under a short file lock
(`flock 9` on `$STATE/ledger.lock`, or a `mkdir` lock with a 30-second ceiling where flock is absent),
writing to `ledger.json.tmp.$$` and `mv`-ing it into place.

| Call | Effect |
|---|---|
| `op <name> <recipeId> <detail> <percent>` | set `.op` from **this process's** pid, clear `.error`, log, snapshot |
| `op_pending <name> <pid> [recipeId]` | the parent records the worker it just spawned, so the very next snapshot is busy. Compare-and-swap: it never overwrites a worker that already wrote. Then it waits 0.2 s and, if the pid is gone, clears the record and leaves the worker's own refusal standing (no phantom op) |
| `op_done` | clear `.op`, clear `.error` |
| `oops <reason>` | log, set `.error`, clear `.op`, snapshot, `exit 1` — a worker's failure exit |
| `refuse <reason>` | for panel-invoked verbs: log, set `.error`, snapshot, return non-zero. **Never touches `.op`**, because a refusal can race a live worker whose op record is authoritative |

### The lock

`guard` takes the op lock: `exec 8>"$STATE/op.lock"; flock -n 8` — non-blocking, so a second
operation is refused immediately with `another operation is running`. Without flock it creates
`$STATE/op.lockd` containing the pid, and treats a lock directory whose pid is dead as stale.

The worker keeps fd 8 for its whole life. Every child is spawned through `run_child`/`spawn_child`,
which close fds 8 and 9, so nothing a worker starts can outlive it holding the lock. `lock_wait`
lets a *verb* wait up to 5 s for a finishing worker to release the lock, so a click right after a
Start does not fail with `another operation is running` while the worker writes its last snapshot.

### Workers that die without a word

`worker_exit` (the `EXIT` trap of every worker) covers the unforeseen: if the worker exits while the
ledger still names it as the running op, it writes
`stopped unexpectedly while <detail> (see $LOGFILE)` and clears `.op`. If `$STATE/cancel` exists the
worker was asked to stop; the canceller writes the outcome instead.

`snapshot_write` has a second net for a worker killed too hard to run its trap: if `.op.pid` is dead
and no worker is busy, it logs `worker <pid> vanished during <name>` and reports
`stopped unexpectedly while <detail>; press Start again (see $LOGFILE)`.

## The snapshot — `$STATE/snapshot.json` (`omarchy-local-ai/snapshot/10`)

Written by `snapshot_write` (`lib/snapshot.sh`) with `mv` from a temp file. Top level:

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | string | `omarchy-local-ai/snapshot/10` |
| `updatedAt` | ISO-8601 UTC | when this snapshot was derived |
| `state` | `uninitialized` \| `idle` \| `download` \| `starting` \| `unload` \| `share` \| `ready` \| `error` | see the state rule below |
| `error` | string | the ledger's error, else the focused model's `note` |
| `operation` | `{name, recipeId, detail, percent, startedAt, expectedSeconds}` | `expectedSeconds` is `lastStartSeconds` while `name == "starting"`, else 0 |
| `hardwareId` | string | the matched hardware id, or `""` |
| `gpus` | array | every detected card: `{key, backend, index, product, vramGb, hardwareId, chosen, tempC, utilPct, usedGb}` |
| `registry` | string | the `registryCommit` of the file in use |
| `registryFile` | `{source, generatedAt, checkedAt, refresh}` | `source` is `vendored` or `live`; `checkedAt` is the unix time of the last refresh attempt; `refresh` is false when fetching is off |
| `reason` | string | why there is no model to start: a gate refusal, the hardware reason, a short card claim, or a foreign listener on the port. Empty when fine |
| `running` | `null` \| `{recipeId, name, cards, port, state}` | the model the card looks at |
| `models` | array | every running slot (see below) |
| `apis` | `["chat", "messages", "responses"]` | the focused model's accepted dialects |
| `agents` | `{default, installed[], launchable[]}` | `default` from `omarchy-default-agent` (fallback `pi`); `launchable` is installed ∩ the model's dialects |
| `share` | `{available, active, url, keyFile, error}` | never the key itself |
| `cards` | array | detected card **types**: `{hardwareId, backend, product, name, vramGb, count, totalGb, keys[], chosen, recipe, claimed, idle}` |
| `recipes` | array | every offered recipe of every detected card type: `{id, name, engine, sizeGb, precision, ctxTokens, kvTokens, caps, onDisk, partialBytes, hardwareId, cards, claims, recommended, running}` |
| `selected` | `null` \| `{recipeId, name, hardwareId, cards, claims, indexes, keys, onDisk, partialBytes, sizeGb, running}` | the recipe the card would start, with the exact device indexes and keys it would claim |
| `port` | `{number, busy, listener}` | `listener` is `none`, `gateway` or `other` |

### `models[]` — one entry per running slot

| Field | Meaning |
|---|---|
| `recipeId`, `name`, `port`, `endpoint` | identity; `endpoint` is `http://127.0.0.1:<port>/v1` |
| `keys[]`, `cards` | the device keys it holds, and how many |
| `state` | `ready`, `error`, `stopped`, or the running op's name while it is busy |
| `note` | the sentence beside a non-ready state (see the rules below) |
| `servedModel` | what the gateway answers with now, else the accepted one |
| `apis`, `caps` | accepted dialects; `{chat, vision, video, tools, reasoning}` from the slot's recipe |
| `ctxTokens`, `kvTokens`, `decodeTps`, `prefillTps`, `acceptedAt`, `startedAt` | from the acceptance record and the slot record |
| `tokensToday` | completion tokens this model served through its gateway in the last 24 h, from `usage.jsonl` |
| `launchable` | agents that can use this model's dialects |
| `shareUrl` | the tailnet URL when sharing is active, else `""` |
| `engine`, `gateway` | container names (used by the log and by hand) |

### How a model's state is decided (`models_json`)

In order, first match wins:

| Condition | State | `note` |
|---|---|---|
| this slot is the recipe of the running op | the op's name (`download`/`starting`/`unload`/`share`) | — |
| the gateway answers **and** the slot has an acceptance record | `ready` | — |
| the gateway answers, no acceptance record | `error` | `never verified; press Start` |
| the engine container runs, the gateway does not answer | `error` | `the gateway is not answering; press Start or Stop` |
| another op is busy (this slot was set aside) | `stopped` | — |
| otherwise | `stopped` | `stopped outside the plugin; press Start or Stop` |

In direct-docker mode the engine's container state is checked too (`live`); in prompt mode docker
would prompt, so a gateway that answers *is* the evidence, and no docker call is made.

### The state rule for the whole card

```
busy (op pid alive)                → the op's name
else any model ready               → ready
else ledger .error is non-empty    → error
else any model in error            → error  (+ that model's note)
else                               → idle
```

`error` and `reason` differ on purpose: `reason` is *why there is nothing to start* (a durable
property of the hardware or the file), `error` is *what the last action said*.

### Housekeeping `snapshot_write` performs

- scrubs `.share` out of any ledger that still has it, then re-reads;
- if `.op.pid` is dead and not busy, records the vanished worker (once) and re-reads;
- **direct-docker mode only, and never while busy**: a slot whose engine, gateway and engine-previous
  containers are all gone (the user removed them by hand, or docker was pruned) is forgotten, and its
  `<id>.json` removed. Then re-reads.

Everything else it does is read-only: no container is started, stopped or renamed by a snapshot.

### `port_listener`

`ss -Hltn "( sport = :$PORT )"` decides whether anything is listening; without `ss`, a connect probe
(exit 7 = connection refused means free). A listener is classified by probing `GET /v1/models`
**without** a key: HTTP 401 with body
`{"error":{"type":"authentication_error","message":"invalid or missing API key"}}` is `gateway`
(ours); anything else that answers is `other`, which becomes the snapshot's `reason`
(`port <n> is in use by something else`) and the panel's *port busy*.
