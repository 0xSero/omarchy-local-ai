# 12 — CLI and environment reference

The card is the whole interface; every verb it uses exists on the command line, plus the settings.

```bash
omarchy-local-ai <verb> [args]
```

`bin/omarchy-local-ai` declares its surface to Omarchy in its header comments
(`omarchy:summary=`, `omarchy:args=`), which is what the bar's launcher and search read.

Before anything else it checks for `jq` and `curl`, and for a readable recipes file. A missing tool
prints `<missing tool: jq (sudo pacman -S jq)>` and, for `snapshot`, still prints a valid snapshot
whose `state` is `error` — the card must be able to say what is wrong even when nothing can run.

## Verbs

| Verb | Arguments | Does |
|---|---|---|
| `snapshot` | — | refresh the recipe file if the TTL has passed, derive `snapshot.json`, print it |
| `load` | — | start the selected recipe on the selected card, downloading if needed |
| `run` | `<recipe> [<backend:index>]` | pin the recipe and the card, then start — one process, one snapshot, as the card's run row does |
| `unload` | `[<recipe>]` | stop one model, or all of them; during a download it stops the download instead |
| `open-agent` | `[<name>] [<recipe>]` | open an installed agent on a running model |
| `share` | `[--key <value>\|-]` | toggle tailnet sharing, or replace the key (`-` reads stdin) |
| `gpu` | `[auto\|<backend:index>]` | which detected card to use; prints the `gpus` array |
| `recipe` | `[auto\|<id>]` | which validated recipe of that card to run; prints the `recipes` array |
| `recipes` | `[update]` | which recipe file is in use; `update` fetches a newer one now |
| `agent-dir` | `<path>` | the directory agents open in |
| `agent-args` | `<name> [-- <flags>…]` | extra flags for one agent; none to clear |
| `help`, `-h`, `--help` | — | usage |

Internal (never typed by hand, but documented because the tests use them):

| Verb | Meaning |
|---|---|
| `_worker-load`, `_worker-unload [<recipe>]` | the worker bodies; the verbs above spawn these |
| `_root <env-file> <sha256> <phase> [args]` | the root side of one privileged action; refuses unless it is root (or `OMARCHY_AI_TEST_ROOT`) and reached through pkexec |

### Exact refusals

| Verb | Condition | Message |
|---|---|---|
| any | `jq`/`curl` missing | `missing tool: jq (sudo pacman -S jq)` |
| any | recipes file missing/broken | `recipes.json is missing or broken: reinstall the plugin` |
| `load`, `run` | a worker is alive | `another operation is running` |
| `run` | bad recipe id | `run <recipe> [gpu], as listed in the snapshot` |
| `run` | bad card key | `run <recipe> [backend:index]` |
| `unload <id>` | no such slot | `no model <id> is running` |
| `unload` while an op other than `download` runs | — | `another operation is running` |
| `unload` during a download behind a prompt | — | `the download runs behind the password prompt and cannot be stopped from here` |
| `open-agent` | no ready model | `load a model first` |
| `open-agent <name>` | dialect not accepted | `<name> cannot use this model: its API dialect did not pass acceptance` |
| `open-agent <name>` | agent not installed | `<name> is not installed` |
| `share` | see [10 — Sharing](10-sharing.md) | under the toggle, not in the ledger |
| `gpu <key>` | malformed | `gpu <backend:index>, as listed in the snapshot` |
| `recipe <id>` | unknown id | `recipe <id>, as listed in the snapshot` |
| `recipes <other>` | — | `recipes [update]` |
| `agent-args <name>` | unknown agent | `agent-args <agent> [-- flags...], one of: ${AGENTS[*]}` |
| `agent-dir <path>` | not a directory | `agent-dir: not a directory: <path>` |
| `_root` | not root, or not pkexec | `_root is for pkexec` / `this must run through pkexec` |

Two refusal styles exist on purpose:

- **`fail`** — stderr only. For verbs whose caller is a person in a terminal.
- **`refuse`** — stderr **and** `.error` in the ledger **and** a snapshot, because the panel never sees
  a child's stderr. It never touches `.op`, since a refusal can race a live worker whose op record is
  authoritative.

## Environment variables

Every variable below is read by the plugin. `HOME_DIR` is `OMARCHY_AI_USER_HOME`, else `$HOME`; under a
root phase it is the home of the uid pkexec reports.

