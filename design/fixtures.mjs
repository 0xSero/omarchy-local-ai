// Local AI design fixtures: real snapshots, built the way bin/omarchy-local-ai builds them.
//
// The panel is a function of one JSON snapshot (Model.js). A design that invents a snapshot designs a
// machine that does not exist, so this file builds each machine from the vendored recipes.json with the
// backend's own rules (busy, taken, free, kinds, models, groups, unfit) and then adds only the runtime
// state a snapshot carries: a deployment's step and percent, and the usage log.
//
// design/build.mjs runs Model.build() on every case here, so every screen in the studio is the real view
// for that machine rather than a mock-up of one.

import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const HERE = path.dirname(fileURLToPath(import.meta.url))
export const RECIPES = JSON.parse(fs.readFileSync(path.join(HERE, "..", "recipes.json"), "utf8"))

// ---------------------------------------------------------------- the backend's own rules

// summary($host) in bin/omarchy-local-ai: the recipe as the panel sees it, with ctx from serving.ctxTokens
export function recipe(hw, i) {
  const r = RECIPES.hardware[hw].recipes[i]
  return { id: r.id, name: r.name, family: r.family, cards: r.cards || 1, format: r.format, sizeGb: r.sizeGb,
    ctx: (r.serving || {}).ctxTokens || null, caps: r.capabilities || null, needs: r.needs || null,
    weights: (r.weights || []).map((w) => ({ repository: w.repository, revision: w.revision })) }
}

// unfit($h) in bin/omarchy-local-ai: what the recipe needs that this machine does not have
export function unfit(r, h) {
  const n = r.needs || {}, w = (r.weights || []).map((x) => (x.layout === "hub" ? "" : `${x.repository.replace(/\//g, "--")}@${x.revision.slice(0, 12)}`))
  const got = w.reduce((a, k) => a + (((h.got || {})[k] || 0) / 1e9), 0), out = []
  if ((n.host_ram_gb || 0) > h.freeRamGb) out.push(`needs ${Math.ceil(n.host_ram_gb)} GB RAM, you have ${Math.floor(h.freeRamGb)}`)
  if ((n.disk_gb || 0) - got > h.diskFreeGb && (w.length === 0 || !w.some((x) => (h.have || []).includes(x + "/.verified"))))
    out.push(`needs ${Math.ceil(n.disk_gb)} GB free disk, you have ${Math.floor(h.diskFreeGb)}`)
  if ((n.fast_storage || "") === "nvme" && h.disk !== "nvme") out.push("needs the models folder on an NVMe drive")
  return out.join("; ")
}

// The recipes of one card kind: the first on one card is its recommended model and the rest are what its
// Config offers; a recipe across several cards is a group.
function kind(hw, host, extra) {
  const models = [], groups = []
  RECIPES.hardware[hw].recipes.forEach((raw, i) => {
    const r = recipe(hw, i)
    r.unfit = unfit(r, host) || null
    ;(r.cards === 1 ? models : groups).push(r)
  })
  ;(extra || []).forEach((r) => groups.push(Object.assign({ cards: 2, family: "qwen" }, r)))
  return { hw, models, groups }
}

// ---------------------------------------------------------------- a machine

// A card as the backend reports it. `usedMiB: null` is a card that does not report its memory in use
// (Intel), which the panel draws as no bar; a CPU has no VRAM at all and reports RAM instead.
export function gpu(o) {
  return Object.assign({ key: "nvidia:0", hw: "rtx-3090-24gb", name: "RTX 3090", backend: "nvidia",
    vramGb: 24, usedMiB: 11_800, tempC: 62, held: false }, o)
}

// A running model: its recipe plus the step its worker is on (status.json) and its usage log (session).
export function deploy(r, o = {}) {
  const session = Object.assign({ lines: 4210, requests: 128, total: 1_284_000, week: 412_000, first: 1_785_000_000,
    last: 1_786_000_000, decode: 88.4, prefill: 1240, ttft: 180, ttftn: 128, since: "Sep 29", line: line(24) }, o.session || {})
  return Object.assign({}, r, { keys: ["nvidia:0"], state: "ready", agent: "pi", folder: "/home/sero/Work",
    shared: "", port: 12434, startedAt: "2026-09-29T17:00:00Z", detail: "", percent: 0, error: "",
    session: { all: session } }, o)
}

