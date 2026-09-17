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
found=0
if [ -d downloaded-report ]; then
  for d in downloaded-report/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}index.html" ] || continue
    local_size="$(du -sh "$d" 2>/dev/null | awk '{print $1}' || echo '?')"
    echo "[add] Publishing report: ${d} → site/${RUN_FOLDER} (source size: ${local_size})"
    rm -rf "site/$RUN_FOLDER"
    cp -r "$d" "site/$RUN_FOLDER"
    echo "[add] Copied. Site size now: $(site_size_mb)"
    found=1
    break  # only one report per run
  done
fi

if [ "$found" -eq 0 ]; then
  echo "[site] No report found in downloaded-report — creating placeholder"
  mkdir -p "site/$RUN_FOLDER"
fi

touch site/.nojekyll

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
