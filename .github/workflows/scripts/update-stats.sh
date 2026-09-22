#!/usr/bin/env bash

set -euo pipefail

# Reads Playwright JSON results from downloaded-results/ and shell test JUnit XML,
# updates site/stats/runs.json with a rolling 30-day window, and regenerates
# site/stats/index.html with a failure/flakiness dashboard.
#
# Required env vars:
#   GITHUB_RUN_NUMBER   - GitHub Actions run number
#   GITHUB_RUN_ID       - GitHub Actions run ID
#   GITHUB_SERVER_URL   - e.g. "https://github.com"
#   GITHUB_REPOSITORY   - e.g. "org/repo"
# Optional env vars:
#   SHELL_TESTS_XML     - path to JUnit XML from shell unit tests

RESULTS_DIR="${RESULTS_DIR:-downloaded-results}"
SITE_DIR="${SITE_DIR:-site}"

mkdir -p "${SITE_DIR}/stats"

python3 - <<PYEOF
import json, os, glob, sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo

results_dir     = os.environ.get("RESULTS_DIR", "downloaded-results")
site_dir        = os.environ.get("SITE_DIR", "site")
shell_tests_xml = os.environ.get("SHELL_TESTS_XML", "")
run_number      = os.environ.get("GITHUB_RUN_NUMBER", "0")
run_url         = "{}/{}/actions/runs/{}".format(
    os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
    os.environ.get("GITHUB_REPOSITORY", ""),
    os.environ.get("GITHUB_RUN_ID", "0"),
)
cutoff = datetime.now(timezone.utc) - timedelta(days=30)


def walk_suites(suite, parents, failed_tests, flaky_tests):
    suite_title = suite.get("title", "")
    cur = parents + ([suite_title] if suite_title else [])
    for spec in suite.get("specs", []):
        spec_title = spec.get("title", "")
        full_title = " > ".join(cur + [spec_title]) if spec_title else " > ".join(cur)
        file_path  = spec.get("file", "")
        for test in spec.get("tests", []):
            status = test.get("status", "")
            if status == "unexpected":
                errors = []
                for result in test.get("results", []):
                    for err in result.get("errors", []):
                        msg = err.get("message", "") or err.get("value", "")
                        if msg:
                            errors.append(msg[:300])
                failed_tests.append({
                    "title": full_title,
                    "file": file_path,
                    "error": errors[0] if errors else "",
                })
            elif status == "flaky":
                flaky_tests.append({
                    "title": full_title,
                    "file": file_path,
                    "attempts": len(test.get("results", [])),
                })
    for sub in suite.get("suites", []):
        walk_suites(sub, cur, failed_tests, flaky_tests)


all_json_files = sorted(glob.glob(os.path.join(results_dir, "*.json")))
print(f"[stats] Found {len(all_json_files)} result file(s) in {results_dir!r}")

agg = {"expected": 0, "unexpected": 0, "flaky": 0, "skipped": 0}
failed_tests = []
flaky_tests  = []

for json_file in all_json_files:
    try:
        with open(json_file) as f:
            data = json.load(f)
    except Exception as e:
        print(f"[stats] Skipping {json_file}: {e}", file=sys.stderr)
        continue
    raw = data.get("stats", {})
    for k in agg:
        agg[k] += raw.get(k, 0)
    for suite in data.get("suites", []):
        walk_suites(suite, [], failed_tests, flaky_tests)

# ── Shell tests (JUnit XML) ─────────────────────────────────────────────────

shell_passed = 0
shell_failed = 0
shell_skipped = 0
shell_failed_tests = []

if shell_tests_xml and os.path.exists(shell_tests_xml):
    try:
        root = ET.parse(shell_tests_xml).getroot()
        suites = root.findall("testsuite") if root.tag == "testsuites" else [root]
        for suite in suites:
            suite_name = suite.get("name", "")
            for tc in suite.findall("testcase"):
                if tc.find("skipped") is not None:
                    shell_skipped += 1
                elif tc.find("failure") is not None or tc.find("error") is not None:
                    shell_failed += 1
                    elem = tc.find("failure") or tc.find("error")
                    msg = (elem.get("message", "") or elem.text or "")[:300]
                    shell_failed_tests.append({
                        "title": f"{suite_name} > {tc.get('name', '?')}",
                        "file":  tc.get("classname", ""),
                        "error": msg,
                    })
                else:
                    shell_passed += 1
        print(f"[stats] Shell tests: passed={shell_passed} failed={shell_failed} skipped={shell_skipped}")
        if shell_failed_tests:
            print(f"[stats] Shell test failures ({len(shell_failed_tests)}):")
            for t in shell_failed_tests:
                print(f"    - {t['title']}")
    except Exception as e:
        print(f"[stats] Could not parse shell tests XML {shell_tests_xml}: {e}", file=sys.stderr)
