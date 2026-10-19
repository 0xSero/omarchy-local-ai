# Privacy

Nothing, until you allow it. Home asks once whether to share minimal, anonymous
usage counts (**No thanks** or **Allow**; either answer is kept, and Settings
changes it later). An install from before this question is treated as not having
answered: off until you allow it. Once allowed, to count how many machines use it,
Local AI sends one small message each time it checks the registry for new models
(every 12 hours while the bar runs) to
`https://usage.sybilsolutions.ai/v1/local-ai/ping`:

```json
{"id": "9f2c…", "version": "6.15.0", "hw": ["rtx-3090"], "running": 1, "launched": true,
 "actions": {"started": 2, "failed": 0, "opened": 1, "downloaded": 1}}
```

`id` is a random number made on the first message and kept in
`~/.local/state/omarchy/local-ai/install-id`; it is not derived from the machine
or you, and Remove deletes it. `hw` lists the card kinds Local AI has recipes for
that it found, `running` how many models run, `launched` whether a model has ever
answered on this machine. `actions` are how many models started, starts that
failed, agents opened and models downloaded since the last message that arrived:
totals only, never which model, agent or folder. They wait in
`~/.local/state/omarchy/local-ai/counts.json` until a message arrives, so no
action is lost or sent twice, and nothing extra is sent when you use Local AI.
The server keeps those fields and the day, and no IP address or other header.
Its code, the D1 migrations and the deploy config are in [`usage/`](../usage) (the
worker `local-ai-usage` and its `usage.sybilsolutions.ai` route); the public
totals are the same worker's `GET /v1/local-ai/stats`.

Turn it on or off in the panel under **Settings** (send usage reports), or with
`omarchy-local-ai set ping on|off`; `DO_NOT_TRACK=1` in the bar's environment
keeps it off whatever the setting. Turning it off also deletes the actions not
yet sent, and nothing is counted while it is off or not yet allowed. A failed or
refused message changes nothing.

