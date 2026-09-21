# 11 — The panel

Local AI has two presentations of the same controller: its standalone bar panel and an optional third tab inside Omarchy's native Agents view. Both use the same row data, launch handler and snapshot. Native integration is installed from `integrations/install-agents.py`; it patches a user-owned copy of the installed Agents panel and leaves system files untouched.

## Overview and details

The overview contains **Launch agent**, collapsed by default, and one status row per GPU type. Expanding the launcher shows the running model, compatible installed agent, project folder and Open action. The selected folder is remembered. A missing folder refuses launch rather than opening elsewhere.

**Deployments** lists GPU groups in stable order, with the current model and visible status beneath each name. **Manage** opens a running deployment; **Load model** opens the picker for an available group. **Tokens by GPU** is a separate read-only section below deployments, using the native Agents model-row layout. Bars have no deployment action or keyboard focus. They show available historical generated tokens, with today's count on hover and ≈ for estimated vLLM counts. Hide this section when no history is available; zero and unavailable readings otherwise remain compact. The model picker supports one or more GPUs of the same type; running models remain inspectable, while loading requires enough free GPUs.

Model details put agent launch above today's runtime statistics, context and capability information, with device temperature, utilization and VRAM meters. Missing sensors or unsupported engine statistics show N/A. Per-device readings stay out of the overview.

The footer contains the update action. A check stages newer recipe/plugin information; applying it uses Omarchy's updater. Sharing and Stop belong to the running model. Copy opens a full-panel URL overlay anchored to the visible viewport, independent of scroll position. Copy URL (or Enter/Ctrl+C) copies and closes it; Close or Escape dismisses it. Failures remain inside the overlay. The keyboard cheat sheet has its own OS status-bar button.

## Styling and scrolling

The native view uses Omarchy's Button, PanelSectionHeader, PanelSeparator, fonts and colors. Ordinary rows have no permanent box border. Disclosure headings use a chevron and stronger text, with indented choices. Hover backgrounds have internal padding; only the device header reacts to hover.

The embedded view uses the native panel's outer scroll container. Standalone mode scrolls the whole page, including headers, folder editing and footer actions, and supports F11 expansion. Mouse wheels work across the content; Home/End and Page Up/Down move the viewport. Keyboard navigation reveals the selected action, and resizing clamps the scroll position.

Every breadcrumb is a direct link, including the current destination, and long paths wrap on narrow screens. Navigation returns to the top. During a deployment you can browse GPU groups and models, then select View progress to return; conflicting deployment actions remain disabled.

## Source responsibilities

| File | Responsibility |
|---|---|
| `ui/ui.js` | Pure data: overview, GPU/model selection, launcher, operation and error rows |
| `ui/TokenTotal.qml` | Lightweight token bars and hover readout |
| `ui/CardRow.qml` | Render rows, sections, disclosures, status, bars and device meters |
| `ui/Panel.qml` | Snapshot polling, navigation, folder editing, terminal launch and controller verbs |
| `integrations/agents-panel.patch` | Add Local AI to the native panel and connect scrolling/focus |
| `integrations/Shortcuts.qml` | Separate status-bar help button |

The decorative orb has been removed. Model and recipe text is rendered as plain text.

## Keyboard and IPC

Within Local AI, arrows or j/k move through actions, Enter activates, Backspace returns, and Ctrl+O edits the project folder. In standalone mode F11 expands the panel. The native wrapper handles tab selection and its own panel navigation.

The plugin exposes the sero.local-ai IPC target for open, close, toggle, refresh and row activation. For example:

```bash
quickshell ipc --any-display -p /usr/share/omarchy/shell call sero.local-ai activate home
```

`test/navigation` runs native wheel, keyboard, resize and breadcrumb checks using an isolated controller fixture on Omarchy. It covers standalone and embedded views at 240×180, 380×400 and 600×650, including folder editing, empty/error/progress screens and navigation during deployment work. It requires QtTest and a running Wayland session.

`test/visual` drives row actions and captures the live panel. `test/ui.cjs` checks launcher selection, stale selections, GPU availability, compact overview data and retained detail meters.

## Statistics and refresh

The panel watches the snapshot file and refreshes more often while working. Runtime telemetry has a shared ten-second cache and file lock, so multiple panel instances do not each rescan the engine logs. It creates no inference traffic.

For vLLM and llama.cpp, decode/prefill are averages of non-zero engine log samples since local midnight, not the one-off acceptance speed. Generated tokens are backfilled from retained runtime logs and attributable older gateway receipts. vLLM counts are marked approximate. GPU telemetry adapters cover NVIDIA, Intel and AMD, with physical validation currently completed on NVIDIA and Intel.

## Mac and Moonlight

The optional profile uses click-to-focus, Command+Tab for the next window, Command+Space for apps and Control+Command+F for fullscreen. Ctrl+Space then P selects the previous window; shifted Command+Tab was unreliable through the stream. Command+W and Command+D are contextual: application tab/bookmark commands in a browser, window close/new terminal in Foot.

The OS bar help button opens the offline visual guide installed at ~/.local/share/omarchy/guides/macos-controls.html. The guide includes search, workspace/window examples, agent setup and stream escape instructions. Its browser rendering remains an open acceptance check.
