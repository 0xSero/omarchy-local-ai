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

## Pending work, in order

1. Fix the one failing case: `local-ai-weights-test.sh` "a running download can be stopped" (background
   worker with `OMARCHY_AI_FOREGROUND=0`; on Pop!_OS the state read `idle` after 1 s and the models dir did not
   exist). Likely the detached worker's timing or the cancel path in the `unload` verb.
2. `.github/workflows/test.yml` and `release.yml`: `make check` now needs `plugin/v2/recipes.json` from the
   registry checkout (Makefile already points there); `registry.yml`'s daily sync should use `make sync` (v2).
   CI needs node for the Model.js test (ubuntu-latest has it).
3. README.md and CHANGELOG.md (a `[6.0.0]` section: what changed, what was dropped and why, the state-file
   rename `ledger.json` → `state.json`, the schema-2 recipes, the verbs).
4. Deploy for a live test on this box without touching the 5.4.0 install: install the `v6` tree as a second
   plugin dir (`~/.config/omarchy/plugins/sero.local-ai-next` with the manifest id changed to
   `sero.local-ai-next` for the test only), `omarchy-shell -q shell rescanPlugins`, `omarchy bar put`, then in
   prompt mode: `OMARCHY_AI_DOCKER=prompt OMARCHY_AI_FOREGROUND=1 ./bin/omarchy-local-ai load <recipe-id>` for
   the 3090's recommended recipe, with the temporary polkit rule from the skill
   (`~/.claude/skills/omarchy-local-ai/SKILL.md`, "Live tests on the box"). Check: gateway container runs as
   1000:1000, engine has no `--ipc`, nothing root-owned under `~/.local/state/omarchy/local-ai`, the card shows
   ready, an agent opens.
5. Then 6.0.0: version, changelog, tag, release workflow; retarget marketplace issue #5990; update the box's
   real install with `omarchy plugin update sero.local-ai --yes`.
6. The upstream PR (Elsewhen route): Install › AI / Remove › AI menu entries pointing at the two installers,
   a paragraph under "Local LLMs" in `manual/17-ai.md`, a migration test modelled on
   `elsewhen-default-migration-test.sh`. `~/omarchy` on the Mac is a clean fork checkout on current upstream.

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