| Variable | Default | Meaning |
|---|---|---|
| `OMARCHY_AI_STATE` | `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/local-ai` | the state directory |
| `OMARCHY_AI_MODEL_ROOT` | `$HOME/.cache/omarchy/local-ai/models` | the models root recipes mount as `${MODEL_ROOT}` |
| `OMARCHY_AI_CACHE_ROOT` | `$HOME/.cache/omarchy/local-ai/cache` | the second permitted mount root |
| `OMARCHY_AI_HF_HOME` | `$HOME/.cache/huggingface` | the HF cache recipes may mount, and where hub-layout downloads land |
| `OMARCHY_AI_USER_HOME` | `$HOME` | the home every derived path is built from |
| `OMARCHY_AI_PORT` | `12434` | the first gateway port |
| `OMARCHY_AI_POLL` | `2` | seconds between progress samples and acceptance retries |
| `OMARCHY_AI_TIMEOUT` | `3600` | seconds the engine has to answer before acceptance gives up |
| `OMARCHY_AI_NETWORK` | `omarchy-local-ai` | the network name prefix |
| `OMARCHY_AI_CONTAINER` | `omarchy-local-ai` | the container name prefix |
| `OMARCHY_AI_GPU` | — | pin a card (`backend:index`), like `$STATE/gpu` |
| `OMARCHY_AI_RECIPE` | — | pin a recipe id, like `$STATE/recipe-pick` |
| `OMARCHY_AI_RECIPES` | — | use exactly this recipes file; disables fetching |
| `OMARCHY_AI_RECIPES_URL` | the registry raw URL | where to fetch; empty disables fetching |
| `OMARCHY_AI_RECIPES_TTL` | `21600` | seconds between background refresh attempts |
| `OMARCHY_AI_DOCKER` | auto | `direct` or `prompt`, overriding socket detection |
| `OMARCHY_AI_RUN_AS` | `$(id -u):$(id -g)` | the uid:gid the gateway and downloader run as |
| `OMARCHY_AI_WEIGHTS_PATHS` | — | colon-separated extra roots to search for weights you already have |
| `OMARCHY_AI_NO_HOST_HF` | — | set: never use the host `hf`, always download inside the image |
| `OMARCHY_AI_HARDWARE_JSON` | — | replace GPU detection with this JSON |
| `OMARCHY_AI_DRI_PATH` | `/dev/dri/by-path` | where the Intel render-node symlinks live |
| `OMARCHY_AI_AGENT_DIR` | `$STATE/agent-dir`, else the shell's directory | where an agent opens |
| `OMARCHY_AI_FOREGROUND` | `0` | set: run the worker in the foreground, and make `open-agent` print its command instead of launching |
| `OMARCHY_DOCKER_SOCKET` | `/var/run/docker.sock` | the socket whose writability decides direct vs prompt |
| `HF_TOKEN` | — | passed to the Hub tree listing and to the in-container downloader; never logged |
| `http_proxy`, `https_proxy`, `no_proxy` (and uppercase) | — | forwarded into root phases, so a gated download still works behind the prompt |

`OMARCHY_AI_ROOT_PHASE` is set by `_root` itself and is not meant to be set by hand; it changes
`log` to write to stderr (root may not create files in the user's state).

## Exit codes and output

- Verbs that print state (`snapshot`, `gpu`, `recipe`, `recipes`) print one line of JSON.
- `snapshot` prints the whole snapshot; `gpu` prints `.gpus`; `recipe` prints `.recipes`; `recipes`
  prints `{source, file, registryCommit, generatedAt, hardware, recipes}`.
- A refusal exits non-zero and prints `local-ai: <reason>` on stderr.
- `open-agent` in foreground mode prints a shell-quoted command instead of launching.

## Examples

```bash
omarchy-local-ai snapshot | jq -r '.state, .reason, .running.name'
omarchy-local-ai run qwen38-awq-int4-rtx3090-vllm-tp2 nvidia:0
omarchy-local-ai recipes update
omarchy-local-ai recipes | jq -r '.source, .registryCommit[0:12]'
omarchy-local-ai agent-args codex -- --dangerously-bypass-approvals-and-sandbox
omarchy-local-ai agent-dir ~/work/project
omarchy-local-ai open-agent codex
omarchy-local-ai share --key - < ~/my-key.txt
```