// the 24-point line a card draws: cumulative tokens, so it rises to the right
function line(n) {
  const out = []
  for (let i = 0; i < n; i++) out.push(Math.round(1_000_000 * (i / (n - 1)) ** 1.6))
  return out
}

// the lifetime grid: a column a week from a Monday, a row a weekday, 140 days
export function life(o = {}) {
  const today = o.today === undefined ? 132 : o.today, top = 41_000, days = []
  for (let i = 0; i <= today; i++) {
    const v = (i * 37) % 11
    days.push(v < 3 ? 0 : Math.round(top * (v - 2) / 9))
  }
  return Object.assign({ requests: 1284, since: "Sep 29", last: 1_786_000_000, start: 1_780_000_000,
    today, days, total: days.reduce((a, v) => a + v, 0) }, o)
}

function session(days = 140) {
  const cells = []
  for (let i = 0; i < days; i++) cells.push(Math.round(40_000 * (0.15 + ((i * 53) % 17) / 22)))
  return { requests: 1284, since: "Sep 29", last: 1_786_000_000, start: 1_780_000_000, today: days - 1,
    days: cells, total: cells.reduce((a, v) => a + v, 0) }
}

// The whole snapshot. `gpus` carries only what the machine's own tools report; busy, taken, free, kinds
// and the deployments' placement are derived here exactly as cmd_snapshot derives them.
export function snapshot(m) {
  const gpus = m.gpus || [], deployments = m.deployments || []
  const host = Object.assign({ ramGb: 64, freeRamGb: 48, disk: "nvme", diskFreeGb: 400, got: {}, have: [] }, m.host || {})
  const busy = new Set(deployments.flatMap((d) => d.keys))
  const taken = gpus.filter((g) => (g.held || (g.usedMiB || 0) > 2048) && !busy.has(g.key)).map((g) => g.key)
  const free = gpus.filter((g) => !busy.has(g.key) && !taken.includes(g.key)).map((g) => g.key)
  const kinds = []
  for (const hw of [...new Set(gpus.filter((g) => g.hw !== "").map((g) => g.hw))]) {
    const keys = gpus.filter((g) => g.hw === hw).map((g) => g.key)
    kinds.push(Object.assign(kind(hw, host, m.extraGroups), { keys, free: keys.filter((x) => free.includes(x)), taken: keys.filter((x) => taken.includes(x)) }))
  }
  const all = ["pi", "claude", "codex", "opencode", "omp", "crush", "grok", "copilot", "hermes"]
  return { version: m.version || "6.9.0", setupError: m.setupError || "",
    readiness: m.readiness || { state: "ready", message: "" }, host,
    week: 412_000, total: session().total, life: m.life || life(),
    defaults: m.defaults || { agent: "pi", folder: "/home/sero/Work" },
    agents: m.agents === undefined ? all : all.filter((a) => m.agents.includes(a)),
    folders: m.folders || ["/home/sero/Work", "/home/sero/Projects"],
    tailnet: m.tailnet === undefined ? "machine.example.ts.net" : m.tailnet,
    gpus: gpus.map((g) => Object.assign({}, g, { busy: busy.has(g.key) })), kinds, deployments }
}

// ---------------------------------------------------------------- the machines

const NINJA = gpu()

// One group recipe, for the group screen: the registry currently has none, so this is the shape a
// two-card recipe takes (cards > 1). It is labelled here as the only invented recipe in this file.
const GROUP2 = { id: "qwen38-27b-exl3-3bpw-2x3090-sglang-tp2", name: "Qwen3.8-27B", family: "qwen",
  cards: 2, format: "EXL3 · 3 bpw", sizeGb: 13.84, ctx: 212992, caps: { chat: true, tools: true, vision: true },
  needs: null, weights: [], unfit: "" }

