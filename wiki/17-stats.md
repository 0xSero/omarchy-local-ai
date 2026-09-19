# 17 — Stats

There is no server and no client-side telemetry, so every number on this page comes from GitHub's
own APIs. The daily `traffic` workflow (`.github/workflows/traffic.yml`) reads them once at 03:17
UTC, writes them to the **`stats`** branch (never `main`), and this page reads that branch's
`summary.json` in your browser. Nothing here is generated at build time: the static page fetches the
current numbers when it is opened, so it never goes stale behind a deploy.

GitHub itself only keeps clone/view traffic and the referrer/path breakdown for **14 days**, and the
breakdown is a rolling snapshot with no per-day buckets. The workflow therefore records all of it
daily, and the `stats` branch is the only lasting record. `stats/traffic/summary.json` is the single
aggregated file this page renders; the raw per-day files sit beside it.

## Live counters

<div id="stats-live">
  <p id="stats-status">Loading live counters from the <code>stats</code> branch…</p>
</div>

<script>
(function () {
  var RAW = "https://raw.githubusercontent.com/0xSero/omarchy-local-ai/stats/traffic/summary.json";
  var el = document.getElementById("stats-live");
  function esc(v) {
    return String(v === null || v === undefined ? "—" : v).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function table(head, rows) {
    return "<table><thead><tr>" +
      head.map(function (h) { return "<th>" + esc(h) + "</th>"; }).join("") +
      "</tr></thead><tbody>" +
      rows.map(function (r) {
        return "<tr>" + r.map(function (c) { return "<td>" + esc(c) + "</td>"; }).join("") + "</tr>";
      }).join("") + "</tbody></table>";
  }
  function h(t) { return "<h3>" + esc(t) + "</h3>"; }
  function day(d) { return d ? String(d).slice(0, 10) : "—"; }
  function render(s) {
    var r = s.repo || {}, c = s.clones || {}, v = s.views || {}, st = s.stars || {},
        d = s.downloads || {}, i = s.interactions || {};
    var out = "<p>Last recorded <strong>" + esc(s.updated) + "</strong> (UTC). Numbers before that " +
      "date are settled; the last day or two are revised by GitHub as they age, and the newest reading wins.</p>";

    out += h("Installs and views");
    out += table(["Counter", "Total", "Days", "First", "Last", "Peak day", "Peak", "Uniques (14d)"], [
      ["Installs (clones)", c.total, c.days, c.first, c.last, c.peak_day, c.peak, c.uniques_14d],
      ["Views", v.total, v.days, v.first, v.last, v.peak_day, v.peak, v.uniques_14d]
    ]);
    out += "<p>Every <code>omarchy plugin add</code> is a clone, so the clone column is the closest " +
      "thing to an install count. \"Uniques\" is GitHub's rolling 14-day window, the only unique " +
      "figure it exposes for traffic.</p>";

    out += h("Downloads");
    var rel = (d.by_release || []).map(function (x) {
      return [x.tag, x.name, day(x.published), x.downloads,
        (x.assets || []).map(function (a) { return a.name + " (" + a.downloads + ")"; }).join(", ")];
    });
    out += table(["Release", "Name", "Published", "Downloads", "Assets"], rel);
    out += "<p><strong>" + esc(d.total) + "</strong> asset downloads across " + esc(d.release_count) +
      " releases; latest release <strong>" + esc(d.latest) + "</strong>. These are the release " +
      "archives from <code>make bundle</code>, counted by GitHub's own <code>download_count</code>.</p>";

    out += h("Stars and repository");
    out += table(["Reading", "Value"], [
      ["Stars now", r.stars],
      ["Stars first recorded", st.first_count],
      ["Stars gained since", st.gained + " (since " + day(st.first) + ")"],
      ["Forks", r.forks],
      ["Watchers (REST subscribers)", r.watchers],
      ["Open issues and PRs", r.open_issues],
      ["Repository size", r.size_kb + " kB"]
    ]);
    out += "<p>The star timeline is not paginated from stargazers: the workflow archives each day's " +
      "repo snapshot with its date, so <code>traffic/stars-daily.json</code> is the series.</p>";

    out += h("GitHub interactions");
    var is = i.issues || {}, pr = i.pull_requests || {};
    out += table(["Metric", "Value"], [
      ["Stars (GraphQL)", i.stars],
      ["Forks (GraphQL)", i.forks],
      ["Watchers (GraphQL)", i.watchers],
      ["Issues", is.total + " total · " + is.open + " open · " + is.closed + " closed"],
      ["Pull requests", pr.total + " total · " + pr.open + " open · " + pr.merged + " merged · " + pr.closed + " closed"],
      ["Discussions", i.discussions],
      ["Commits on " + esc(i.default_branch), i.commits]
    ]);
    out += "<p>One GraphQL call, recorded daily with the date in the file " +
      "(<code>traffic/interactions." + esc(i.day) + ".json</code>).</p>";

    out += h("Where the traffic comes from");
    out += table(["Referrer", "Views", "Uniques"], (s.referrers || []).map(function (x) {
      return [x.referrer, x.count, x.uniques];
    }));
    out += h("Most-viewed paths");
    out += table(["Path", "Views", "Uniques"], (s.paths || []).map(function (x) {
      return [x.title, x.count, x.uniques];
    }));
    out += "<p>Both breakdowns are GitHub's rolling 14-day snapshot, re-recorded whole each day.</p>";
    el.innerHTML = out;
  }
  function fail(err) {
    el.innerHTML = "<p><strong>Live counters are unavailable right now.</strong> The page reads " +
      "<code>" + esc(RAW) + "</code> directly; if that request fails (offline, or a browser that " +
      "blocks cross-origin fetches) nothing is broken — the numbers still exist and can be read " +
      "straight from the file. Raw data: " +
      "<a href=\"https://github.com/0xSero/omarchy-local-ai/tree/stats/traffic\">" +
      "github.com/0xSero/omarchy-local-ai/tree/stats/traffic</a>. " +
      "The workflow ran into: <code>" + esc(err) + "</code></p>";
  }
  fetch(RAW, { cache: "no-store" })
    .then(function (res) { if (!res.ok) throw new Error("HTTP " + res.status); return res.json(); })
    .then(render)
    .catch(function (e) { fail(e && e.message ? e.message : e); });
})();
</script>

## What is recorded, and where

Everything lives on the `stats` branch, written only by the daily workflow, and every file it writes
is listed in [15 — Registry and CI](15-registry-and-ci.md). `traffic/summary.json` is the one file this
page reads: the totals, both traffic spans, the star timeline, the download tally per release and
asset, the day's interaction counts, and the rolling referrer and path breakdowns. Each per-day file is
rewritten in place on a re-run, and the aggregations keep the **maximum** reading of a day, so a
revision by GitHub corrects rather than duplicates. `main` is never touched by that workflow.

## Reading the raw data

The dashboard is only a rendering. The file behind it is small and plain:

```bash
curl -s https://raw.githubusercontent.com/0xSero/omarchy-local-ai/stats/traffic/summary.json | jq .
# the per-day series, straight from the branch
gh api repos/0xSero/omarchy-local-ai/contents/traffic/clones-daily.json?ref=stats --jq .content | base64 -d | jq .
```

No secret is needed to read it, no third party is involved, and there is nothing to opt out of:
these are GitHub's own counts of GitHub's own repository, recorded before the 14-day window drops
them.