else:
    print(f"[stats] No shell tests XML provided — skipping")

run_entry = {
    "run_id":              run_number,
    "run_url":             run_url,
    "timestamp":           datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "total":               agg["expected"] + agg["unexpected"] + agg["flaky"] + agg["skipped"],
    "passed":              agg["expected"],
    "failed":              agg["unexpected"],
    "skipped":             agg["skipped"],
    "flaky_count":         agg["flaky"],
    "failed_tests":        failed_tests,
    "flaky_tests":         flaky_tests,
    "shell_passed":        shell_passed,
    "shell_failed":        shell_failed,
    "shell_skipped":       shell_skipped,
    "shell_failed_tests":  shell_failed_tests,
}
print(f"[stats] Run #{run_number}: playwright total={run_entry['total']} passed={run_entry['passed']} "
      f"failed={run_entry['failed']} flaky={run_entry['flaky_count']} skipped={run_entry['skipped']}")
if failed_tests:
    print(f"[stats] Failed tests ({len(failed_tests)}):")
    for t in failed_tests:
        print(f"    - {t['title']}")
if flaky_tests:
    print(f"[stats] Flaky tests ({len(flaky_tests)}):")
    for t in flaky_tests:
        print(f"    ~ {t['title']}")

stats_dir = os.path.join(site_dir, "stats")
os.makedirs(stats_dir, exist_ok=True)
runs_file = os.path.join(stats_dir, "runs.json")

if os.path.exists(runs_file):
    with open(runs_file) as f:
        store = json.load(f)
    prev_count = len(store.get("runs", []))
    print(f"[stats] Loaded existing runs.json: {prev_count} run(s) on record")
else:
    store = {"runs": []}
    prev_count = 0
    print(f"[stats] No existing runs.json — starting fresh")

store["runs"] = [
    r for r in store["runs"]
    if r.get("run_id") != run_number
    and datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")) >= cutoff
]
pruned = prev_count - len(store["runs"])
if pruned > 0:
    print(f"[stats] Pruned {pruned} run(s) (duplicate run_id or older than 30 days)")

store["runs"].append(run_entry)
store["runs"].sort(key=lambda r: r["timestamp"])

with open(runs_file, "w") as f:
    json.dump(store, f, indent=2)
print(f"[stats] runs.json updated: {len(store['runs'])} run(s) → {runs_file}")


# ── Dashboard helpers ───────────────────────────────────────────────────────

def is_all_failed_run(run):
    total   = run.get("total", 0)
    skipped = run.get("skipped", 0)
    executed = max(0, total - skipped)
    return executed > 0 and run.get("failed", 0) >= executed

def top_failing(runs, n=10):
    counts = {}
    for run in runs:
        if is_all_failed_run(run):
            continue
        for t in run.get("failed_tests", []):
            k = t["title"]
            counts[k] = counts.get(k, 0) + 1
    return sorted(counts.items(), key=lambda x: -x[1])[:n]

def flaky_counts(runs):
    eligible = [r for r in runs if not is_all_failed_run(r)]
    counts = {}
    for run in eligible:
        seen = set()
        for t in run.get("flaky_tests", []):
            k = t["title"]
            if k not in seen:
                counts[k] = counts.get(k, 0) + 1
                seen.add(k)
    # Cross-run intermittent failures
    fail_counts = {}
    for run in eligible:
        seen = set()
        for t in run.get("failed_tests", []):
            k = t["title"]
            if k not in seen:
                fail_counts[k] = fail_counts.get(k, 0) + 1
                seen.add(k)
    total = len(eligible)
    for k, c in fail_counts.items():
        if 0 < c < total:
            counts[k] = max(counts.get(k, 0), c)
    return sorted(counts.items(), key=lambda x: (-x[1], x[0]))

def short_name(title):
    parts = [p.strip() for p in title.split(">") if p.strip()]
    return parts[-1] if parts else title

def esc(s):
    return s.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;").replace(">", "&gt;")

# ── Build dashboard ─────────────────────────────────────────────────────────

