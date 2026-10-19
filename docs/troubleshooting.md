# Troubleshooting

For when Local AI shows an error. Find the message you see, then do what it says below.

The full log is in `~/.local/state/omarchy/local-ai/log`. `omarchy-local-ai log` opens it at the end.

## Setup

### "Local AI is not set up yet: choose Set up Local AI"
Click **Set up Local AI** in the panel. It is needed once per machine.

### "Docker is not running" or "Docker is not answering"
Start Docker: `sudo systemctl enable --now docker`. The panel clears the message by itself once Docker answers.

### "This login cannot use Docker's socket, though the account is in the docker group"
Log out and back in. If it stays, check that `docker info` works in a terminal.

### "Docker lists no NVIDIA GPU: set up Local AI, and check that nvidia-smi works"
Run `nvidia-smi` in a terminal. If it fails, the NVIDIA driver is not working: fix that first (after a driver
update, reboot). Then click **Set up Local AI** again.

### "NVIDIA container support is not ready" or "the NVIDIA device list is out of date"
This happens after a driver update or after adding or removing a card. Click **Set up Local AI** (or **Fix** on home).
It writes the device list again.

### A red banner about polkit files
An old Local AI (6.0-6.4) left files that give root without a password. See [legacy-polkit.md](legacy-polkit.md) to
remove them. The banner clears by itself.

## Finding a model

### "no tested model yet"
No recipe was accepted on your card yet. Check the [supported list](https://github.com/sybil-solutions/local-ai-registry/blob/main/supported/README.md).
To add your card, see the registry's [recipe bounties](https://github.com/sybil-solutions/local-ai-registry/issues?q=is%3Aissue+is%3Aopen+label%3Abounty).

### An AMD card is not found
Local AI finds AMD cards through ROCm's `amd-smi`. Install ROCm, then reopen the panel.

### A model is listed under "too big for this machine"
Its row says what is missing: GPU memory, free RAM, free disk under `~/.cache/omarchy/local-ai/models`, an NVMe
drive, or more cards. Free that up, or pick another model.

## Starting a model

### "Hugging Face did not list … (rate limit or no network): try again in a minute"
Wait a minute and press **Start** again. If it keeps happening, put a Hugging Face token in
`~/.cache/huggingface/token`; logged-in downloads have higher limits.

### Out of memory: messages like "CUDA out of memory", "Insufficient VRAM" or "Free memory on device"
Something else is using the GPU. Close games, other models and GPU-heavy browser tabs, then **Start** again. Check
with `nvidia-smi` what holds memory. If it still fails with nothing else running, report it (below): the recipe is
too tight for your card.

### "the engine keeps crashing" or "the engine printed nothing for 15 minutes"
Open the log and look at the last lines before the error. Most often it is memory (above). Otherwise report it.

### "the GPU driver reset the card while the model loaded"
The driver crashed, not Local AI. Reboot, then try again. If it repeats, report it with the kernel lines from the log.

### "the engine did not answer within 30 minutes"
The first start of a large model can be slow on a slow disk. Press **Start** again: the weights are already
downloaded. If it times out again, report it.

### "the gateway refuses this install's key"
Stop the model and start it again.

## Sharing

### Sharing says Tailscale's operator is someone else
Sharing needs your account as Tailscale's operator: `sudo tailscale set --operator=$USER`. Tailscale must be
running and logged in.

## Reporting a problem

Open an [issue](https://github.com/0xSero/omarchy-local-ai/issues) with:

- your card and the model you started,
- the message the panel showed,
- the last 50 lines of the log: `tail -n 50 ~/.local/state/omarchy/local-ai/log`.
