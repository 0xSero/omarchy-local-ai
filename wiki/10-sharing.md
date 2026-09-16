# 10 — Sharing on the tailnet

Sharing publishes the gateway's own port on this machine's tailnet address, next to the loopback one.
Nothing else is involved: no `tailscale serve`, no extra container, no root, no password.

## The key

The key exists from the first Start. Agents launched from the panel always send it; the gateway always
checks it; sharing adds nothing but the route.

| Property | Value |
|---|---|
| File | `$STATE/gateway.key`, 0600 |
| Generated | `head -c 24 /dev/urandom \| base64 \| tr -d '/+=\n' \| cut -c1-32` — 32 characters |
| Never in | the ledger, the snapshot, the log, any process argument, the `share` status |
| Accepted as | `Authorization: Bearer <key>` or `x-api-key` (the gateway's own business, not the plugin's) |
| Read | by the gateway on **every** request, so replacing it needs no restart |

`share --key <value>` (or `share --key -`, which reads the value from stdin so it never appears in a
command line) replaces it. The value must match `^[A-Za-z0-9._-]{16,128}$`, else
`key must be 16 to 128 letters, digits, . _ or -`.

Replacing a key also:

- deletes `$STATE/gateway.auth` (stale header cache),
- deletes every `$STATE/agents/*/` directory except `agents/args`, because those configs embed the old
  key — they are regenerated at the next agent launch,
- deletes `$STATE/share.cache`,
- writes a snapshot.

The suite asserts the old key is left nowhere under `$STATE`.

## Where it is exposed

| Surface | Header | Reachable from |
|---|---|---|
| `http://127.0.0.1:<port>/v1` | required | this machine only — loopback publish, always on |
| `http://<tailnet address>:<port>/v1` | required | your tailnet — only while sharing |
| the engine | — | nothing; it has no published port at all |

## `share_state`

Computed fresh on every snapshot (never cached), returned as the snapshot's `share`:

```json
{ "available": true, "active": true, "url": "http://box.tail.ts.net:12434", "keyFile": "…/gateway.key", "error": "" }
```

| Field | Meaning |
|---|---|
| `available` | `tailscale` exists **and** the machine has a tailnet address. `false` ⇒ the card shows *no tailscale* |
| `active` | sharing is wanted (`$STATE/share.on` exists) **and** that slot's gateway answers |
| `url` | `http://<MagicDNS name, else the IP>:<port>`; the IPv4 literal is bracketed when it is IPv6 |
| `keyFile` | the path, so the card can tell you where the key is — never the key |
| `error` | the last refusal, shown under the toggle |

### Which address is bound

Only a tailnet address, ever. `tailnet_self` parses `tailscale status --json` (5-second deadline) and
takes:

- IPv4 from `100.64.0.0/10` — the regex accepts only `100.64`–`100.127`;
- else IPv6 `fd7a:115c:a1e0:…`;
- else nothing, and sharing is *unavailable*.

`bind_addr` brackets an IPv6 literal, so docker gets `[fd7a:115c:a1e0::7]:12434:12434`.

`online` requires `Self.Online` **and** `BackendState == "Running"`.

### Address changes

`$STATE/share.on` holds the address the gateways were actually published on. If the tailnet address
changes under a live share, the gateways are still bound to the old one, so the snapshot reports
`active: false` with `tailnet address changed; share again` — it does not claim to be shared when it
is not. Sharing again publishes on the new address.

## Toggling

```
omarchy-local-ai share            # on → off, off → on
omarchy-local-ai share --key <v>  # replace the key in place
```

`share_toggle` refuses, **under the toggle** rather than in the ledger's error, when:

| Condition | Message |
|---|---|
| no tailscale, or no tailnet address | `tailscale is not installed or not logged in` |
| tailscale is not running/online | `tailscale is not connected` |
| no model is ready | `load a model first` |

Those refusals are `share_refuse`: they log, write `$STATE/share.error`, `op_done` and fail — so a
running model stays **ready** with the reason shown next to the share row, instead of the whole card
turning into an error.

Turning **on**: `: > $STATE/share.on`, then `restart_gateways` (one privileged phase). Each gateway is
removed and re-run with an extra `--publish <tailnet ip>:<port>:12434` — the loopback publish stays.
Engines are untouched; agents reconnect on their next request, because the gateway is stateless.

Turning **off**: the marker is removed first, then the gateways are restarted without the tailnet
publish. The marker is **restored** if the restart fails, so the card keeps saying *shared* rather
than lying. If no gateway answers at all, there is nothing to stop and the marker simply goes.

On success `$STATE/share.error` is removed and the op finishes. The panel then copies the new URL to
the clipboard by itself (see [11 — The panel](11-panel.md)).

`share_forget` drops the marker when the last model is unloaded — only once the published gateways are
really gone.

## Why not `tailscale serve`

`serve` refuses a plain user until root names them the operator (`tailscale set --operator=$USER`), and
the panel cannot escalate: no polkit agent runs in that context. It would also need the plugin to
manage a second piece of tailscale state. Publishing the port directly needs neither: WireGuard already
encrypts everything on the tailnet, so a plain `http://` URL there is exactly as private as the
`https://` one `serve` would have minted. The only tailscale call the plugin makes is
`tailscale status --json`, which needs no operator.

## What a peer does

```bash
curl -H "Authorization: Bearer $(cat ~/.local/state/omarchy/local-ai/gateway.key)" \
     http://box.tail.ts.net:12434/v1/models
```

Without the header: HTTP 401 with
`{"error":{"type":"authentication_error","message":"invalid or missing API key"}}`. That exact
response is also how the plugin recognises *its own* listener on a port when deciding whether the port
is busy (see [4 — State](04-state.md)).

## Failure modes

| Symptom | Cause |
|---|---|
| card says *still shared: could not restart the gateway* | the restart failed; the marker was put back, so the state on screen matches reality |
| card says *shared* but the peer gets connection refused | the tailnet address changed; the card shows `address changed` only after the next snapshot, or an ACL/firewall blocks the port |
| `could not publish on the tailnet: <docker's last line>` | docker refused the publish — read `$STATE/log` |
| peer gets 401 with the right key | the key was replaced after the client cached it |