runs      = store["runs"]
eligible  = [r for r in runs if not is_all_failed_run(r)]
top       = top_failing(runs, 10)
flaky     = flaky_counts(runs)

total_executed = sum(max(0, r.get("total", 0) - r.get("skipped", 0)) for r in eligible)
total_passed   = sum(r.get("passed", 0) + r.get("flaky_count", 0) for r in eligible)
total_failed   = sum(r.get("failed", 0) for r in eligible)
total_flaky    = sum(r.get("flaky_count", 0) for r in eligible)
avg_passed     = round(total_passed / max(1, len(eligible)), 1)
avg_total      = round(total_executed / max(1, len(eligible)), 1)
pass_rate      = round(100 * (1 - total_failed / max(1, sum(r.get("total", 0) for r in eligible))), 1)

shell_total_passed  = sum(r.get("shell_passed", 0) for r in eligible)
shell_total_failed  = sum(r.get("shell_failed", 0) for r in eligible)
shell_total_skipped = sum(r.get("shell_skipped", 0) for r in eligible)
shell_avg_passed    = round(shell_total_passed / max(1, len(eligible)), 1)
shell_avg_failed    = round(shell_total_failed / max(1, len(eligible)), 1)
shell_avg_total     = round((shell_total_passed + shell_total_failed + shell_total_skipped) / max(1, len(eligible)), 1)

# Top shell test failures across runs
shell_fail_counts = {}
for run in eligible:
    for t in run.get("shell_failed_tests", []):
        k = t["title"]
        shell_fail_counts[k] = shell_fail_counts.get(k, 0) + 1
top_shell = sorted(shell_fail_counts.items(), key=lambda x: -x[1])[:10]

rate_cls = "rate-ok" if pass_rate >= 90 else ("rate-warn" if pass_rate >= 70 else "rate-bad")

now_utc = datetime.now(timezone.utc)
now_de  = now_utc.astimezone(ZoneInfo("Europe/Berlin"))
updated_label = f"{now_de.strftime('%Y-%m-%d %H:%M %Z')} ({now_utc.strftime('%H:%M UTC')})"

