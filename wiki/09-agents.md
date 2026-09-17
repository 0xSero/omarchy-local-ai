# 9 — Agents

Agents are **launch-only**. The local model reaches an agent only when it is launched from the panel:
the endpoint, the key and the model travel in the launch command's environment and flags. Nothing you
own on disk is edited, so nothing has to be restored when the plugin stops — and an agent typed into a
terminal keeps its own provider.

## The agents

```bash
AGENTS=(pi omp opencode ori claude codex grok agy hermes copilot crush)
```

An agent is *installed* when `bin_of <name>` finds it (`$HOME/.local/bin/<name>`, else `PATH`).
The default is whatever `omarchy-default-agent` prints, else `pi`.

## Dialects and visibility

| Agent | Dialect it needs | Hidden when |
|---|---|---|
| `claude` | `messages` (Anthropic) | that dialect failed acceptance |
| `codex` | `responses` | that dialect failed acceptance |
| everything else | `chat` (OpenAI) | `chat` failed acceptance |

`chat` is always accepted when a model is ready, so an engine without the other two dialects still has
agents — the selector just does not offer `claude` or `codex`. Choosing one anyway is refused with
`<name> cannot use this model: its API dialect did not pass acceptance`.

## What each agent gets

Every agent is launched with `ENDPOINT=http://127.0.0.1:<the model's port>`, so an agent always talks
to the model it was launched for, never to "the" model.

| Agent | Endpoint | Key variable | Extra |
|---|---|---|---|
| `claude` | `ANTHROPIC_BASE_URL` | `ANTHROPIC_AUTH_TOKEN` | `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_{SONNET,OPUS,HAIKU}_MODEL` all set to the served model; `--model <m>` |
| `codex` | `-c model_providers.local.base_url=$ENDPOINT/v1` | `LOCAL_AI_KEY` | `-c model_providers.local.wire_api=responses`, `.env_key=LOCAL_AI_KEY`, `-c model_provider=local`, `-c model=<m>` |
| `opencode` | `OPENCODE_CONFIG_CONTENT` (inline JSON, provider `omarchy-local`, `@ai-sdk/openai-compatible`) | `OMARCHY_LOCAL_AI_KEY`, referenced as `{env:…}` inside the config | `--model omarchy-local/<m>` |
| `pi`, `omp` | `models.json` in a plugin-owned agent dir | written into that file | `PI_CODING_AGENT_DIR` / `OMP_CODING_AGENT_DIR`; `--provider omarchy-local --model <m>`. `omp` also gets a `config.yml` so it skips its first-run wizard |
| `crush` | `crush/crush.json` under `XDG_CONFIG_HOME` | written into that file | `XDG_DATA_HOME` moved too, because crush's data file pins the last chosen model over its config; a mise shim is resolved to the real binary so a mise reinstall cannot hijack it |
| `copilot` | `COPILOT_PROVIDER_BASE_URL=$ENDPOINT/v1` | `COPILOT_PROVIDER_API_KEY` | `--model <m>` |
| `grok` | custom model in plugin-owned `GROK_HOME/config.toml` | `XAI_API_KEY`, referenced by `env_key` | `--model omarchy-local`; served model and context come from the selected recipe |
| `hermes`, `ori`, `agy`, others | `OPENAI_BASE_URL` **and** `OPENAI_API_BASE` | `OPENAI_API_KEY` | `OPENAI_MODEL=<m>` |

Notes that are not cosmetic:

- **`claude` gets a bearer token, not an API key.** `ANTHROPIC_API_KEY` makes Claude Code ask "use
  this API key?" for every new key and *remember* a refusal; `ANTHROPIC_AUTH_TOKEN` is its documented
  form for gateways and is used as-is. The gateway accepts `Authorization: Bearer`.
