# local-ai-usage

Counts installs of the [Local AI](https://github.com/sybil-solutions/omarchy-local-ai) Omarchy plugin. A Cloudflare Worker with one D1 table, at `https://usage.sybilsolutions.ai`.

## What an install sends

When the plugin checks the registry for new models (every 12 hours while the bar runs), it sends:

```json
{"id": "9f2c…32 hex", "version": "6.13.0", "hw": ["rtx-3090"], "running": 1}
```

- `id`: a random number the plugin made on first run, kept in `~/.local/state/omarchy/local-ai/install-id`. It is not derived from the machine or the user.
- `version`: the plugin version.
- `hw`: the card kinds Local AI has recipes for that it found (the registry's hardware ids), or none.
- `running`: how many models are running.

The Worker stores those four fields and the UTC day, one row per install per day. It stores no IP address, user agent or other header. The caller's address is used only by Cloudflare's in-memory rate limit.

Turn it off with `omarchy-local-ai set ping off`, or `DO_NOT_TRACK=1` in the environment the bar runs in.

## Reading it

`GET https://usage.sybilsolutions.ai/v1/local-ai/stats` (public, cached 5 minutes):

- `installs`: `installs` ever seen, active `today`, this `week` (7 days), this `month` (30 days), and `monthRunning` (ran a model in the last 30 days).
- `daily`: the last 90 days: `active`, `running`, `new`.
- `week`: versions and hardware of the installs active in the last 7 days.

The plugin repository's `traffic` workflow records this daily on its `stats` branch, next to GitHub traffic.

## Deploy

```sh
npx wrangler d1 migrations apply local-ai-usage --remote
npx wrangler deploy
```
