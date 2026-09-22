# Local AI for Omarchy

The model validated for your GPU, one click, and every coding agent on it.

One bar mark. Click it: the card names your GPU and the recipe the registry validated on that exact card.
Load it: the weights are fetched and verified, the engine starts in a container on a private network, a
keyed gateway answers on loopback, one real completion is checked, and the card says ready. Open any
installed coding agent on it, in your project folder, with nothing written to your own config.

![the card](preview.png)

## Install

```bash
omarchy plugin add https://github.com/0xSero/omarchy-local-ai
```

Then click the mark. On an NVIDIA card the first load installs the NVIDIA container toolkit behind one
password prompt; Docker itself is part of Omarchy. Nothing else is needed.

Omarchy keeps you out of the docker group on purpose, so every Start and Stop is one polkit prompt. If
you turned on sudoless Docker (Setup › Security), there is no prompt.

## What runs

- **Recipes** come from [the registry](https://github.com/0xSero/local-ai-registry), where each one was
  validated on the exact card it names. The plugin vendors that export in `recipes.json`; a recipe can only
  say what the launcher will run: an image pinned by digest, weights pinned by revision, the engine's
  arguments, environment, port and shm. Mounts, devices, capabilities and network mode are not in the file.
- **Weights** are downloaded as you, over https, from the pinned revision, and every file is checked against
  the Hub's tree before it is mounted. A verified copy already on the machine is adopted instead.
- **Containers**: the engine on its own bridge network with no published port, and the attested gateway on
  `127.0.0.1:12434`, running as your user, requiring a bearer key that lives in one 0600 file.
- **Acceptance**: the model must be the one the recipe names, answer one real request at a speed that is not
  a CPU fallback, and answer the dialects agents use. A start that fails is rolled back to the previous run.
- **Agents**: claude, codex, pi, omp, opencode, crush, grok, copilot, hermes, ori, agy, muse and cursor open
  in a terminal with the endpoint and the key in their environment, or in a config directory the plugin
  owns. No file of yours is read or written.

## Using it from a shell

```bash
omarchy-local-ai snapshot                 # the state the card renders, as JSON
omarchy-local-ai load <recipe-id> [gpu…]  # download if needed, then start; e.g. load qwen3827b-exl3-4bpw-rtx4090-tabbyapi-tp1
omarchy-local-ai unload [recipe-id]       # stop one model, or every model
omarchy-local-ai agent claude             # open an agent on the running model
omarchy-local-ai agent-dir ~/code/thing   # the folder agents open in
```

The endpoint is OpenAI-compatible at `http://127.0.0.1:12434/v1` (Messages and Responses too, when the
model passed them); the key is in `~/.local/state/omarchy/local-ai/gateway.key`.

## Uninstall

`bin/omarchy-remove-ai-local` stops everything and deletes the containers, images, weights and state.
Then `omarchy plugin remove sero.local-ai`.

## Layout

`bin/omarchy-local-ai` is the whole backend, one bash file. `Panel.qml`, `CardRow.qml` and `Model.js` are
the card. `recipes.json` is the data. `test/all` runs the shell tests (docker, curl, the GPU tools and
pkexec are shimmed, so they run anywhere; `Model.js` is tested under node). `docs/design.md` is the design.