- **`opencode` keeps the key out of its config text** by having the config reference `{env:…}`.
- **OMP uses PNG/JPEG for images.** Its `OMP_NO_WEBP=1` setting avoids WebP, which local llama.cpp image decoders cannot read.
- **OpenCode and Codex receive the selected context window.** OpenCode and Crush also receive the selected model's image support. The gateway preserves images in Chat, Messages and Responses requests, including Messages tool results.
- **Grok uses its custom-model configuration**, so a saved cloud model or OAuth token cannot override the local selection. Its private config leaves reasoning and sampling settings unset.
- **`pi`/`omp` get the recipe's real context and image support**, not a hardcoded 128K:
  `contextWindow` comes from the model's `ctxTokens`, and `input` becomes `["text","image"]` when the
  model passed vision acceptance. Costs are declared as zero, because they are.
- **`omp` leaves reasoning settings to the model's defaults.** Its generated config suppresses
  inferred reasoning parameters; it does not disable the model's reasoning. Both `models.json`
  and OMP's preferred `models.yml` are refreshed on launch so an earlier model cannot stay selected.
- The per-agent config files are 0600 and live under `$STATE/agents/`, never under your config.

## How the key stays out of `argv`

Agents that take a key from an environment variable are launched through a two-word bash stage:

```bash
bash -c 'k=$(cat "$1") || exit 1; shift; while [[ $1 != -- ]]; do export "$1=$k"; shift; done; shift; exec "$@"' \
     omarchy-local-ai-agent <$STATE/gateway.key> <VAR>… -- <the agent's own argv>
```

`/proc/<pid>/cmdline` therefore shows the *path of the key file* and the *variable names* — never the
key. Agents that take a key only from a file get a plugin-owned 0600 file instead. The suite asserts
both: the key is absent from the launch argv for `claude` and `codex`, and the environment is not
written to disk.

## Opening one

```
omarchy-local-ai open-agent [name] [recipe]
```

1. read the snapshot; a model is selected by `[recipe]`, else by the card's focused
   `running.recipeId`; it must exist and be `ready` (`load a model first`);
2. `name` defaults to the snapshot's `agents.default`, then `pi`;
3. `name` must be in that model's `launchable` list;
4. `ENDPOINT` is set to that model's port;
5. the argv is built (above), then `$STATE/agents/args/<name>` is appended if it exists;
6. with `OMARCHY_AI_FOREGROUND=1` it prints the command instead of launching it (this is how the suite
   inspects argv without spawning a terminal);
7. it `cd`s to `OMARCHY_AI_AGENT_DIR`, else the directory recorded by `agent-dir`, else wherever the
   shell was started;
8. it opens a terminal:

```
omarchy-launch-tui --app-id=org.omarchy.agent <argv>          (detached, its own session)
```

`omarchy-launch-tui` blocks for the terminal's whole life, so its exit is detached from the launch and
never reported as the agent's. It goes through uwsm's fast app daemon, which can wedge (*Timed out
waiting for pipes*, ten seconds per call), so a two-second `uwsm-app ping` decides between it and the
plain client:

```
uwsm app -- xdg-terminal-exec --app-id=org.omarchy.agent -e <argv>
```

If neither is available: `could not open a terminal for <name>: the uwsm app daemon is not answering`.
A launch that works clears an earlier refusal (`.error = ""`), because the panel's error state would
otherwise outlive the problem.

## Per-agent settings

| Verb | Effect |
|---|---|
| `agent-dir <path>` | records the canonical path agents open in; `agent-dir: not a directory: <path>` otherwise |
| `agent-args <name> [-- <flags>…]` | stores NUL-separated extra flags for one agent (a yolo mode, an allowed-tools list). With no flags the file is removed. The name is validated against `AGENTS` (`agent-args <agent> [-- flags...], one of: …`) |

These are the reason the demo videos can drive agents hands-free: `agent-args claude -- --permission-mode acceptEdits --allowedTools=Bash`,
`codex -- --dangerously-bypass-approvals-and-sandbox`, `opencode -- --auto`, `crush -- --yolo`,
`omp -- --auto-approve`, `copilot -- --allow-all`, `grok -- --always-approve`.

## What the plugin never does

It does not edit `~/.claude.json`, `~/.codex/`, `~/.config/opencode`, or any other agent config. It
does not install agents. It does not proxy an agent's traffic: the agent talks to the gateway
directly. It does not keep a session alive after Stop — a running agent loses its endpoint and its
own error message says so.
