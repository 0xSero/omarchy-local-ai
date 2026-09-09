<p align="center">
  <img src="media/logo-256.png" width="128" height="128" alt="Local AI">
</p>

<h1 align="center">Local AI for Omarchy</h1>

<p align="center">
  The model validated for your GPU, one button on the bar.<br>
  Start serves it, any coding agent opens on it, one click shares it on your tailnet.
</p>

<p align="center">
  <a href="https://omarchyplugins.com/plugin.html?id=sero.local-ai">Marketplace listing</a> ·
  <a href="media/features.mp4">Every feature, 4 min</a> ·
  <a href="media/demo.mp4">Eight agents on one model, 6 min</a>
</p>

![Local AI](preview.png)

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai.git --enable
```

Click the new bar icon and press **Start**. The card shows the model chosen
for your GPU and its download size before anything lands on disk. The first
Start downloads the weights and pulls the engine image; later Starts take
seconds to a couple of minutes, depending on the card. When the card says
**ready**, the model has passed every check below, and **Open agent** starts
any installed coding agent on it.

### Requirements

- Docker, with your user in the `docker` group
- An NVIDIA GPU with the NVIDIA container toolkit, an Intel Arc Pro B70, or an AMD GPU with the AMD container toolkit
- `jq`, `curl`, `flock`
- Optional: `tailscale` for sharing; `hf` for faster downloads

The listing is marked *manual setup* because of Docker and the container
toolkit. Nothing else needs configuring: no model to pick, no config file to
write, no API key to make.

## What you get

- **One validated model per card.** 34 GPU recipes, from a 2.6B model on
  8 GB cards to a 27B on 32 GB and up, each validated on that exact card and
  vendored with its image digest and model revision.
- **Every GPU you have, listed.** One card is a line; more than one is a
  picker. The largest card with a recipe is the default; pick another and
  Start puts its model there.
- **Any coding agent, one click.** pi, omp, opencode, ori, claude, codex,
  grok, agy, hermes, copilot, crush open on the running model with the
  endpoint and key in their own environment. No config file of yours is
  touched.
- **Share on Tailscale.** The same endpoint, keyed, on your tailnet address.
  One click, no `tailscale serve`, no root, no password.
- **Refusals out loud.** Anything the plugin cannot do is a sentence on the
  card, never a dead button: no supported GPU, a recipe that fails the gate,
  an engine that will not start, an agent whose dialect did not pass.

## Commands

The card is the whole interface; the same verbs exist on the command line.

```
omarchy-local-ai snapshot                    refresh and print the state the card renders
omarchy-local-ai load                        download if needed, then start
omarchy-local-ai unload                      stop; keep downloads
omarchy-local-ai open-agent [name]           open an agent on the running model
omarchy-local-ai share [--key <value>]       toggle tailnet sharing, or replace the key
omarchy-local-ai gpu [auto|<backend:index>]  which detected card to use
omarchy-local-ai agent-dir <path>            the directory agents open in
omarchy-local-ai agent-args <name> [-- …]    extra flags for one agent (none clears)
```

State lives in `~/.local/state/omarchy/local-ai/` (0700; `log` records every
step and every container command). Weights go to `~/.cache/omarchy/local-ai/`
or the shared Hugging Face cache, whichever the recipe mounts.

## Remove

```bash
omarchy-local-ai unload            # stops the model, keeps downloads
omarchy plugin remove sero.local-ai
rm -rf ~/.cache/omarchy/local-ai   # optional: the downloaded weights
rm -rf ~/.local/state/omarchy/local-ai
```

## How it works

**Recipes** come from the [local-ai registry](https://github.com/0xSero/local-ai-registry)
export in `recipes.json`, one per hardware id. A recipe names a digest-pinned
engine image, a model pinned by revision, its mounts, arguments, serving
limits, and the validation record from the card it was proven on.

**The gate** refuses, before anything starts, any recipe that is not
digest-pinned, asks for host IPC, extra capabilities, or a weakened security
profile, or mounts a path outside the plugin's two cache roots. Mount paths
are canonicalized, so a symlink out of the root is refused too.

**Two containers**, both labeled and owned by the plugin, on a private bridge
network: the engine (TabbyAPI, SGLang, vLLM, or llama.cpp), never reachable
from the host, and the
[gateway](https://github.com/0xSero/local-ai-images) on `127.0.0.1:12434`,
which serves OpenAI chat, Anthropic Messages, and OpenAI Responses so every
agent talks to one endpoint, and requires a key on every request.

**Acceptance** decides "ready": the served model matches the recipe, an
unkeyed request is refused, a chat reply comes back, decode speed is not a
CPU fallback, the Messages and Responses dialects answer in the shapes agents
really send, a tool call with a Claude-style schema works, and a reasoning
model's thinking is split from its answer. Any failure rolls back to the
previous model with the reason on the card.

**The key** is generated on first Start into
`~/.local/state/omarchy/local-ai/gateway.key` (0600) and lives only there:
not in the ledger, the snapshot, the log, or any process argument. Agents
receive it through a launch stage that reads the file; the plugin's own
probes hand curl a header file. `share --key <value>` replaces it in place.

## How we know it works

- 29 NVIDIA recipes ran the plugin's own Start path on rented cards, RTX 3060
  through RTX 6000 Ada; per-card logs are in [`test/rented-results/`](test/rented-results/).
- The Intel Arc Pro B70 recipe runs daily on a mixed RTX 3090 + B70 host,
  where both videos were recorded.
- 87 shimmed tests cover the gate, download, start, acceptance, rollback,
  agents, sharing, and the key handling, without a GPU: `bash test/all`.
- The marketplace listing passed validation and the automated security
  baseline and went through five rounds of security review.

## Development

```bash
bash test/all                          # isolated state, shimmed docker/curl/tailscale; no GPU needed
make sync REGISTRY=../local-ai-registry  # regenerate recipes.json from a registry checkout
python3 test/rented.py --list            # the rented-GPU harness (see the file's header)
```

`recipes.json` carries the registry commit it was exported from; CI fails if
the file and the commit disagree. The recordings and how they were made are
in [`demo/`](demo/README.md).

## License

MIT. Container images are pinned by digest and documented in
`recipes.json`; self-built images carry a build attestation you can verify
with `gh attestation verify`.
