# 11 — The panel

Four files in `ui/`, one job: draw the snapshot and issue verbs. `ui/ui.js` decides **what** the rows
are (pure data, no Qt), `ui/Panel.qml` draws them and runs the verbs, `ui/CardRow.qml` draws one row,
`ui/Orb.qml` is the state orb.

```
ui/Panel.qml  ──uses──>  ui/ui.js:build({snap, view, …})  ──returns──>  {tone, eyebrow, title, sub, steps, path, rows, foot}
    │
    ├── ui/CardRow.qml   one row (sec | row | status | bar | stat | text)
    └── ui/Orb.qml       15×15 rounded-pixel field, lit from the centre
```

## ui/Panel.qml

| Property | Value |
|---|---|
| `moduleName` / `ipcTarget` | `sero.local-ai` — the IPC target the visual helper and tests call |
| `cli` | `<plugin dir>/bin/omarchy-local-ai`, resolved from `Qt.resolvedUrl("..")` (the QML lives in `ui/`) — the panel runs the plugin's own CLI |
| `stateDir` | `$XDG_STATE_HOME/omarchy/local-ai`, else `$HOME/.local/state/omarchy/local-ai` |
| `snap` | the last snapshot read; starts as `{state: "uninitialized"}` |
| `path` | the navigation stack: `["home"]`, `["home","card"]`, `["home","model"]`, plus `work` during an operation |
| `expanded` | compact (default) or full-screen; toggled by the header control, the `expand` action or `F11` |

### Palette

A locked, matte palette: fills rather than borders, sharp corners, no gradients.

| Token | Hex | Used for |
|---|---|---|
| `popupBg` | `#1a1a1a` | the card's background |
| `popupLine` | `#2e2e2e` | its single flat border |
| `ink` | `#f5f5f5` | titles, primary fills, ready |
| `fg` | `#bebebe` | values |
| `dim` | `#8a8a8d` | secondary text |
| `faint` | `#555555` | disabled text, section words |
| `urgent` | `#D35F5F` | errors, the danger verb |
| `accent` | `#e68e0d` | work in progress |
| `orbField` | `#4b4b4b` | the orb's unlit pixels |
| `recessed` | `rgba(0,0,0,0.24)` | the state slab, status rows, the toast |
| `restFill` / `hoverFill` / `selectedFill` | ink at 4% / 8% / 16% | row backgrounds |

`mono` is the bar's font family. Everything is `Text.PlainText`, so no recipe or model name can ever
be interpreted as markup.

### Tone

```
tone = "work"   while a verb runs           → accent
       "error"  when the last verb failed   → urgent
       "ready"  when a model is up          → ink
       "idle"   otherwise                   → dim
```

The bar icon is one square whose colour follows the tone and whose opacity blinks (500 ms each way)
while working. The tooltip is `Local AI · <the card's title>`.

On a tone change to `error`, or to `work` for anything but a share, the card returns to `home` — an
operation is never hidden behind a drill-down.

### Navigation

Three places: **home** (every GPU group with one cell per physical card, and each running model
nested under the group it holds) → **card** (a GPU group: how many cards, which recipe) → **model**
(one running model: its numbers, capabilities, agent, share, stop). Work and error take the card over
in between.

| Key | Action |
|---|---|
| `F11` | toggle full-screen |
| `Esc` | leave full-screen first, else back one level, else close at home |
| `Tab` / `Shift+Tab` | switch bar panel |
| `↓` / `j`, `↑` / `k` | move the cursor over actionable rows |
| `Enter` | run the row's action |
| `←` / `→` | in the card view: how many cards of this type to use |
| `Backspace` | back |

A GPU group with a model on it is not itself actionable — it is reached through the nested model row.
A free group opens the recipe picker.

### Compact and full-screen

At the top of the card sits a header row: `local ai` on the left, and on the right a control reading
**full screen ↗** or **compact ↙** (`activate("expand")`, or `F11`). Full-screen mode widens the card
to `panel.availableCardWidth` and raises the ceiling to the available card height minus the panel's
vertical inset; compact mode fits the content up to the **720 px** ceiling and 360 px width. Switching
never changes navigation or the selection, and the footer's verbs stay reachable because only the body
scrolls — on a short display the body shrinks to zero rather than pushing the verbs off-screen. A
failed snapshot derivation leaves the previous one on screen.

In compact mode the slab, the path, the header row and the footer are fixed; in full-screen mode the
body expands to fill the rest.

### The controller

