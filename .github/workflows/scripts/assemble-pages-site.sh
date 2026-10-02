#!/usr/bin/env bash

set -euo pipefail

DEFAULT_MAX_REPORTS=3
PAGES_SIZE_LIMIT_BYTES=$((1000 * 1000 * 1000))
RUN_FOLDER="run-${GITHUB_RUN_NUMBER}"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

site_size_bytes() {
  [ -d site ] || { echo 0; return; }
  du -sb site | awk '{print $1}'
}

format_mb() {
  awk "BEGIN { printf \"%.1f MB\", $1 / 1024 / 1024 }"
}

site_size_mb() {
  format_mb "$(site_size_bytes)"
}

prune_reports() {
  local dir="$1"
  local max_reports="${2:-$DEFAULT_MAX_REPORTS}"
  [ -d "$dir" ] || return 0

  local old_folders
  old_folders="$(find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'run-*' -mtime +7 -printf '%f\n' 2>/dev/null || true)"
  if [ -n "$old_folders" ]; then
    echo "[prune] Removing run folders older than 7 days in ${dir}:"
    echo "$old_folders" | sed 's/^/  - /'
    find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'run-*' -mtime +7 -exec rm -rf {} + || true
  fi

  local count=0
  while IFS= read -r report_dir; do
    count=$((count + 1))
    if [ "$count" -gt "$max_reports" ]; then
      local folder_size
      folder_size="$(du -sh "$dir/$report_dir" 2>/dev/null | awk '{print $1}' || echo '?')"
      echo "[prune] Removing excess run (count=${count}, max=${max_reports}): ${dir}/${report_dir} (${folder_size})"
      rm -rf "$dir/$report_dir"
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -name 'run-*' -printf '%f\n' | sort -t- -k2,2nr)
}

enforce_site_size_limit() {
  local current_size
  current_size="$(site_size_bytes)"
  echo "[size] Site size: $(format_mb "$current_size") (limit: $(format_mb "$PAGES_SIZE_LIMIT_BYTES"))"

  [ "$current_size" -le "$PAGES_SIZE_LIMIT_BYTES" ] && { echo "[size] Within limit."; return; }

  for keep in 2 1; do
    echo "[size] Reducing retention to ${keep} run(s)."
    prune_reports site "$keep"
    current_size="$(site_size_bytes)"
    [ "$current_size" -le "$PAGES_SIZE_LIMIT_BYTES" ] && { echo "[size] Reduced to $(format_mb "$current_size")."; return; }
  done

  while [ "$current_size" -gt "$PAGES_SIZE_LIMIT_BYTES" ]; do
    local oldest_run_path
    oldest_run_path="$(find site -mindepth 1 -maxdepth 1 -type d -name 'run-*' ! -name "${RUN_FOLDER}" -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-)"
    [ -z "$oldest_run_path" ] && oldest_run_path="$(find site -mindepth 1 -maxdepth 1 -type d -name 'run-*' -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-)"
    [ -z "$oldest_run_path" ] || [ ! -d "$oldest_run_path" ] && { echo "[size] No runs left to delete."; return; }
    local folder_size
    folder_size="$(du -sh "$oldest_run_path" 2>/dev/null | awk '{print $1}' || echo '?')"
    echo "[size] Removing oldest run: ${oldest_run_path} (${folder_size})"
    rm -rf "$oldest_run_path"
    current_size="$(site_size_bytes)"
  done

  echo "[size] Final site size: $(format_mb "$current_size")"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ -d gh-pages-current ]; then
  mkdir -p site
  cp -a gh-pages-current/. site/
  rm -rf site/.git
  echo "[site] Restored from gh-pages-current: $(site_size_mb)"
else
  echo "[site] No existing gh-pages-current — starting fresh"
  mkdir -p site
fi

