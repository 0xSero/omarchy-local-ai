// Counts Local AI installs. The plugin sends, at most twice a day:
//   POST /v1/local-ai/ping  {"id": "<32 hex>", "version": "6.15.0", "hw": ["rtx-3090"], "running": 1,
//                            "launched": true, "actions": {"started": 2, "failed": 0, "opened": 1, "downloaded": 1}}
// `id` is random, made by the plugin on first run. `actions` are totals since the install's last delivered ping, never
// which model or agent; versions before 6.15.0 send neither field. Only those fields and the UTC day are stored: no IP
// address, no user agent, no headers. The caller's address is used only by the in-memory rate limit, never written.
//   GET /v1/local-ai/stats  aggregate counts, public
//   GET /                   the dashboard (src/page.html), which reads the stats above and the plugin's GitHub traffic
import PAGE from "./page.html";
const ID = /^[0-9a-f]{32}$/;
const VERSION = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/;
const HW = /^[a-z0-9][a-z0-9-]{0,47}$/;
const DAY = 86400000;
const ACTIONS = ["started", "failed", "opened", "downloaded"];

// Every response: no sniffing, no referrer, HTTPS only, never framed.
const SECURE = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "strict-transport-security": "max-age=31536000; includeSubDomains",
  "x-frame-options": "DENY",
  "permissions-policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
};
// Only the stats are read by browsers on other sites; the ping is sent by the plugin, never by a page.
const json = (body, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...SECURE, ...headers },
  });

// The dashboard may run only its own inline script (by hash, worked out once per isolate) and read only this worker
// and the plugin's traffic files.
let csp;
async function policy() {
  if (csp) return csp;
  const script = PAGE.match(/<script>([\s\S]*?)<\/script>/)[1];
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(script));
  const hash = btoa(String.fromCharCode(...new Uint8Array(digest)));
  csp = [
    "default-src 'none'",
    `script-src 'sha256-${hash}'`,
    "style-src 'unsafe-inline'",
    "img-src 'self' data:",
    "connect-src 'self' https://raw.githubusercontent.com",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
  return csp;
}
const day = (offset = 0) => new Date(Date.now() - offset * DAY).toISOString().slice(0, 10);

function valid(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const { id, version, hw = [], running = 0, launched = false, actions = {} } = body;
  if (typeof id !== "string" || !ID.test(id)) return null;
  if (typeof version !== "string" || !VERSION.test(version)) return null;
  if (!Array.isArray(hw) || hw.length > 8 || !hw.every((h) => typeof h === "string" && HW.test(h))) return null;
  if (!Number.isInteger(running) || running < 0 || running > 64) return null;
  if (typeof launched !== "boolean") return null;
  if (!actions || typeof actions !== "object" || Array.isArray(actions)) return null;
  for (const [k, v] of Object.entries(actions)) {
    if (!ACTIONS.includes(k) || !Number.isInteger(v) || v < 0 || v > 1000) return null;
  }
  const a = Object.fromEntries(ACTIONS.map((k) => [k, actions[k] ?? 0]));
  return { id, version, hw: [...new Set(hw)].sort().join(","), running, launched: launched ? 1 : 0, ...a };
}

async function ping(request, env) {
  const ip = request.headers.get("cf-connecting-ip");
  if (!ip) return json({ error: "no address" }, 400);
  const { success } = await env.LIMIT.limit({ key: ip });
  if (!success) return json({ error: "slow down" }, 429);
  if (!(request.headers.get("content-type") || "").startsWith("application/json")) return json({ error: "send JSON" }, 415);
  // refuse a large body before reading it, then check what was actually sent
  if (Number(request.headers.get("content-length") || 0) > 1024) return json({ error: "too large" }, 413);
  const text = await request.text();
  if (text.length > 1024) return json({ error: "too large" }, 413);
  let body;
  try {
    body = valid(JSON.parse(text));
  } catch {
    body = null;
  }
  if (!body) return json({ error: "invalid ping" }, 400);
  await env.DB.prepare(
    `INSERT INTO pings (day, id, version, hw, running, launched, started, failed, opened, downloaded)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
     ON CONFLICT (day, id) DO UPDATE SET version = excluded.version, hw = excluded.hw,
       running = MAX(pings.running, excluded.running), launched = MAX(pings.launched, excluded.launched),
       started = pings.started + excluded.started, failed = pings.failed + excluded.failed,
       opened = pings.opened + excluded.opened, downloaded = pings.downloaded + excluded.downloaded`,
  ).bind(day(), body.id, body.version, body.hw, body.running, body.launched,
    body.started, body.failed, body.opened, body.downloaded).run();
  return new Response(null, { status: 204 });
}

