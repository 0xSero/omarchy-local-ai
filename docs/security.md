# Security

What setup changes on your machine, how a running model is isolated, and how its key is kept.

## Setup

**Set up Local AI** opens a terminal opens and runs two of Omarchy's own commands; Local AI itself runs nothing as root, and adding or updating the plugin never runs setup.

- `omarchy-setup-security-sudoless-docker`, Omarchy's Sudoless Docker: it explains what that means, asks you to confirm, then asks "Password for *you* to turn on Sudoless Docker for Local AI". This login reaches Docker through the new group at once, so Local AI needs no logout or reboot (Omarchy may still suggest one at its next update).
- NVIDIA only: `omarchy-pkg-add nvidia-container-toolkit`, asking "Password for *you* to install NVIDIA container support for Local AI"; already installed, it asks nothing. The package describes your GPUs to Docker in `/etc/cdi/nvidia.yaml`, which Docker reads when a model starts, so Docker's configuration is untouched and it is not restarted.

If Local AI 6.0-6.4 was ever set up on this machine, by any account, it left two polkit files for that account that let its programs get root without a password. Local AI stops while any are there: the panel shows a red banner, and starting, sharing and setup refuse. Only root can delete them, so Local AI does not; [legacy-polkit.md](legacy-polkit.md) says what they are and gives the commands to run in a terminal. The banner clears by itself once they are gone.

Setup ends by checking what the panel will show. Sharing a model on your tailnet needs you as Tailscale's operator; Omarchy's Tailscale install sets that, and setup tells you when it is not. After setup, starting, stopping, sharing, refreshing and removing never ask for a password. Sudoless Docker is root-equivalent, as Omarchy's own warning says; turn it off in Setup > Security.

## Containers

Each engine is on its own internal Docker network, isolated from the host
(`com.docker.network.bridge.gateway_mode_ipv4=isolated`, Docker 28 and later):
the host has no address on it and no route to it, so no account on the machine
can reach the engine, whatever it listens on or whether it checks a key of its
own. Only the model's gateway joins that network; it is the one way in, and it
requires the key. A model an older version started is moved to its private
network while it runs, the first time the panel refreshes after the update.

Images are pinned by SHA-256. The gateway runs as the calling user, with no
Linux capabilities, a read-only root filesystem, a bounded temporary directory
and external DNS disabled. Docker service discovery still resolves the engine;
usage records remain writable in their dedicated directory. Existing containers
receive these restrictions when stopped and started again.

Model engines still have writable container filesystems; the internal network
leaves them no outbound network access. Digest pins and build attestations establish image identity; they do
not make untrusted code safe. Engine restrictions need per-engine hardware
validation before rollout. Disabling gateway DNS does not block outbound IP
connections.

## The gateway key

Each running model's gateway answers at its address on the model's own Docker network, `http://<address>:12434/v1`: the model's page shows it under **this machine**, hidden until clicked, with a copy. The key is in `~/.local/state/omarchy/local-ai/gateway.key`. Send it there and nowhere else, as Local AI itself and the agents it opens do: only Docker assigns addresses on that bridge and no host interface holds them, so no other account on the machine can listen there, while `127.0.0.1:<port>` is free for any account to bind the moment the gateway stops. The gateway's port on `127.0.0.1` (from 12434) carries no key: Local AI only checks there that the gateway is up and that it refuses a request without the key.