export const MACHINES = {
  // the reference machine: one 3090, one model ready on it, a lifetime of use
  desktop: (o = {}) => snapshot(Object.assign({
    gpus: [NINJA], life: life(),
    deployments: [deploy(recipe("rtx-3090-24gb", 0))],
  }, o)),
  // the same machine with the card free: no deployment and nothing else using it, so the card row offers the
  // model validated for it. The desktop fixture's card reports 11.8 GB in use, which is the held card, so a free
  // card needs the memory reading cleared as well as the deployments.
  free: (o = {}) => snapshot(Object.assign({
    gpus: [gpu({ usedMiB: 0 })], life: life(), deployments: [],
  }, o)),
  // a model that keeps experts in system RAM: it needs more than the machine has, so Config says what it lacks
  offload: (o = {}) => snapshot(Object.assign({
    gpus: [gpu({ usedMiB: 3_100 })], host: { ramGb: 64, freeRamGb: 41, disk: "nvme", diskFreeGb: 22 },
  }, o)),
  // Intel: a card that does not report its memory in use, so its row carries no bar
  b70: (o = {}) => snapshot(Object.assign({
    gpus: [gpu({ key: "intel:0", hw: "intel-arc-pro-b70-32gb", name: "Intel Arc Pro B70", backend: "intel", vramGb: 32, usedMiB: null, tempC: 51 })],
    host: { ramGb: 64, freeRamGb: 52, disk: "nvme", diskFreeGb: 400 },
  }, o)),
  // a CPU model: no card at all, and the hardware page says HARDWARE rather than GPUS
  cpu: (o = {}) => snapshot(Object.assign({
    gpus: [gpu({ key: "cpu", hw: "x86-64-avx2-cpu", name: "AMD EPYC 7443 (AVX2)", backend: "cpu", vramGb: null, ramGb: 64, usedMiB: null, tempC: null })],
  }, o)),
  // a big card, and several models of the same kind, so Config has something to choose between
  server: (o = {}) => snapshot(Object.assign({
    gpus: [gpu({ key: "nvidia:0", hw: "rtx-pro-6000-blackwell-96gb", name: "RTX PRO 6000 Blackwell", vramGb: 96, usedMiB: 70_000, tempC: 58 })],
    host: { ramGb: 128, freeRamGb: 110, disk: "nvme", diskFreeGb: 900 },
  }, o)),
  // two cards of different kinds: home lists a row each, hardware lists both
  mixed: (o = {}) => snapshot(Object.assign({
    gpus: [NINJA, gpu({ key: "intel:0", hw: "intel-arc-pro-b70-32gb", name: "Intel Arc Pro B70", backend: "intel", vramGb: 32, usedMiB: null, tempC: 51 })],
  }, o)),
  // two cards of one kind, and a group recipe for them
  group: (o = {}) => snapshot(Object.assign({ gpus: [NINJA, gpu({ key: "nvidia:1" })], extraGroups: [GROUP2] }, o)),
  // a card another program holds: home says so, and Config still opens for it
  held: (o = {}) => snapshot(Object.assign({ gpus: [gpu({ held: true, usedMiB: 21_000 })] }, o)),
  // a card with no validated model yet: Coming soon, and the supported list
  unknown: (o = {}) => snapshot(Object.assign({ gpus: [gpu({ hw: "", name: "NVIDIA RTX 2080 Ti", vramGb: 11, usedMiB: 400, tempC: 40 })] }, o)),
  // nothing to run on at all
  bare: (o = {}) => snapshot(Object.assign({ gpus: [] }, o)),
  // setup: the machine cannot start a model yet
  setup: (o = {}) => snapshot(Object.assign({ gpus: [NINJA], readiness: { state: "needs-setup", message: "Docker access for your account is off" } }, o)),
  dockerDown: (o = {}) => snapshot(Object.assign({ gpus: [NINJA], readiness: { state: "docker-down", message: "Docker is not answering" } }, o)),
  unsupported: (o = {}) => snapshot(Object.assign({ gpus: [NINJA], readiness: { state: "unsupported", message: "Omarchy's Sudoless Docker helper is missing" } }, o)),
}

// ---------------------------------------------------------------- every screen

const R3090 = recipe("rtx-3090-24gb", 0), RCPU = recipe("x86-64-avx2-cpu", 0)
const ID3090 = R3090.id, IDCPU = RCPU.id
const IDLONG = RECIPES.hardware["rtx-3090-24gb"].recipes.map((r) => r.id).filter((x) => x.length > 34).pop()
const IDFLASH = RECIPES.hardware["rtx-3090-24gb"].recipes.map((r) => r.id).filter((x) => /offload/.test(x))[0]