function tally(rows, key) {
  const out = {};
  for (const row of rows) for (const k of key(row)) out[k] = (out[k] || 0) + 1;
  return Object.fromEntries(Object.entries(out).sort((a, b) => b[1] - a[1]));
}

async function stats(env) {
  // launched: ran a model here, ever: a model has answered on it (6.15.0+), a start finished, or one ran at a check-in
  const [totals, daily, latest] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(DISTINCT id) AS installs,
         COUNT(DISTINCT CASE WHEN day = ?1 THEN id END) AS today,
         COUNT(DISTINCT CASE WHEN day >= ?2 THEN id END) AS week,
         COUNT(DISTINCT CASE WHEN day >= ?3 THEN id END) AS month,
         COUNT(DISTINCT CASE WHEN day >= ?3 AND running > 0 THEN id END) AS monthRunning,
         COUNT(DISTINCT CASE WHEN launched > 0 OR started > 0 OR running > 0 THEN id END) AS launched,
         COUNT(DISTINCT CASE WHEN day >= ?3 AND (started > 0 OR opened > 0 OR running > 0) THEN id END) AS monthUsed,
         COALESCE(SUM(CASE WHEN day >= ?3 THEN started END), 0) AS monthStarted,
         COALESCE(SUM(CASE WHEN day >= ?3 THEN failed END), 0) AS monthFailed,
         COALESCE(SUM(CASE WHEN day >= ?3 THEN opened END), 0) AS monthOpened,
         COALESCE(SUM(CASE WHEN day >= ?3 THEN downloaded END), 0) AS monthDownloaded
       FROM pings`,
    ).bind(day(), day(6), day(29)),
    env.DB.prepare(
      `WITH first AS (SELECT id, MIN(day) AS d FROM pings GROUP BY id)
       SELECT p.day AS day, COUNT(*) AS active, SUM(p.running > 0) AS running, SUM(f.d = p.day) AS new,
         SUM(p.started) AS started, SUM(p.failed) AS failed, SUM(p.opened) AS opened
       FROM pings p JOIN first f ON f.id = p.id WHERE p.day >= ?1 GROUP BY p.day ORDER BY p.day`,
    ).bind(day(89)),
    // each install's newest ping of the last 7 days
    env.DB.prepare(
      `SELECT version, hw FROM pings p WHERE day >= ?1
         AND day = (SELECT MAX(day) FROM pings q WHERE q.id = p.id AND q.day >= ?1)`,
    ).bind(day(6)),
  ]);
  const rows = latest.results;
  return {
    updated: new Date().toISOString(),
    installs: totals.results[0],
    daily: daily.results,
    week: {
      versions: tally(rows, (r) => [r.version]),
      hardware: tally(rows, (r) => (r.hw ? r.hw.split(",") : ["none"])),
    },
  };
}

export default {
  async fetch(request, env, ctx) {
    try {
      return await route(request, env, ctx);
    } catch {
      // nothing about the database or the code reaches the caller
      return json({ error: "unavailable" }, 503);
    }
  },
};

async function route(request, env, ctx) {
  const { pathname } = new URL(request.url);
  if (pathname === "/v1/local-ai/ping") {
    return request.method === "POST" ? ping(request, env) : json({ error: "use POST" }, 405);
  }
  if (pathname === "/v1/local-ai/stats" && request.method === "GET") {
    const cache = caches.default;
    const key = new Request(new URL(pathname, request.url));
    const hit = await cache.match(key);
    if (hit) return hit;
    const response = json(await stats(env), 200, { "cache-control": "public, max-age=300", "access-control-allow-origin": "*" });
    ctx.waitUntil(cache.put(key, response.clone()));
    return response;
  }
  if (pathname === "/" && request.method === "GET") {
    return new Response(PAGE, {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300",
        "content-security-policy": await policy(), ...SECURE },
    });
  }
  return json({ error: "not found" }, 404);
}