dashboard = os.path.join(site_dir, "stats", "index.html")
with open(dashboard, "w") as fh:
    fh.write(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Test Statistics — StatsServiceBook</title>
<style>
*{{box-sizing:border-box}}
body{{font-family:system-ui,-apple-system,Arial,sans-serif;margin:0;background:#f0f2f5;color:#1a1a2e;min-height:100vh}}
.topbar{{background:#1a1a2e;color:#fff;padding:.75rem 2rem;display:flex;align-items:center;gap:1rem}}
.topbar a{{color:#93c5fd;text-decoration:none;font-size:.875rem}}
.topbar a:hover{{text-decoration:underline}}
.topbar-title{{font-weight:700;font-size:1rem;flex:1}}
.topbar-meta{{font-size:.78rem;color:#94a3b8}}
.page{{max-width:60rem;margin:0 auto;padding:1.5rem 2rem 3rem}}
.legend{{display:flex;flex-wrap:wrap;align-items:center;gap:.5rem 1.25rem;margin-bottom:1.25rem;padding:.75rem 1rem;background:#fff;border:1px solid #e2e8f0;border-radius:.625rem;font-size:.8rem;color:#475569}}
.legend-item{{display:inline-flex;align-items:center;gap:.375rem}}
.legend-note{{width:100%;color:#94a3b8;font-size:.75rem;margin-top:.2rem}}
.legend-swatch{{width:.75rem;height:.75rem;border-radius:2px;display:inline-block;flex-shrink:0;border:1px solid rgba(0,0,0,.1)}}
.sw-green{{background:#22c55e}}.sw-red{{background:#ef4444}}.sw-yellow{{background:#eab308}}
.sw-mixed{{background:linear-gradient(to top,#eab308 0%,#eab308 50%,#ef4444 50%)}}
.sw-black{{background:#1e293b}}
.card{{background:#fff;border:1px solid #e2e8f0;border-radius:.75rem;padding:1.25rem;margin-bottom:1.25rem;box-shadow:0 1px 3px rgba(0,0,0,.06)}}
.card-header{{display:flex;align-items:center;justify-content:space-between;margin-bottom:.875rem}}
.card-title{{font-size:1rem;font-weight:700;color:#1a1a2e;margin:0}}
.rate-pill{{font-size:.875rem;font-weight:700;padding:.2rem .65rem;border-radius:999px}}
.rate-ok{{background:#dcfce7;color:#15803d}}
.rate-warn{{background:#fef9c3;color:#854d0e}}
.rate-bad{{background:#fee2e2;color:#b91c1c}}
.stats-row{{display:grid;grid-template-columns:repeat(4,1fr);gap:.625rem;margin-bottom:.875rem}}
.stat-box{{background:#f8fafc;border:1px solid #e2e8f0;border-radius:.5rem;padding:.6rem .5rem;text-align:center}}
.stat-val{{font-size:1.15rem;font-weight:700;color:#1a1a2e;line-height:1.2}}
.stat-lbl{{font-size:.68rem;color:#94a3b8;text-transform:uppercase;letter-spacing:.05em;margin-top:.15rem}}
.stat-fail .stat-val{{color:#dc2626}}
.stat-flaky .stat-val{{color:#d97706}}
.spark-label{{font-size:.7rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#94a3b8;margin-bottom:.3rem}}
.sparkline{{height:72px;display:flex;align-items:flex-end;gap:3px;padding:.25rem 0;border-bottom:1px solid #f1f5f9;overflow:hidden;margin-bottom:.875rem}}
.sparkline a{{flex:0 0 auto;display:flex;align-items:flex-end}}
.bar{{width:7px;border-radius:2px 2px 0 0}}
.bar:hover{{opacity:.7}}
.section-lbl{{font-size:.7rem;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.06em;margin:.75rem 0 .35rem}}
table{{width:100%;border-collapse:collapse;font-size:.8rem}}
th{{text-align:left;padding:.3rem .4rem;color:#94a3b8;font-weight:600;border-bottom:2px solid #e2e8f0;font-size:.72rem;text-transform:uppercase;letter-spacing:.05em}}
td{{padding:.3rem .4rem;border-bottom:1px solid #f8fafc;word-break:break-word;color:#374151}}
td:last-child{{text-align:right;font-weight:700;color:#dc2626;white-space:nowrap}}
.flaky-list{{margin:.35rem 0 0;padding-left:1rem;font-size:.8rem;color:#374151}}
.flaky-list li{{margin:.2rem 0}}
.flaky-list strong{{color:#d97706}}
a{{color:#2563eb;text-decoration:none}}a:hover{{text-decoration:underline}}
.empty{{text-align:center;padding:4rem;color:#94a3b8}}
</style>
</head><body>
<div class="topbar">
  <span class="topbar-title">StatsServiceBook &middot; Test Statistics</span>
  <a href="../">&larr; All reports</a>
  <span class="topbar-meta">Last 30 days &middot; Updated {esc(updated_label)}</span>
</div>
<div class="page">
<div class="legend" aria-label="Sparkline legend">
  <span class="legend-item"><span class="legend-swatch sw-green"></span>All passed</span>
  <span class="legend-item"><span class="legend-swatch sw-red"></span>Failures</span>
  <span class="legend-item"><span class="legend-swatch sw-yellow"></span>Flaky only</span>
  <span class="legend-item"><span class="legend-swatch sw-mixed"></span>Failures + flaky</span>
  <span class="legend-item"><span class="legend-swatch sw-black"></span>All failed (excluded from stats)</span>
  <span class="legend-note">Bars: oldest &rarr; newest. Bar height = total tests run (Playwright + shell); color = pass/fail status. Cards sorted newest execution first.</span>
</div>
""")

    if not runs:
        fh.write('<div class="empty"><p>No statistics available yet.</p></div>\n')
    else:
        fh.write('<div class="card">\n')
        fh.write(f'<div class="card-header"><h2 class="card-title">Last 30 days &mdash; {len(runs)} run(s)</h2>')
        fh.write(f'<span class="rate-pill {rate_cls}">{pass_rate}% pass rate</span></div>\n')

        fh.write('<div class="section-lbl">Playwright tests</div>\n')
        fh.write('<div class="stats-row">\n')
        fh.write(f'<div class="stat-box"><div class="stat-val">{avg_total}</div><div class="stat-lbl">Avg tests/run</div></div>\n')
        fh.write(f'<div class="stat-box"><div class="stat-val">{avg_passed}</div><div class="stat-lbl">Avg passed/run</div></div>\n')
        fh.write(f'<div class="stat-box stat-fail"><div class="stat-val">{total_failed}</div><div class="stat-lbl">Total failures</div></div>\n')
        fh.write(f'<div class="stat-box stat-flaky"><div class="stat-val">{total_flaky}</div><div class="stat-lbl">Total flaky</div></div>\n')
        fh.write('</div>\n')

        max_total = max((r.get("total", 0) + r.get("shell_passed", 0) + r.get("shell_failed", 0) for r in runs), default=1) or 1
        fh.write('<div class="spark-label">Tests per run (Playwright + shell) — color shows pass/fail</div>\n')
        fh.write('<div class="sparkline" title="Total tests per run (oldest → newest)">')
        for run in runs:
            pw_failed   = run["failed"]
            pw_flaky    = run.get("flaky_count", 0)
            sh_failed   = run.get("shell_failed", 0)
            issues      = pw_failed + pw_flaky + sh_failed
            run_total   = run.get("total", 0) + run.get("shell_passed", 0) + sh_failed
            h           = max(8, round(60 * run_total / max_total))
            if is_all_failed_run(run):
                color = "#1e293b"
            elif issues == 0:
                color = "#22c55e"
            elif pw_failed > 0 and pw_flaky > 0:
                red_pct    = round(100 * pw_failed / issues, 1)
                yellow_pct = 100 - red_pct
                color = f"linear-gradient(to top,#eab308 0%,#eab308 {yellow_pct}%,#ef4444 {yellow_pct}%)"
            elif pw_failed > 0 or sh_failed > 0:
                color = "#ef4444"
            else:
                color = "#eab308"
            label = (
                f"Run #{run['run_id']} — "
                f"Playwright: {run.get('passed', 0)} passed / {pw_failed} failed / {pw_flaky} flaky / {run.get('skipped', 0)} skipped — "
                f"Shell: {run.get('shell_passed', 0)} passed / {sh_failed} failed"
            )
            fh.write(
                f'<a href="{esc(run["run_url"])}" target="_blank" title="{esc(label)}">'
                f'<div class="bar" style="height:{h}px;background:{color}"></div></a>'
            )
        fh.write('</div>\n')

        if top:
            fh.write('<div class="section-lbl">Top failing Playwright tests</div>\n')
            fh.write('<table><tr><th>Test</th><th style="width:4rem">Fails</th></tr>\n')
            for title, count in top:
                s = short_name(title)
                short = s[-70:] if len(s) > 70 else s
                fh.write(f'<tr><td title="{esc(title)}">{esc(short)}</td><td>{count}</td></tr>\n')
            fh.write('</table>\n')

        if flaky:
            fh.write('<div class="section-lbl">Flaky tests</div>\n')
            fh.write('<ul class="flaky-list">\n')
            for t, count in flaky[:7]:
                s = short_name(t)
                short = s[-70:] if len(s) > 70 else s
                fh.write(f'<li title="{esc(t)}">{esc(short)} <strong>({count})</strong></li>\n')
            if len(flaky) > 7:
                fh.write(f'<li>&hellip;and {len(flaky)-7} more</li>\n')
            fh.write('</ul>\n')

        # Shell tests section
        fh.write('<div class="section-lbl">Shell unit tests (POSIX sh)</div>\n')
        fh.write('<div class="stats-row" style="margin-bottom:.5rem">\n')
        fh.write(f'<div class="stat-box"><div class="stat-val">{shell_avg_total}</div><div class="stat-lbl">Avg tests/run</div></div>\n')
        fh.write(f'<div class="stat-box"><div class="stat-val">{shell_avg_passed}</div><div class="stat-lbl">Avg passed/run</div></div>\n')
        sh_fail_cls = " stat-fail" if shell_total_failed > 0 else ""
        fh.write(f'<div class="stat-box{sh_fail_cls}"><div class="stat-val">{shell_total_failed}</div><div class="stat-lbl">Total failures</div></div>\n')
        fh.write(f'<div class="stat-box"><div class="stat-val">{shell_total_skipped}</div><div class="stat-lbl">Total skipped</div></div>\n')
        fh.write('</div>\n')
        if top_shell:
            fh.write('<table><tr><th>Shell test</th><th style="width:4rem">Fails</th></tr>\n')
            for title, count in top_shell:
                s = short_name(title)
                short = s[-70:] if len(s) > 70 else s
                fh.write(f'<tr><td title="{esc(title)}">{esc(short)}</td><td>{count}</td></tr>\n')
            fh.write('</table>\n')
        else:
            fh.write('<p style="font-size:.8rem;color:#94a3b8;margin:.25rem 0">No shell test failures recorded.</p>\n')

        fh.write('</div>\n')

    fh.write('</div></body></html>\n')

print(f"[dashboard] Written to {dashboard}")
PYEOF
