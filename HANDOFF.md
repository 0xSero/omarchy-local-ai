# Handoff: Local AI v6, continued on the Omarchy box

Moved from the Mac on 2026-09-22 so the work happens where it runs. The Mac copy stops being edited.
`docs/progress.md` (state and evidence) and `docs/design.md` (the design) are the long form;
`docs/plan.html` and `docs/first-principles.html` are the explainer pages.

## Intent

Rebuild the Local AI plugin from first principles as one bash backend, one card and one vendored
data file that look like Omarchy wrote them, keep shipping it on the marketplace as 6.0.0, then get
it into Omarchy by the Elsewhen route (a package plus a ~100-line PR). The card's design does not change.

## Verified state

- Registry: schema-2 export merged to `0xSero/local-ai-registry` main (PR #79): `plugin/v2/recipes.json`,
  36 hardware ids, 81 recipes, one entry per line. Mounts, devices, IPC, capabilities and security options
  do not exist in the schema.
- Plugin repo `omarchy-local-ai`, branch `v6`, pushed. Contains:
  `bin/omarchy-local-ai` (806 lines, the whole backend), `Panel.qml`, `CardRow.qml`, `Model.js` (the card),
  `manifest.json` 6.0.0, `recipes.json` (schema 2), `bin/omarchy-install-ai-local`, `bin/omarchy-remove-ai-local`,
  `test/all` and `test/shell.d/local-ai-{start,priv,weights,hardware,model}-test.sh` with shims in
  `test/shell.d/fixtures/local-ai/env.sh`, `Makefile`. The old `lib/ ui/ native/ scripts/ wiki/ media/` are gone.
- Tests on Linux: start 19/19, priv 11/11, hardware 17/17 pass on the Omarchy box; weights 10/11 (see below);
  the node Model.js test needs node (Pop!_OS has it, the box does not).
- QML lints clean on the box (`/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I /tmp/qsroot Panel.qml`, with
  `/tmp/qsroot/qs -> /usr/share/omarchy/shell`).
- The live plugin (5.4.0, `main`) is untouched: the marketplace listing and the box's install stay on it until
  6.0.0 is green and live-tested. `main` has three local unpushed commits on the Mac (integrations moved to
  `moonlight/`, the design); they are also on `v6`.

## Done since the handoff (2026-09-22, from the Mac against the box)

- Suite: 59/59 on Omarchy (Model.js test skips without node), 100/100 on Pop!_OS with node. The
  background-download cancel case now waits for the worker instead of a fixed second.
- Weights adoption: a verified copy under `$MODELS` (the 5.x layout), `~/models`, `~/.cache/llama.cpp` or the Hub
  cache is hard-linked into place; on the box the 8 GB Gemma EXL3 from 5.4.0 was adopted in one second.
- Live on the box as a second plugin `sero.local-ai-next` (bar entry added before Agents; the 5.4.0 install and
  its `ledger.json.5x` backup are untouched). Direct mode: ready in ~35 s, all three dialects, gateway 1000:1000 on
  loopback, engine private IPC, no caps, no published ports, read-only mounts, 401 without the key. Prompt mode
  with a real pkexec (temporary polkit rule, removed after): load 49 s, stop 7 s, dismissed prompt → clean reason.
- `remove --purge` (root) also deletes `~/.cache/omarchy/local-ai/scratch`, where an engine running as root inside
  its container leaves root-owned files (13k such files exist from the 5.x vLLM cache under `cache/vllm`).
- README, CHANGELOG `[6.0.0]`, workflows (`make bundle` before publish; the daily registry sync commits the v2 export).

## Pending work, in order

1. Sero clicks "Local AI (next)" on the bar: the only check not done from a shell. The shell log shows the same
   duplicate-IpcHandler warning the 5.4.0 plugin always logged (328 times in the journal); not a regression.
2. Release 6.0.0 on `main`: merge `v6` (it contains the three local `main` commits), tag, let the release workflow
   publish; retarget marketplace issue #5990; update the box's real install with `omarchy plugin update sero.local-ai --yes`,
   then remove the `sero.local-ai-next` test copy and its bar entry.
3. The upstream PR (Elsewhen route): Install › AI / Remove › AI menu entries pointing at the two installers, a
   paragraph under "Local LLMs" in `manual/17-ai.md`, a migration test modelled on `elsewhen-default-migration-test.sh`.
   `~/omarchy` on the Mac is a clean fork checkout on current upstream.
4. Registry: Sero's recommendation rule (16 GB and up → Qwen3.8-27B EXL3 with vision and full KV; 12 GB → Qwen3.5-9B;
   below → LFM2.5) is a three-line change to `TIERS` in `scripts/recommend.py` plus nine validation runs
   (seven 16 GB cards on turboderp's sc3bpw, the RTX 4000 Ada, vision on the 3090 Ti and 5090 4bpw builds).
   Mia-AiLab's `Qwen3.8-27B-EXL3-3.5bpw` (14.3 GB, EXL3 1.4.2, text-only, sha 19441ac8) loads on our attested
   TabbyAPI image (exllamav3 1.4.2) and could be a text-only candidate; their fork (MTP, DFlash2, NVFP4 KV) would be
   a new engine and image.

## Verification commands

```bash
# this workspace is the plugin repository, branch v6
bash test/all                                   # every shell test; node needed for the Model.js one
bash test/shell.d/local-ai-weights-test.sh      # the one with the open case
git clone -q https://github.com/0xSero/local-ai-registry ../local-ai-registry 2>/dev/null; make check REGISTRY=../local-ai-registry   # tests + recipes.json schema + currency
```

## Machines and traps

- This box: `~/.config/omarchy/plugins/sero.local-ai` is the live 5.4.0 install; `~/suite-v6` was a scratch copy
  of the tree used for test runs and can go. No node here.
- pop-os: `ssh pop-os`, has node; `~/suite-v6` scratch copy there too.
- Shell traps: `cp` is `cp -i` on the Mac only. Never `pkill -f` a pattern from the driver shell. `set -e` and
  `x=$(f)`: guard every substitution of a function that can fail. The pkexec shim in the fixture runs the
  target with `env -i`, so a test that passes there crosses the real boundary.
