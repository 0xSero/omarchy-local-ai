// Counts Local AI installs. The plugin sends, at most twice a day:
//   POST /v1/local-ai/ping  {"id": "<32 hex>", "version": "6.13.0", "hw": ["rtx-3090"], "running": 1}
// `id` is random, made by the plugin on first run. Only those four fields and the UTC day are stored: no IP address,
// no user agent, no headers. The caller's address is used only by the in-memory rate limit, never written.
//   GET /v1/local-ai/stats  aggregate counts, public
const ID = /^[0-9a-f]{32}$/;
const VERSION = /^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$/;
const HW = /^[a-z0-9][a-z0-9-]{0,47}$/;
const DAY = 86400000;

const json = (body, status = 200, headers = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "access-control-allow-origin": "*", ...headers },
  });
const day = (offset = 0) => new Date(Date.now() - offset * DAY).toISOString().slice(0, 10);

function valid(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const { id, version, hw = [], running = 0 } = body;
  if (typeof id !== "string" || !ID.test(id)) return null;
  if (typeof version !== "string" || !VERSION.test(version)) return null;
  if (!Array.isArray(hw) || hw.length > 8 || !hw.every((h) => typeof h === "string" && HW.test(h))) return null;
  if (!Number.isInteger(running) || running < 0 || running > 64) return null;
  return { id, version, hw: [...new Set(hw)].sort().join(","), running };
}

async function ping(request, env) {
  const ip = request.headers.get("cf-connecting-ip");
  if (!ip) return json({ error: "no address" }, 400);
  const { success } = await env.LIMIT.limit({ key: ip });
  if (!success) return json({ error: "slow down" }, 429);
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
    `INSERT INTO pings (day, id, version, hw, running) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT (day, id) DO UPDATE SET version = excluded.version, hw = excluded.hw,
       running = MAX(pings.running, excluded.running)`,
  ).bind(day(), body.id, body.version, body.hw, body.running).run();
  return new Response(null, { status: 204 });
}

function tally(rows, key) {
  const out = {};
  for (const row of rows) for (const k of key(row)) out[k] = (out[k] || 0) + 1;
  return Object.fromEntries(Object.entries(out).sort((a, b) => b[1] - a[1]));
}

async function stats(env) {
  const [totals, daily, latest] = await env.DB.batch([
    env.DB.prepare(
      `SELECT COUNT(DISTINCT id) AS installs,
         COUNT(DISTINCT CASE WHEN day = ?1 THEN id END) AS today,
         COUNT(DISTINCT CASE WHEN day >= ?2 THEN id END) AS week,
         COUNT(DISTINCT CASE WHEN day >= ?3 THEN id END) AS month,
         COUNT(DISTINCT CASE WHEN day >= ?3 AND running > 0 THEN id END) AS monthRunning
       FROM pings`,
    ).bind(day(), day(6), day(29)),
    env.DB.prepare(
      `WITH first AS (SELECT id, MIN(day) AS d FROM pings GROUP BY id)
       SELECT p.day AS day, COUNT(*) AS active, SUM(p.running > 0) AS running, SUM(f.d = p.day) AS new
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
    const { pathname } = new URL(request.url);
    if (pathname === "/v1/local-ai/ping") {
      return request.method === "POST" ? ping(request, env) : json({ error: "use POST" }, 405);
    }
    if (pathname === "/v1/local-ai/stats" && request.method === "GET") {
      const cache = caches.default;
      const key = new Request(new URL(pathname, request.url));
      const hit = await cache.match(key);
      if (hit) return hit;
      const response = json(await stats(env), 200, { "cache-control": "public, max-age=300" });
      ctx.waitUntil(cache.put(key, response.clone()));
      return response;
    }
    return json({ error: "not found" }, 404);
  },
};
