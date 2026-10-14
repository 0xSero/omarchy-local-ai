# local-ai-usage

Folded in from the former [sybil-solutions/local-ai-usage](https://github.com/sybil-solutions/local-ai-usage) repository
(archived): the worker source, the D1 migration and the deploy config live here, and the plugin repository owns the counter it
serves. The deployed worker keeps the name `local-ai-usage` and the `usage.sybilsolutions.ai` route, so a deploy from this
directory updates the same worker:

```bash
cd usage && npx wrangler@4 deploy
```

Counts installs of the [Local AI](https://github.com/sybil-solutions/omarchy-local-ai) Omarchy plugin. A Cloudflare Worker with one D1 table, at `https://usage.sybilsolutions.ai`.

## What an install sends

When the plugin checks the registry for new models (every 12 hours while the bar runs), it sends:

```json
{"id": "9f2c…32 hex", "version": "6.15.0", "hw": ["rtx-3090"], "running": 1, "launched": true,
 "actions": {"started": 2, "failed": 0, "opened": 1, "downloaded": 1}}
```

- `id`: a random number the plugin made on first run, kept in `~/.local/state/omarchy/local-ai/install-id`. It is not derived from the machine or the user.
- `version`: the plugin version.
- `hw`: the card kinds Local AI has recipes for that it found (the registry's hardware ids), or none.
- `running`: how many models are running.
- `launched` (6.15.0+): whether a model has ever answered on this install (the gateway's usage log is not empty).
- `actions` (6.15.0+): models started, starts that failed, agents opened and models downloaded since the install's last delivered ping. Totals only. The plugin keeps them until a ping arrives, then subtracts what it sent.

The Worker stores those fields and the UTC day, one row per install per day; actions in the same day add up. It stores no IP address, user agent or other header. The caller's address is used only by Cloudflare's in-memory rate limit.

Turn it off in the panel (Settings, send usage reports), with `omarchy-local-ai set ping off`, or `DO_NOT_TRACK=1` in the environment the bar runs in.

## Security

- Cloudflare Worker `local-ai-usage` and D1 database `local-ai-usage` (Western Europe), reachable only through the Cloudflare account; no `workers.dev` or preview address (`workers_dev = false`, `preview_urls = false`).
- No request logs (`[observability]` off), so Cloudflare keeps no caller address for this worker; the worker writes none either. The rate limit (20 a minute per address) is in memory.
- Pings must be JSON and at most 1 KB, refused by `Content-Length` before the body is read; every field is checked against a fixed shape, and anything else is a 400 that writes nothing.
- Every response sends `nosniff`, `no-referrer`, HSTS and `X-Frame-Options: DENY`; the dashboard has a CSP allowing only its own inline script (by SHA-256, computed from `page.html` at start), inline styles, this worker and the plugin's traffic files. Only the stats allow other origins to read them. Internal errors return a bare 503.
- Pings are not authenticated (any key in an open-source plugin would be public), so totals can be inflated by someone sending made-up pings; nothing can be read or changed that way.

## Reading it

The dashboard is at `https://usage.sybilsolutions.ai/` (`src/page.html`): it reads the stats below and the `stats` branch's traffic files in the browser.


`GET https://usage.sybilsolutions.ai/v1/local-ai/stats` (public, cached 5 minutes):

- `installs`: `installs` ever seen; `launched`, installs that ever ran a model (a model answered, a start finished, or one ran at a check-in); active `today`, this `week` (7 days), this `month` (30 days); `monthRunning` (running at a check-in in the last 30 days); `monthUsed` (started, opened or ran a model in the last 30 days); and the 30-day totals `monthStarted`, `monthFailed`, `monthOpened`, `monthDownloaded`.
- `daily`: the last 90 days: `active`, `running`, `new`, `started`, `failed`, `opened`.
- `week`: versions and hardware of the installs active in the last 7 days.

The plugin repository's `traffic` workflow records this daily on its `stats` branch, next to GitHub traffic.

## Deploy

```sh
npx wrangler d1 migrations apply local-ai-usage --remote
npx wrangler deploy
```
