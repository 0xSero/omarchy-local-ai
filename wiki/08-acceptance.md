# 8 — Acceptance

`accept <recipe>` (`lib/runtime.sh`) is the reason **ready** means something. It runs after both
containers are up and before the model is announced. Every probe goes through the slot's own gateway
on `http://127.0.0.1:<slot port>` with the key, so it tests the same path an agent will use.

Nothing here is a smoke test. Each check exists because something passed every other check and was
still wrong in front of a user.

## The probes, in order

| # | Probe | Request | Passes when | Card detail |
|---|---|---|---|---|
| 1 | engine answers | `GET /v1/models` every `POLL` s until the deadline | an `id` is present | `loading the model` |
| 2 | right model | the same | `data[0].id == model.servedName`, or that name's last path segment is contained in it (a GGUF recipe serves a path) | — |
| 3 | context | the same | `max_model_len` (or `meta.n_ctx`) is 0, or ≥ `serving.ctxTokens` | — |
| 4 | key enforced | an **unkeyed** `GET /v1/models` | must **fail** | — |
| 5 | chat | `POST /v1/chat/completions`, "Reply with exactly: LOCAL_AI_READY" | `content` or `reasoning_content` contains `LOCAL_AI_READY` | `chat acceptance` |
| 6 | decode speed | two runs of "Count from 1 to 80 separated by single spaces. Write nothing else." (`max_tokens: 160`), the better kept | see below | `speed check` |
| 7 | reasoning leak | the probe-6 reply | `content` must not match `</think>` or `<|end_of_thought|>` | — |
| 8 | prefill speed | one ~5 KB prompt with a one-word answer, whole time minus the decode share | recorded, never gated | `prefill check` |
| 9 | Messages dialect | `POST /v1/messages`: system prompt, a prior user/assistant turn, then the readiness request | a text block contains `LOCAL_AI_READY` | `messages acceptance` |
| 10 | Responses dialect | `POST /v1/responses`: `instructions` plus a `developer` item **after** the user item | output text contains `LOCAL_AI_READY` | `responses acceptance` |
| 11 | tools | `POST /v1/chat/completions` with a `shell` tool, when `capabilities.tools` | a `tool_calls[]` entry named `shell` whose arguments contain `LOCAL_AI_TOOL_OK` | `tool-call acceptance` |
| 12 | vision | an inline base64 PNG (`data:image/png;base64,…`, embedded in `lib/runtime.sh`) as an `image_url`, when `capabilities.vision` | the answer matches `\bred\b` | `vision acceptance` |
| 13 | video | an inline base64 MP4 (also embedded in `lib/runtime.sh`) as a `video_url`, when `capabilities.video` | the answer matches `\bred\b` | `video acceptance` |

Probes 9–13 are **additive**: a dialect that fails is simply absent from the accepted `apis` list, so
the agents that speak it are hidden and the model stays usable for the rest. A capability the recipe
marks `false` is skipped entirely; a capability the recipe does not mention stays *unknown* on the
card (`reasoning ?`) rather than being claimed.

Probes 9 and 10 use the shapes agents really send — a template that refuses a late system message
fails here rather than inside an agent.

## Why each exists

**Right model (2).** An engine serving the wrong quant, or resolving a different file inside the
mount, would otherwise be reported as success.

**Context (3).** A recipe advertising 262,144 tokens that the runtime silently truncates to 131,072 is
a data-loss bug that only surfaces in a long agent session. This probe is why the plugin refuses to
retry launches at a smaller context: the advertised context is a promise, and the alternative
(`fit_length`) was dropped in 5.0 for exactly that reason.

**Key enforced (4).** A gateway that cannot read its key file serves **keyless without a word**.
Sharing that on a tailnet is the one thing this plugin must never do, so an unkeyed request must fail.

**Decode speed (6).** The founding finding of the project: a host whose driver cannot initialise the
image's CUDA serves from the CPU at under 1 tok/s while every health check passes. Details:

- two runs, the **better** counts — the first is cold;
- tokens come from `usage.completion_tokens` when the engine reports it, otherwise from the words
  written (thinking included) at 1.3 tokens per word, because TabbyAPI reports no usage;
- the floor is `max(3, floor(recipe.speed.tps / 10))` — a tenth of the validated speed, never below 3;
- skipped when fewer than 16 tokens came back, so a short answer cannot fail a fast engine;
- the failure names the cause: `decode <n> tok/s is below the <f> tok/s floor: the GPU is not being
  used (driver too old for this image?)`.

It is deliberately coarse: it exists to catch a CPU fallback, not to benchmark.

**Reasoning leak (7).** A reasoning model whose engine is not splitting on the think tags puts the
closing tag into the answer text, and every agent then renders the model's thinking as its reply — a
real tester's finding on TabbyAPI. The engine's reasoning parser must be on for such models.

**Tools (11).** The schema carries a regex `pattern` with an escape and a `format` hint, exactly as
Claude Code's tools do. llama.cpp's grammar cannot take them, so the gateway must scrub them; the
failure surfaces here instead of inside an agent.

**Vision and video (12, 13).** The fixtures are two tiny red payloads embedded in `lib/runtime.sh`
as base64 data URLs, not files: a readiness check that needs no loose media in the installation, no
encoder and no network. The check is specific — a model that answers "red" for a red frame is reading
the pixels — and the request sets `chat_template_kwargs.enable_thinking: false`, so a reasoning model
cannot spend its 64 tokens thinking.

## What acceptance records

```json
"accepted": { "servedModel": "…", "registry": "<sha40>", "apis": ["chat","messages","responses"],
              "tps": 61, "prefillTps": 812, "contextTokens": 262144, "at": "…" }
```

written to `.slots[<id>].accepted` and logged as
`accepted <id> served=<name> port=<n> tps=<n> prefill=<n> apis=<csv>`.

Its **presence** is what makes a model `ready` in the snapshot. A model whose gateway answers but has
no acceptance record is reported as *never verified; press Start* — which closes the window where a
worker dies between "the gateway answers" and "the model is correct".

## Engine health between probes

`engine_alive` runs before each `/v1/models` retry, in direct mode. Under `--restart unless-stopped`,
docker keeps a container that exits immediately *running* (`State.Running` stays true while it
restarts), so a broken engine would otherwise sit out the whole acceptance timeout — an hour by
default — showing `loading the model`. Instead:

- not running → `engine exited during startup (docker logs <name>)`;
- `State.Restarting` true, or `RestartCount ≥ 2` → `engine keeps crashing: <last log line> (docker logs <name>)`.

`engine_last_line` takes the last 40 log lines, drops blanks, drops Python traceback noise
(`File "`, `^^^^`, `Traceback`, `return `, `raise `, a bare call), and truncates to 140 characters —
so the card carries the engine's own words, not a stack.

Behind a password prompt there is no docker to ask, so the deadline decides instead.

## Usage accounting

Every request the plugin itself makes through a gateway appends a line to `$STATE/usage.jsonl`:

```json
{"t":1758000000,"prompt":42,"completion":12,"recipe":"qwen38-…"}
```

`tokensToday` on the card is the sum of `completion` for that recipe over the last 24 hours. This is
the plugin's own traffic only: what an agent does through the gateway is not counted, because the
gateway does not report back to the plugin.