| Object | Does |
|---|---|
| `FileView` | watches `$STATE/snapshot.json` (`watchChanges`), takes it on load and on every change |
| `Process poll` | runs `omarchy-local-ai snapshot`; ignores an answer over 256 KiB |
| `Process action` | runs one verb at a time; on exit runs the next queued verb, then marks the action done and refreshes |
| `Process agentLaunch` | `open-agent <agent> <recipe>`; closes the panel on exit 0 |
| `Process copy` | `wl-copy` the share URL; exit 127 shows *wl-copy · missing* |
| `Process logOpen` | `omarchy-launch-tui --app-id=org.omarchy.local-ai-log less +G $STATE/log` |
| `Timer` (main) | refresh every **1 s** while pending, **2 s** while working, **10 s** while open, **60 s** while closed |
| `Timer pendingTimeout` | 20 s: drop the optimistic pending flag if nothing confirms it |
| `Timer` (elapsed) | 1 s while working, for the running clock |

**Pending is optimistic and then authoritative.** Clicking a row sets `pending` and starts the verb
immediately, so the card turns busy on the click rather than a second later. `pending` is cleared when
a snapshot shows the operation (for `run`/`load`/`unload`/`share`) or when the process exits (for
every other verb). A parse failure of a non-empty answer is ignored; an empty answer becomes
*no answer*.

When a model disappears while the card was stopping, the panel toasts which card came free:
`<card name> #<index> · freed`.

### Verbs the panel issues

`load`, `unload`, `unload <recipe>`, `run <recipe> <backend:index>`, `share`, `open-agent <agent> <recipe>`,
`copy:<recipe>` (via `wl-copy`), `refresh`, `log`, and `expand` (local to the panel — the size control
does not touch the controller). The card never calls `gpu`/`recipe` on its own: `run` pins both in one
process.

### IPC

```
quickshell ipc --any-display -p /usr/share/omarchy/shell call sero.local-ai <fn> [args]
```

| Function | Effect |
|---|---|
| `open` / `close` / `toggle` | the panel |
| `load` / `unload` / `refresh` | the corresponding verb |
| `activate <action>` | runs **any** row action — `card:rtx-3090-24gb`, `count:2`, `pick:<recipe>`, `model:<recipe>`, `run:<recipe>:<n>`, `share`, `copy:<recipe>`, `stop:<recipe>`, `open-agent:<agent>:<recipe>`, `back`, `expand`, `home` — and returns `<tone>:<view>` |

`activate` is what `test/visual` drives and what a scripted screenshot uses.

## ui/ui.js — the rows

`build(c)` returns `{tone, eyebrow, title, sub, steps, path, rows, foot}`. A row is:

```js
{ type:"row"|"sec"|"stat"|"bar"|"status"|"text", label, value,
  action:"", kind:""|"primary"|"danger"|"dd",
  selected, disabled, urgent, child, cells:[{text,mark}], chips:[{text,off,action}],
  tabs:[{text,on,action}], stat:[{k,v,u}] }
```

`child: true` marks a row as belonging to the row above it — that is how a running model sits under
its GPU group. `ui/CardRow.qml` indents it by `Style.space(18)` and draws it at `list.width - x`.

Helpers worth knowing: `gb`, `kb`, `kmg`, `mmss`; `freeKeys`, `freest` (the free card with the most
memory — a display card carries the desktop, so start elsewhere when there is an elsewhere); `fits(snap, card, n)`
(the recipes usable with exactly *n* cards); `where(snap, model)` (which card a model is on);
`workKeys` (the cards a running op touches); `shortError` (the four-word error word: *no card*,
*no recipe*, *port busy*, *driver*, *out of VRAM*, *too slow*, *stopped*, *acceptance failed*,
*no answer*, *refused*, *docker*, *disk full*, *error*).

**Home is grouped, not flattened.** The first section is `gpus`; each GPU group row reads
`2× RTX 3090` with a second line of one **cell per physical card** — `free · 41°`, `#1 locked`,
`claimed`, `freeing` or `crashed` — and a datum that is `N recipes ›` when the group is free, or
`N locked` when it is not. An occupied group is not actionable; each running model appears under it as
a `child` row (`<model name>` · `<tps> tok/s ›`, or `crashed ›`), and that is where a model is opened
from. A free group's action is `card:<hardwareId>`.

## ui/CardRow.qml

One component, six row types, drawn from the row object: `sec` (a section word), `row` (noun · datum,
with cells/chips underneath or a count toggle beside it), `status` (verb · progress, larger), `bar`
(a filled bar, or a sweep while no percentage is known), `stat` (two figures), `text` (a wrapped
sentence — the one place a whole reason is shown).

## ui/Orb.qml

A 15 × 15 field of rounded pixels, clipped circularly, lit from the centre with a quadratic falloff
and a smoothstep edge band, with a per-cell phase offset so the shimmer travels. One `NumberAnimation`
drives `phase` 0 → 1 over the tone's period and loops while the panel is open — **1200 ms** while
working, **2400 ms** ready, **1800 ms** error, **3200 ms** idle — and the lit radius breathes between
84 % and 100 % of the field. The orb *is* the state; a download animated by it never carries progress,
because that is the bar's job. It is built from plain `Rectangle`s on purpose: in this shell a
`Canvas`'s `requestPaint` does not repaint.