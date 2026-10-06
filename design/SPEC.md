# Local AI panel: the design

Every state is drawn in `rows/frame.mjs` and saved as `screens/NN-<state>.png`; each has a GitHub issue. Values in the
drawings are samples.

## The frame

- One popup, 340 px. A **header band** (tabs home · gpus, tokens generated, today, the cumulative line, 󰊓 full screen)
  and a **footer band** (the machine in one line, e.g. `4 GPUs · 2 models running`; `logs · refresh`) in one surface
  tone. Their heights are fixed; the body between them has one height per machine (its tallest screen's), so switching
  tabs or pages never moves the top or the bottom.
- Pages under gpus (config, ⋯, agent, folder, share) open in the body with `‹ back`; the bands stay.
- One solid button per place; everything else is a quiet link. One spacing unit (28 px of clear space between things).
- Marks: a model line shows its lab's logo, a card its maker's (CPU: a chip glyph), all one colour in the line's tone;
  agents in black and white (`logos/README.md`).
- Errors are not drawn in the panel. They go to a desktop notification (`omarchy-notification-send`, click: logs); the
  line only shows the state it left.

## GPU rows

Closed, each row is two lines and a bar: the mark (lab for a model, maker for a card, a chip for the CPU), the name, on
the right what it is doing (`88 tok/s`, `free`, `downloading 42%`, `stopped`, `in use`) and ⌄; under it the card's facts
(`RTX 3090 · 21 / 24 GB · 62° · 87%`) and a memory bar the width of the row. Every row opens, in place, on click (a
dropdown on a raised surface, no animation), with its buttons inside:

- running: tok/s, prefill, first token, today, total, up; the last hour as a spark; model (change ›), agent, folder,
  share; `[Open pi] Stop · logs`.
- free: every model for the card, best first, fast · medium · smart tagged, the picked one highlighted, on disk /
  download / what it needs under each, one that does not fit dim; `[Run <picked>]`.
- in use (held by another program, or a build whose cards are busy): what holds it, then the models it could run,
  readable but not runnable.
- starting: the step and its progress; `stop`. stopped: when and why; `[Run again] dismiss · logs`.

## The states

| # | state | when | leads to |
|---|---|---|---|
| 01 | not-ready-setup | Docker access or the NVIDIA toolkit is missing | Set up → terminal |
| 02 | not-ready-docker | set up, Docker does not answer | Start Docker → terminal |
| 03 | not-ready-old | Omarchy has no Sudoless Docker | Update Omarchy → terminal |
| 04 | no-supported-gpu | no card with a tested model, nothing running | See supported cards → browser |
| 05 | home | tokens exist: tiers and the calendar (a column a week) | 󰊓 → full-home |
| 06 | home-first | nothing generated yet | gpus |
| 07 | gpus | ready, rows closed | open a row, 󰊓 |
| 08 | gpus-open-running | a running row opened | Open pi; Stop; model/agent/folder/share; logs |
| 09 | gpus-open-free | a free row opened: the model list | pick; Run |
| 10 | starting-download | weights downloading | loading |
| 11 | starting-load | engine loading, checks | ready |
| 12 | gpus-open-in-use | an in-use row opened | (read only) |
| 13 | stopped | a model stopped by itself, its row opened | Run again; dismiss; logs |
| 14 | notification | anything went wrong | click → logs |
| 15 | config | model: change › on a running model | pick; Run |
| 16 | config-hover-on-disk | a downloaded model in that list | Run; remove |
| 17 | more | (folded into the running row; kept for the full-screen ⋯) | agent, folder, share |
| 18 | agent | agent › | sets the model's agent; make default |
| 19 | folder | folder › | sets the folder; choose another… |
| 20 | share | share on | copy address, copy key, Stop sharing |
| 21 | one-gpu | a one-card machine (its row opened) | |
| 22 | cpu-only | no GPU | the CPU as the one row |
| 23 | full-gpus | 󰊓 on gpus | a tile per GPU, actions in plain view |
| 24 | full-home | 󰊓 on home | the year calendar, by model, by card |

fast · medium · smart (config) come from decode speed and the Artificial Analysis index (registry branch `aa-scores`,
not merged); until they are in the catalog, config lists the registry's order with the first that fits chosen.

## Stats storage: compacted tiers (2026-10-06; usage part built)

Raw logs live only until they are folded into a fixed set of aggregates, so storage is bounded and reads are cheap.

| tier | covers | one bucket per | buckets |
|---|---|---|---|
| day | last 24 h | 5 min | 288 |
| week | last 7 days | hour | 168 |
| month | last 30 days | 6 h | 120 |
| 3 months | last 90 days | day | 90 |
| year | last 365 days | week | 52 |
| lifetime | everything | month, plus one running total | ~12 a year |

- A bucket that ages out of a tier is added into the next tier's bucket (sums and counts only, so it rolls up exactly).
- Usage series, per model per build: requests, prompt and completion tokens, decode time and count (tok/s), prefill
  time and count, a coarse time-to-first-token histogram. Hardware series, per card by GPU UUID: max temperature,
  utilisation sum and count, energy as the delta of the card's own counter (NVIDIA total_energy_consumption,
  Intel hwmon energy1_input; a reset is detected and skipped). Runs: `{start, end, model, uuids}`, never deleted.
- The gateway keeps appending raw lines (it opens the log for each write). On each snapshot the backend renames the
  log aside, folds its lines into the aggregates, writes the aggregates and the read position atomically
  (temp + rename, under flock), then deletes the processed file: crash-safe, never double counted.
- No daemon: folding and hardware samples ride the panel's polls (seconds while open, 30 s while closed); a long
  backlog is folded in chunks. Reads touch only the aggregates file (~tens of KB).
- Built (bin/omarchy-local-ai `summary`, test/usage-test.sh): usage buckets by age (5 min → 30 days), a folded log over
  256 KB set aside and deleted, a shorter log treated as a new one (history kept), old per-hour summaries read as
  before; and `usage/<model>/runs.jsonl` (`{t, keys}` per start, never deleted). Not built yet: per-card hardware
  series (temperature, utilisation, energy counters) and the per-card views that use runs.jsonl.
- Views: gpus top line ← day tier; daily usage ← 3-month tier; home's line ← lifetime + finer tiers for the recent
  part; totals ← the running total.

## New data the backend needs

- Per-card stats are not recorded today. Usage is per model (`usage/<model>/usage.jsonl`: t, prompt, completion,
  ttft_ms, ms — no card); the cards a model used are only in `deploy/<model>/config.json` (`keys`), deleted on stop;
  temperature and memory are read live, never stored; utilisation and power are not read.
- To attribute tokens to cards: on each start, append `{t, uuids, names}` to `usage/<model>/runs.jsonl` (never deleted)
  and assign usage lines to the run that was active at their time. Use GPU UUIDs, not `nvidia:0`, which can change.
- Utilisation per card (nvidia-smi `utilization.gpu`; Intel hwmon) if busy % is shown.