// One case is one screen: a machine, the ui state the panel is in, and what that screen is for. `expect`
// is the first row type the view must carry, so build.mjs fails if a screen stops rendering as designed.
export const CASES = [
  // ------------------------------------------------------------ home
  { id: "home-life", group: "Home", note: "your lifetime, then the model running on the card", view: "home", snap: MACHINES.desktop() },
  { id: "home-first-run", group: "Home", note: "a machine that has never run a model: no lifetime, so the grid is absent", view: "home",
    snap: MACHINES.desktop({ life: life({ requests: 0, days: [] }) }), expect: "run" },
  { id: "home-starting", group: "Home", note: "starting: the card breathes, and the progress line is up", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "starting", detail: "starting the engine", percent: 24 })] }) },
  { id: "home-download", group: "Home", note: "downloading: the percent is in the line, not beside it", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "download", detail: "downloading 9.4 / 13.8 GB", percent: 68 })] }) },
  { id: "home-stopping", group: "Home", note: "stopping: Stop is already gone, so nothing can be pressed twice", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "stopping", detail: "stopping" })] }) },
  { id: "home-crashed", group: "Home", note: "a crash on a card: the row is framed in dashes, with run again and dismiss", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "error", error: "the engine stopped" })] }) },
  { id: "home-crashed-lost", group: "Home", note: "a crash on a card no row shows: it gets a row of its own", view: "home",
    snap: MACHINES.bare({ deployments: [deploy(R3090, { state: "error", error: "stopped unexpectedly" })] }) },
  { id: "home-shared", group: "Home", note: "shared on the tailnet: the card carries the reach and its port", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { shared: "https://machine.example.ts.net:12434" })] }) },
  { id: "home-free", group: "Home", note: "a free card: it offers the model validated for it, and Config", view: "home",
    snap: MACHINES.free() },
  { id: "home-held", group: "Home", note: "a card another program holds: the row says so and offers Config", view: "home", snap: MACHINES.held() },
  { id: "home-two-cards", group: "Home", note: "two kinds: a row each, then the fields and Refresh models", view: "home", snap: MACHINES.mixed() },
  { id: "home-cpu", group: "Home", note: "a CPU model: RAM free is a field, and the card row says RAM", view: "home", snap: MACHINES.cpu() },
  { id: "home-soon-unknown", group: "Home", note: "a card with no validated model: the square wave and the supported list", view: "home", snap: MACHINES.unknown() },
  { id: "home-soon-bare", group: "Home", note: "no card at all: the same line, with nothing to name", view: "home", snap: MACHINES.bare() },
  { id: "home-setup", group: "Home", note: "needs-setup: one button, and a model already running stays reachable", view: "home", snap: MACHINES.setup() },
  { id: "home-setup-running", group: "Home", note: "needs-setup with a model running: its card stays, so it can still be opened or stopped", view: "home",
    snap: MACHINES.setup({ deployments: [deploy(R3090)] }) },
  { id: "home-docker-down", group: "Home", note: "docker-down: no button, and it clears by itself", view: "home", snap: MACHINES.dockerDown() },
  { id: "home-unsupported", group: "Home", note: "unsupported: no button, and it clears when Omarchy updates", view: "home", snap: MACHINES.unsupported() },
  { id: "home-error", group: "Home", note: "an action failed: the reason is the first row, above everything", view: "home",
    snap: MACHINES.desktop(), ui: { problem: "Could not open the agent terminal; try again." }, expect: "error" },
  { id: "home-poll-error", group: "Home", note: "a poll failed: the panel says it is retrying rather than looking empty", view: "home",
    snap: MACHINES.desktop(), ui: { pollProblem: "Could not refresh Local AI; retrying." }, expect: "error" },
  { id: "home-setup-error", group: "Home", note: "a setup that did not finish: the panel carries the reason", view: "home",
    snap: MACHINES.desktop({ setupError: "setup did not finish" }), expect: "error" },
  { id: "home-notice", group: "Home", note: "a notice: the registry's own line, with no buttons", view: "home",
    snap: MACHINES.desktop(), ui: { notice: "models up to date · 12345678" }, expect: "links" },
  { id: "home-refreshing", group: "Home", note: "a refresh in flight: Refresh models is disabled, not gone", view: "home",
    snap: MACHINES.desktop(), ui: { registryBusy: true } },
  { id: "home-long-note", group: "Home", note: "a long row note against a short card name: it must elide, not wrap over", view: "home",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "starting", detail: "verifying turboderp--Qwen3.8-27B-exl3-3.00bpw@6fe61ad620ab/.verified, 41 of 84 files" })] }) },

  // ------------------------------------------------------------ a running model's page
  { id: "run-ready", group: "Model page", note: "ready: the figures, the card list, the agent, the folder, Reach, Weights", view: "run", id2: ID3090, snap: MACHINES.desktop() },
  { id: "run-choice-moved", group: "Model page", note: "another model chosen: the check moves, and its context and format are on the page", view: "run", id2: ID3090, snap: MACHINES.desktop(), ui: { model: IDLONG } },
  { id: "run-cpu", group: "Model page", note: "a CPU model: no memory bar, and one card row that says RAM", view: "run", id2: IDCPU,
    snap: MACHINES.cpu({ deployments: [deploy(RCPU, { keys: ["cpu"], agent: "claude", port: 12435 })] }) },
  { id: "run-offload", group: "Model page", note: "a model that keeps experts in RAM: it fits here, and says how much it takes besides the card", view: "run", id2: IDFLASH,
    snap: MACHINES.desktop({ deployments: [] }) },
  { id: "run-offload-unfit", group: "Model page", note: "the same model on a machine that lacks the RAM: it says what it needs and cannot be chosen", view: "kind", id2: "rtx-3090-24gb",
    snap: MACHINES.offload({ deployments: [] }), ui: { model: IDFLASH } },
  { id: "run-starting", group: "Model page", note: "starting: the progress line, Stop, and the reach already there", view: "run", id2: ID3090,
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "starting", detail: "loading weights", percent: 42 })] }) },
  { id: "run-failed", group: "Model page", note: "a failure: the reason, run again, logs, dismiss", view: "run", id2: ID3090,
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "error", error: "the engine stopped" })] }) },
  { id: "run-agent-open", group: "Model page", note: "the agent list, opened: every installed agent, and the one chosen", view: "run", id2: ID3090,
    snap: MACHINES.desktop(), ui: { open: "agent" } },
  { id: "run-folder-open", group: "Model page", note: "the folder list, opened", view: "run", id2: ID3090, snap: MACHINES.desktop(), ui: { open: "folder" } },
  { id: "run-secret", group: "Model page", note: "a shared tailnet value: hidden, small, with copy beside it", view: "run", id2: ID3090,
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { shared: "https://machine.example.ts.net:12434" })] }) },
  { id: "run-no-tailnet", group: "Model page", note: "no tailnet: Reach carries the machine only", view: "run", id2: ID3090,
    snap: MACHINES.desktop({ tailnet: "" }) },
  { id: "run-no-weights", group: "Model page", note: "no weights section when the recipe carries none", view: "run", id2: IDCPU,
    snap: MACHINES.cpu({ deployments: [deploy(RCPU, { keys: ["cpu"] })] }) },

  // ------------------------------------------------------------ a card kind's page
  { id: "kind-free", group: "Models page", note: "the models validated for the card, the recommended one checked, Run", view: "kind", id2: "rtx-3090-24gb",
    snap: MACHINES.free() },
  { id: "kind-long", group: "Models page", note: "a deliberately long model name against its fit: the two must not overlap", view: "kind", id2: "rtx-3090-24gb",
    snap: MACHINES.free(), ui: { model: IDLONG } },
  { id: "kind-unfit", group: "Models page", note: "a model this machine cannot run: what it lacks, and it cannot be chosen", view: "kind", id2: "rtx-3090-24gb",
    snap: MACHINES.offload({ deployments: [] }), ui: { model: IDFLASH } },
  { id: "kind-taken", group: "Models page", note: "the card another program holds: the card row says so", view: "kind", id2: "rtx-3090-24gb", snap: MACHINES.held() },
  { id: "kind-intel", group: "Models page", note: "Intel: a card that does not report its memory in use", view: "kind", id2: "intel-arc-pro-b70-32gb",
    snap: MACHINES.b70({ deployments: [] }) },
  { id: "kind-cpu", group: "Models page", note: "the CPU kind: its own model, and its own section name", view: "kind", id2: "x86-64-avx2-cpu",
    snap: MACHINES.cpu({ deployments: [] }) },
  { id: "kind-busy", group: "Models page", note: "the card is running a model: Config still opens, so it can be set up too", view: "kind", id2: "rtx-3090-24gb",
    snap: MACHINES.desktop({ extraGroups: [GROUP2] }) },

  // ------------------------------------------------------------ a group of cards
  { id: "group-free", group: "Group page", note: "one model across several free cards, and the cards it would run on", view: "group", id2: "rtx-3090-24gb", key: "2", snap: MACHINES.group() },
  { id: "group-none", group: "Group page", note: "fewer free cards than the group needs: groupView returns null, so the page falls back to Home", view: "group", id2: "rtx-3090-24gb", key: "4", snap: MACHINES.group(), expect: "life" },

  // ------------------------------------------------------------ every card on the machine
  { id: "gpus-mixed", group: "Hardware page", note: "every card: the same rows as home's, so any of them opens to Config", view: "gpus", snap: MACHINES.mixed() },
  { id: "gpus-open", group: "Hardware page", view: "gpus", ui: { open: "gpu:nvidia:0" }, snap: MACHINES.mixed(),
    note: "a card opened: the comparison, so every model it can run is under it" },
  { id: "gpus-open-running", group: "Hardware page", view: "gpus", ui: { open: "gpu:nvidia:0" }, snap: MACHINES.held(),
    note: "a card another program holds: it says so, and its models are still listed" },
  { id: "gpus-one", group: "Hardware page", note: "one card: a section name and a single row", view: "gpus", snap: MACHINES.desktop() },
  { id: "gpus-cpu", group: "Hardware page", note: "the CPU backend: the section is named HARDWARE, not GPUS", view: "gpus", snap: MACHINES.cpu() },
  { id: "gpus-unknown", group: "Hardware page", note: "a card with no validated model: it offers the supported list", view: "gpus", snap: MACHINES.unknown() },
  { id: "gpus-empty", group: "Hardware page", note: "no card at all: a section name, and nothing under it", view: "gpus", snap: MACHINES.bare() },
  { id: "gpus-open", group: "Hardware page", note: "a row opened: its memory, what there is to know, Config", view: "gpus",
    snap: MACHINES.desktop(), ui: { open: "gpu:nvidia:0" } },
  { id: "gpus-crashed", group: "Hardware page", note: "a crash: the row is framed in dashes, with run again and dismiss", view: "gpus",
    snap: MACHINES.desktop({ deployments: [deploy(R3090, { state: "error", error: "the engine stopped" })] }) },

  // ------------------------------------------------------------ the agents page
  // The settings page does not exist in Model.js yet, so this case names the proposal that draws it: a case
  // may declare `propose`, and build.mjs applies that patch before rendering, the same way the app does.
  { id: "settings", group: "Pages", view: "settings", propose: "settings", from: { view: "kind", id: "rtx-3090-24gb" },
    snap: MACHINES.desktop(), expect: "sec", note: "how a model runs, on a page of its own" },

  { id: "agents-default", group: "Agents page", note: "the default agent, the folder, and every agent to choose", view: "agents", snap: MACHINES.desktop() },
  { id: "agents-open", group: "Agents page", note: "the list opened: Selected on the default, Select on the rest", view: "agents", snap: MACHINES.desktop(), ui: { open: "agent" } },
  { id: "agents-updating", group: "Agents page", note: "an update in flight: Update is disabled and says Updating", view: "agents", snap: MACHINES.desktop(), ui: { updatingAgent: "claude" } },
  { id: "agents-none", group: "Agents page", note: "no agent installed: Choose an agent", view: "agents", snap: MACHINES.desktop({ agents: [] }) },
  { id: "agents-subset", group: "Agents page", note: "only the agents this machine has: a shorter list, no blanks", view: "agents",
    snap: MACHINES.desktop({ agents: ["pi", "claude", "codex"] }), ui: { open: "agent" } },
]