# Copy the downloaded Playwright report to site/run-N/
# download-artifact v4+ places files directly into the target dir (no subdir wrapper).
found=0
if [ -d downloaded-report ]; then
  if [ -f "downloaded-report/index.html" ]; then
    local_size="$(du -sh downloaded-report 2>/dev/null | awk '{print $1}' || echo '?')"
    echo "[add] Publishing report: downloaded-report/ → site/${RUN_FOLDER} (source size: ${local_size})"
    rm -rf "site/$RUN_FOLDER"
    cp -r downloaded-report "site/$RUN_FOLDER"
    echo "[add] Copied. Site size now: $(site_size_mb)"
    found=1
  else
    for d in downloaded-report/*/; do
      [ -d "$d" ] || continue
      [ -f "${d}index.html" ] || continue
      local_size="$(du -sh "$d" 2>/dev/null | awk '{print $1}' || echo '?')"
      echo "[add] Publishing report: ${d} → site/${RUN_FOLDER} (source size: ${local_size})"
      rm -rf "site/$RUN_FOLDER"
      cp -r "$d" "site/$RUN_FOLDER"
      echo "[add] Copied. Site size now: $(site_size_mb)"
      found=1
      break
    done
  fi
fi

if [ "$found" -eq 0 ]; then
  echo "[site] No report found in downloaded-report — creating placeholder page"
  mkdir -p "site/$RUN_FOLDER"
  cat > "site/$RUN_FOLDER/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Run #${GITHUB_RUN_NUMBER} — Report unavailable</title>
<style>
body{font-family:system-ui,Arial,sans-serif;margin:0;background:#f0f2f5;display:flex;flex-direction:column;min-height:100vh}
.topbar{background:#1a1a2e;color:#fff;padding:.75rem 2rem}
.topbar-title{font-weight:700;font-size:1rem}
.page{max-width:36rem;margin:4rem auto;padding:0 2rem;text-align:center}
h1{font-size:1.5rem;color:#1a1a2e}
p{color:#64748b}
a{color:#2563eb;text-decoration:none}a:hover{text-decoration:underline}
</style>
</head><body>
<div class="topbar"><span class="topbar-title">StatsServiceBook &middot; Test Reports</span></div>
<div class="page">
<h1>Report not available</h1>
<p>The Playwright report for run #${GITHUB_RUN_NUMBER} was not captured &mdash;
the CI job may have been cancelled or the artifact upload may have failed.</p>
<p><a href="../">&larr; Back to all reports</a></p>
</div>
</body></html>
HTML
fi

# Publish the latest browser-side coverage summary at a stable Pages URL.
mkdir -p site/coverage
coverage_file="downloaded-coverage/coverage-summary.json"
if [ -f "$coverage_file" ]; then
  cp "$coverage_file" site/coverage/coverage-summary.json
  COVERAGE_FILE="$coverage_file" COVERAGE_HTML="site/coverage/index.html" \
    GITHUB_RUN_NUMBER="$GITHUB_RUN_NUMBER" \
    GITHUB_RUN_URL="${GITHUB_RUN_URL:-}" \
    python3 - <<'PY'
import html
import json
import os
from datetime import datetime

with open(os.environ["COVERAGE_FILE"], encoding="utf-8") as source:
    report = json.load(source)

overall = float(report.get("overallPercent", 0))
generated = report.get("generatedAt", "")
try:
    generated = datetime.fromisoformat(generated.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M UTC")
except (TypeError, ValueError):
    generated = "Unknown"

def tone(percent):
    if percent >= 80:
        return "good"
    if percent >= 50:
        return "medium"
    return "low"

rows = []
for page in report.get("pages", []):
    label = html.escape(str(page.get("label", "Unknown")))
    percent = float(page.get("percent", 0))
    covered = int(page.get("coveredStatements", 0))
    total = int(page.get("totalStatements", 0))
    rows.append(
        '<tr>'
        f'<th scope="row">{label}</th>'
        f'<td><strong>{percent:.2f}%</strong>'
        f'<div class="bar"><span class="{tone(percent)}" style="width:{max(0, min(100, percent)):.2f}%"></span></div></td>'
        f'<td>{covered:,} / {total:,} statements</td>'
        '</tr>'
    )

rows_html = "\n".join(rows) or '<tr><td colspan="3">No page coverage data was collected.</td></tr>'
run_url = os.environ.get("GITHUB_RUN_URL", "")
run_link = (
    f'<a href="{html.escape(run_url, quote=True)}">GitHub Actions run #{html.escape(os.environ["GITHUB_RUN_NUMBER"])}</a>'
    if run_url else f'GitHub Actions run #{html.escape(os.environ["GITHUB_RUN_NUMBER"])}'
)
document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Playwright JavaScript Coverage — StatsServiceBook</title>
<style>
:root{{color-scheme:light dark;--bg:#f0f2f5;--card:#fff;--ink:#1a1a2e;--muted:#64748b;--line:#e2e8f0;--blue:#2563eb}}
@media(prefers-color-scheme:dark){{:root{{--bg:#0f172a;--card:#1e293b;--ink:#e2e8f0;--muted:#94a3b8;--line:#334155;--blue:#60a5fa}}}}
*{{box-sizing:border-box}}body{{font-family:system-ui,Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}}
.topbar{{background:#1a1a2e;color:#fff;padding:.85rem max(1.25rem,calc((100% - 56rem)/2));font-weight:700}}
main{{max-width:56rem;margin:0 auto;padding:2rem 1.25rem}}a{{color:var(--blue);text-decoration:none}}a:hover{{text-decoration:underline}}
.nav{{display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:1.25rem;font-size:.9rem}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:.8rem;padding:1.25rem;margin-bottom:1rem}}
.summary{{display:flex;align-items:center;gap:1.25rem;flex-wrap:wrap}}.score{{font-size:2.6rem;font-weight:800;line-height:1}}
.good{{color:#16a34a}}.medium{{color:#ca8a04}}.low{{color:#dc2626}}.muted{{color:var(--muted);font-size:.88rem}}
table{{width:100%;border-collapse:collapse;text-align:left}}th,td{{padding:.8rem .55rem;border-bottom:1px solid var(--line);vertical-align:middle}}thead th{{font-size:.8rem;color:var(--muted)}}
.bar{{height:.45rem;background:var(--line);border-radius:99px;overflow:hidden;margin-top:.4rem;max-width:18rem}}.bar span{{display:block;height:100%;border-radius:inherit;background:currentColor}}
@media(max-width:36rem){{th,td{{padding:.65rem .35rem;font-size:.82rem}}}}
</style>
</head>
<body>
<header class="topbar">StatsServiceBook · Playwright Coverage</header>
<main>
<nav class="nav"><a href="../">← Test reports</a><a href="../stats/">Test statistics — last 30 days</a>{f'<a href="../run-{html.escape(os.environ["GITHUB_RUN_NUMBER"])}/">Playwright report for this run</a>'}</nav>
<section class="card summary">
<div class="score {tone(overall)}">{overall:.2f}%</div>
<div><h1>Browser-side JavaScript coverage</h1><div class="muted">Measured {html.escape(generated)} · {run_link}</div></div>
</section>
<section class="card">
<h2>Coverage by page</h2>
<p class="muted">Percentage of first-party JavaScript statements executed during each page's initial load, converted from Chromium V8 coverage. This does not include shell scripts, third-party libraries, or page interactions.</p>
<table><thead><tr><th>Page</th><th>Coverage</th><th>Statements</th></tr></thead><tbody>{rows_html}</tbody></table>
</section>
</main>
</body>
</html>
"""
with open(os.environ["COVERAGE_HTML"], "w", encoding="utf-8") as output:
    output.write(document)
PY
else
  rm -f site/coverage/coverage-summary.json
  cat > site/coverage/index.html <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Playwright coverage unavailable — StatsServiceBook</title>
<style>body{font-family:system-ui,Arial,sans-serif;margin:0;background:#f0f2f5;color:#1a1a2e}.topbar{background:#1a1a2e;color:#fff;padding:1rem 2rem;font-weight:700}main{max-width:42rem;margin:4rem auto;padding:0 1.5rem}p{color:#64748b}a{color:#2563eb;text-decoration:none}</style>
</head><body><header class="topbar">StatsServiceBook · Playwright Coverage</header>
<main><h1>Coverage unavailable</h1>
<p>No coverage artifact was produced for this workflow run. The test job may have been cancelled or failed before collection completed.</p>
<p><a href="../">← Back to test reports</a></p></main></body></html>
HTML
fi

touch site/.nojekyll

cat > site/404.html <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="3;url=./..">
<title>Report not found — StatsServiceBook</title>
<style>
body{font-family:system-ui,Arial,sans-serif;margin:0;background:#f0f2f5;display:flex;flex-direction:column;min-height:100vh}
.topbar{background:#1a1a2e;color:#fff;padding:.75rem 2rem}
.topbar-title{font-weight:700;font-size:1rem}
.page{max-width:36rem;margin:4rem auto;padding:0 2rem;text-align:center}
h1{font-size:1.5rem;color:#1a1a2e}
p{color:#64748b}
a{color:#2563eb;text-decoration:none}a:hover{text-decoration:underline}
</style>
</head><body>
<div class="topbar"><span class="topbar-title">StatsServiceBook &middot; Test Reports</span></div>
<div class="page">
<h1>Report not found</h1>
<p>This run has been pruned (only the last 3 are kept).</p>
<p>Redirecting to <a href="./..">&larr; all reports</a>&hellip;</p>
</div>
<script>setTimeout(function(){window.location.href='./..'},3000)</script>
</body></html>
HTML

prune_reports site "$DEFAULT_MAX_REPORTS"
echo "[size] Site size before size-limit enforcement: $(site_size_mb)"
enforce_site_size_limit
echo "[size] Final site size: $(site_size_mb)"

# Root landing page listing recent run reports.
{
  echo '<!doctype html>'
  echo '<html lang="en"><head><meta charset="utf-8">'
  echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
  echo '<title>StatsServiceBook · Playwright Reports</title>'
  echo '<style>'
  echo 'body{font-family:system-ui,Arial,sans-serif;margin:0;background:#f0f2f5}'
  echo '.topbar{background:#1a1a2e;color:#fff;padding:.75rem 2rem;display:flex;align-items:center;gap:1rem}'
  echo '.topbar-title{font-weight:700;font-size:1rem;flex:1}'
  echo '.topbar-meta{font-size:.78rem;color:#94a3b8}'
  echo '.page{max-width:48rem;margin:0 auto;padding:2rem}'
  echo '.card{background:#fff;border:1px solid #e2e8f0;border-radius:.75rem;padding:1.25rem;margin-bottom:1rem}'
  echo '.card h2{margin:0 0 .75rem;font-size:1rem;font-weight:700;color:#1a1a2e}'
  echo 'ul{margin:0;padding:0 0 0 1.1rem}li{margin:.4rem 0}'
  echo 'a{color:#2563eb;text-decoration:none}a:hover{text-decoration:underline}'
  echo '.stats-link{display:inline-flex;align-items:center;gap:.4rem;font-size:.875rem;font-weight:600;color:#2563eb;margin-bottom:1rem}'
  echo '</style>'
  echo '</head><body>'
  echo '<div class="topbar">'
  echo '  <span class="topbar-title">StatsServiceBook · Playwright Reports</span>'
  echo "  <span class=\"topbar-meta\">Run #${GITHUB_RUN_NUMBER} · $(date -u '+%Y-%m-%d %H:%M UTC')</span>"
  echo '</div>'
  echo '<div class="page">'
  echo '<a class="stats-link" href="./stats/">📊 Test Statistics — last 30 days</a>'
  echo '<a class="stats-link" href="./coverage/">📈 Playwright JavaScript Coverage</a>'
  echo '<div class="card">'
  echo '<h2>Recent runs</h2>'
  echo '<ul>'
  run_found=0
  while IFS= read -r name; do
    if [ -f "site/$name/index.html" ]; then
      echo "<li><a href=\"./${name}/\">${name}</a></li>"
      run_found=1
    fi
  done < <(find site -mindepth 1 -maxdepth 1 -type d -name 'run-*' -printf '%f\n' | sort -t- -k2,2nr)
  [ "$run_found" -eq 0 ] && echo "<li>No HTML reports retained yet.</li>"
  echo '</ul>'
  echo '</div>'
  echo "  <p style=\"font-size:.8rem;color:#94a3b8\">Commit: <code>${GITHUB_SHA_VALUE}</code> · Workflow: <strong>${GITHUB_WORKFLOW_NAME}</strong></p>"
  echo '</div>'
  echo '</body></html>'
} > site/index.html
