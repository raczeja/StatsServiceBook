# CLAUDE.md

## Overview

A **router-native activity stats and bike service tracker** for OpenWrt. A set of POSIX shell scripts driven by cron, using `curl` and `jq` to aggregate, writing static HTML pages + JSON into uhttpd's web root. Supports three data sources: **Strava API** (OAuth), **Strava scrape mode** (`STRAVA_MY_SOURCE=scrape`, browser session cookie, no subscription required), and **HealthSync** (CSV/GPX/TCX from Google Drive, fully Strava-API-free).

## Files

| File                                                           | Purpose                                                                                                                                                                                      |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [strava-lib.sh](strava-lib.sh)                                 | Shared library: `log()`, `die()`, `ensure_access_token()`, `curl_retry()`, `fetch_weather_temp()`, `_rw_coords()`, `run_weather_backfill()`, `ensure_session_cookie()`. Sourced by both main scripts. Installed to `/usr/bin/strava-lib.sh` (0644 — not executable directly).                             |
| [strava-leaderboard.sh](strava-leaderboard.sh)                 | Club leaderboard: token refresh → page club feed → merge store → emit JSON → render HTML. Installed to `/usr/bin/strava-leaderboard`.                                                        |
| [config.example](config.example)                               | Config template → `/etc/strava-leaderboard.conf` (holds secrets, `chmod 600`).                                                                                                               |
| [strava-my-activities.sh](strava-my-activities.sh)             | My Activities: token refresh → page `/athlete/activities` → merge store (dedup by Strava ID) → emit JSON → source the four HTML helpers below. Installed to `/usr/bin/strava-my-activities`. |
| [strava-my-html-dashboard.sh](strava-my-html-dashboard.sh)     | Sourced by `strava-my-activities.sh`: writes `index.html` (activities dashboard with year/month/sport filter + reset button).                                                                |
| [strava-my-html-detail.sh](strava-my-html-detail.sh)           | Sourced by `strava-my-activities.sh`: writes `activity.html` (per-activity detail page with Leaflet map, splits chart, elevation chart, HR chart, cadence chart).                           |
| [strava-my-html-bike.sh](strava-my-html-bike.sh)               | Sourced by both main scripts: writes `bike.html` + installs the bike-service CGI + installs the bike-assign CGI.                                                                             |
| [strava-my-html-stats.sh](strava-my-html-stats.sh)             | Sourced by both main scripts: writes `stats.html` (personal stats summary — yearly/monthly/records/sport breakdown).                                                                         |
| [strava-my-html-heatmap.sh](strava-my-html-heatmap.sh)         | Sourced by both main scripts: generates `heatmap.json` (downsampled GPS points per activity) + writes `heatmap.html` (full-viewport Leaflet.heat all-activities heatmap with period filter). |
| [config-my.example](config-my.example)                         | Config template → `/etc/strava-my-activities.conf` (holds secrets, `chmod 600`). Needs `activity:read` scope; `activity:read_all` for private activities. Includes `STRAVA_MY_DEFAULT_BIKE_NAME` for the initial bike-tracker seed. |
| [healthsync-activities.sh](healthsync-activities.sh)           | HealthSync / Google Drive data source: Drive OAuth → download CSV+GPX+TCX → parse (incl. cadence from TCX/GPX) → cache GPX → emit `activities.json` → source HTML helpers. Also processes `Magene_*.fit` files via GPS Visualizer conversion (§3b). Writes `drive-status.json` and generates the `drive-auth` re-authorization CGI (§7). Installed to `/usr/bin/healthsync-activities`. |
| [config-healthsync.example](config-healthsync.example)         | Config template → `/etc/healthsync-activities.conf`. Holds Google OAuth credentials, Drive folder ID, `HEALTHSYNC_DEFAULT_BIKE`. |
| [install.sh](install.sh)                                       | Installs deps (`curl jq ca-bundle`), all scripts, all helper files, all config templates, timezone, and cron entries. Idempotent.                                                            |
| [README.md](README.md)                                         | End-user setup: Strava API app, one-time OAuth, install, scheduling, ops, limitations. Keep it in sync with behavior changes.                                                                |
| [test/Containerfile](test/Containerfile)                       | Alpine container that serves all five pages via lighttpd for local testing. Build context is the repo root.                                                                                  |
| [test/run.sh](test/run.sh)                                     | Container entrypoint: extracts HTML from each helper script's `<<'HTML'` heredoc, sets up the CGI, and starts lighttpd on :8080.                                                             |
| [test/screenshot.mjs](test/screenshot.mjs)                     | Node.js (puppeteer-core + system Edge) script called by `make-screenshots.ps1` to capture all five pages.                                                                                    |
| [test/make-screenshots.ps1](test/make-screenshots.ps1)         | PowerShell driver: builds the container, starts it, runs the screenshot script, saves PNGs to `test/screenshots/`.                                                                           |
| [test/functional-tests.mjs](test/functional-tests.mjs)        | Node.js (puppeteer-core + system Edge) regression test script covering all five pages + CGI round-trip (includes reset-filter, column-sorting, stats-sport-filter suites). Called by `run-tests.ps1`. Exits 0 on all pass, 1 on failure. |
| [.claude/settings.json](.claude/settings.json)                | Claude Code project settings: `PostToolUse` hook that runs `sh -n` after every `.sh` file edit and injects a reminder to run the full test suite.                                           |
| [test/run-tests.ps1](test/run-tests.ps1)                       | PowerShell driver: builds the container, starts it, runs `functional-tests.mjs`, stops the container. Propagates exit code for CI use.                                                      |
| [test/make-test-html.ps1](test/make-test-html.ps1)             | Extracts the dashboard heredoc from `strava-my-html-dashboard.sh`, inlines `activities.json`, writes `test/test.html` for offline preview.                                                   |
| [test/activities.sample.json](test/activities.sample.json)     | Sample activities dataset served inside the container (and used by `make-test-html.ps1`).                                                                                                    |
| [test/bike-service.sample.json](test/bike-service.sample.json) | Sample bike-service store served inside the container.                                                                                                                                       |
| [test/18784255013.json](test/18784255013.json)                 | Sample per-activity detail JSON (served at `details/18784255013.json` inside the container).                                                                                                 |
| [test/run-healthsync-podman.ps1](test/run-healthsync-podman.ps1) | PowerShell driver: runs `healthsync-activities.sh` with real Google credentials inside Alpine (Podman), then serves output with busybox httpd. Accepts `-Config`, `-StateDir`, `-SkipImport`, `-KeepOutput`. |
| [test/run-healthsync-local.ps1](test/run-healthsync-local.ps1)   | PowerShell driver: runs `healthsync-activities.sh` using local exported files (`LOCAL_DRIVE_DIR` mode, no Google credentials). Accepts `-LocalFilesDir`, `-Port`, `-StateDir`, `-SkipImport`, `-KeepOutput`, `-NoBrowser`. |
| [strava-email-monthly.sh](strava-email-monthly.sh)             | **Also installed as `/usr/bin/strava-email-weekly`** — there is no separate source file. The script detects its mode via `basename "$0"` (checks for `*weekly*`). Edit this file to change either email's behavior. |
| [strava-cron-guard.sh](strava-cron-guard.sh)                   | Cron wrapper: network pre-flight ping → retry on failure (up to `STRAVA_CRON_RETRIES`, default 2) → msmtp alert after all retries exhausted. Config: sources leaderboard conf first, then script-specific conf (so SMTP settings can be shared). |
| [test/screenshots/](test/screenshots/)                         | Screenshots generated by `make-screenshots.ps1`; embedded in README.md.                                                                                                                      |
| `$WEB_DIR/drive-status.json`                                   | Written by `healthsync-activities.sh` after each run: `{"ok":true}` on success, `{"ok":false,"error":"...","ts":N}` on Drive token failure. Dashboard reads it to show/hide the re-auth banner. |
| `$CGI_DIR/drive-auth`                                          | Generated CGI (POSIX sh) installed by `healthsync-activities.sh`: implements OAuth device-flow re-authorization for Google Drive. Accessed at `/cgi-bin/drive-auth`.                         |

## Router

- **IP:** `192.168.1.1` — router on the local network
- **Dashboard:** `http://192.168.1.1/strava/me/` (my activities), `http://192.168.1.1/strava/` (club leaderboard)

## Deploy (update binary only, no full reinstall)

Run from the repo root on the dev machine:

```powershell
# Push updated scripts+helpers and regenerate the dashboard immediately
scp strava-my-activities.sh root@192.168.1.1:/usr/bin/strava-my-activities `
  && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh `
  && scp strava-my-html-dashboard.sh strava-my-html-detail.sh strava-my-html-bike.sh strava-my-html-stats.sh strava-my-html-heatmap.sh root@192.168.1.1:/usr/bin/ `
  && ssh root@192.168.1.1 strava-my-activities
```

For the HealthSync script (also push `strava-lib.sh` — it holds the shared weather backfill):

```powershell
scp healthsync-activities.sh root@192.168.1.1:/usr/bin/healthsync-activities `
  && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh `
  && ssh root@192.168.1.1 healthsync-activities
```

For the club leaderboard script:

```powershell
scp strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard `
  && ssh root@192.168.1.1 strava-leaderboard
```

For the email / cron-guard scripts (push both together; no manual run needed — they are triggered by cron or by failure):

```powershell
scp strava-cron-guard.sh root@192.168.1.1:/usr/bin/strava-cron-guard `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-monthly `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-weekly `
  && ssh root@192.168.1.1 "chmod 0755 /usr/bin/strava-cron-guard /usr/bin/strava-email-monthly /usr/bin/strava-email-weekly"
```

Test-send after deploy (override target month; last-week window is always auto-computed from today):

```powershell
# Send August monthly leaderboard now
ssh root@192.168.1.1 "STRAVA_EMAIL_TEST_MONTH=2026-08 /usr/bin/strava-email-monthly"

# Send weekly email with August month leaderboard + last-week column (Aug 24–30 when run on a Wednesday in week of Sep 1)
ssh root@192.168.1.1 "STRAVA_WEEKLY_TEST_MONTH=2026-08 /usr/bin/strava-email-weekly"
```

Full reinstall (first time or after `install.sh` changes):

```sh
scp -r . root@192.168.1.1:/tmp/strava && ssh root@192.168.1.1 sh /tmp/strava/install.sh
```

### After a router sysupgrade

OpenWrt `sysupgrade` wipes `/usr/bin/`, `/usr/lib/`, and installed packages — only `/etc/` is preserved by default. After any firmware upgrade:

1. **Re-install packages** (they are gone):
   ```sh
   ssh root@192.168.1.1 "opkg update && opkg install curl jq ca-bundle"
   ```
2. **Re-deploy all scripts** (full reinstall from the repo):
   ```powershell
   scp -r . root@192.168.1.1:/tmp/strava
   ssh root@192.168.1.1 sh /tmp/strava/install.sh
   ```
   `install.sh` is idempotent and will not touch existing configs in `/etc/`.
3. **Verify state is intact** — persistent state lives under `STRAVA_STATE_DIR` (default `/usr/lib/strava-leaderboard`). If that path is on the overlay (it is on a standard OpenWrt setup), it survives sysupgrade and no data migration is needed. Confirm with:
   ```sh
   ssh root@192.168.1.1 "ls /usr/lib/strava-leaderboard/"
   ```

   The `/etc/sysupgrade.conf` on the router should list all scripts and state dirs so they are preserved across upgrades. The complete correct list is:
   ```
   /usr/bin/strava-leaderboard
   /usr/bin/strava-my-activities
   /usr/bin/healthsync-activities
   /usr/bin/strava-cron-guard
   /usr/bin/strava-email-monthly
   /usr/bin/strava-email-weekly
   /usr/bin/strava-lib.sh
   /usr/bin/strava-my-html-dashboard.sh
   /usr/bin/strava-my-html-detail.sh
   /usr/bin/strava-my-html-bike.sh
   /usr/bin/strava-my-html-stats.sh
   /usr/bin/strava-my-html-heatmap.sh
   /etc/strava-leaderboard.conf
   /etc/strava-my-activities.conf
   /etc/healthsync-activities.conf
   /usr/lib/strava-leaderboard
   /usr/lib/strava-my-activities
   /usr/lib/healthsync
   ```
   CGI scripts (`/www/cgi-bin/bike-service`, `bike-assign`, `drive-auth`) are **not** listed — they are regenerated automatically on the first run after reinstall.
4. **Trigger a manual run** to regenerate the HTML:
   ```sh
   ssh root@192.168.1.1 strava-my-activities
   ```

## How it runs (no dev server)

The scripts target BusyBox `sh` on the router — you can't meaningfully execute
them on a Windows dev box. To validate changes:

- **Syntax / lint:** `shellcheck *.sh` if available (the scripts already carry
  `# shellcheck disable=` pragmas). Otherwise `sh -n strava-leaderboard.sh`.
  Claude Code runs `sh -n` automatically after every `.sh` edit via the
  `.claude/settings.json` hook and will remind you to run the full suite.
- **Functional regression tests (HTML + JS + CGI):** run the Puppeteer test suite
  against the local container — this is the primary way to catch breakage in the
  HTML helper scripts:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\test\run-tests.ps1
  ```
  107 assertions across all five pages and the bike-service CGI. Exits 0 on pass.
  Requires Podman, Node.js ≥ 18, and Microsoft Edge.

  **Running a single test suite:** Neither test runner has a per-suite CLI flag.
  - `shell-tests.sh` — only supports `--junit <file>` (JUnit XML output); to isolate one suite, comment out the others in the file temporarily.
  - `functional-tests.mjs` — comment out the unwanted suite calls in `main()`. Suite functions: `testClubDashboard`, `testMyActivities`, `testStats`, `testActivityDetail`, `testActivityDetailHealthsyncRun`, `testActivityDetailHealthsyncCycling`, `testActivityDetailMagene`, `testBikeService`, `testBikeServicePartReplacement`, `testSyncSourceMerging`, `testHistoricalActivityPreservation`, `testDataConsistencyAcrossSources`.

  **How the test container gets its HTML:** `test/run.sh` (the container entrypoint) re-extracts each page's HTML from the production helper script's `<<'HTML'` heredoc via `awk` at startup — there are no separate HTML fixtures. This means the test always runs against the live heredoc content; changing a heredoc is reflected immediately in the next container run.
- **Screenshots of all pages** (saves PNGs to `test/screenshots/`):
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\test\make-screenshots.ps1
  ```
- **Manual / interactive Podman** (keep container running to browse at `http://localhost:8080`):
  ```powershell
  # Build the image
  podman build -f test/Containerfile -t stravame-test .

  # Start the container
  podman run -d --name stravame -p 8080:8080 stravame-test

  # View logs
  podman logs stravame

  # Run shell unit tests inside the container
  podman exec stravame sh /opt/shell-tests.sh

  # Stop and remove when done
  podman stop stravame && podman rm stravame
  ```
  Pages: `http://localhost:8080/strava/me/` (dashboard), `/activity.html`, `/bike.html`, `/stats.html`, `http://localhost:8080/strava/` (club leaderboard).
- **Real testing on the router** via scp + ssh, then a manual
  `strava-leaderboard` run whose output must end in `done.` (see README §5).

## Hard constraints (do not break these)

- **Pure POSIX sh / BusyBox** — no bashisms. No arrays, no `[[ ]]`, no
  `local` (BusyBox `sh` does support `local`, but stay conservative), no
  process substitution. Stick to `[ ]`, `case`, `printf`, here-docs.
- **Only `curl` + `jq` + `msmtp`** as external deps. Don't introduce `awk`/`sed`/`python`
  dependencies for logic that `jq` can do — `jq` is already required and does
  the aggregation.
- **Low RAM / flash.** Prefer streaming/NDJSON over loading everything. The club
  leaderboard store is append-only NDJSON so writes stay cheap on flash; the My
  Activities store is rebuilt once per run (it reconciles edits/deletions against
  the feed — see `strava-my-activities.sh` §3), which is still a single daily
  write of a small file. Don't add daemons or anything resident in memory —
  uhttpd serves the static output.
- **Persistent state must stay off `/tmp` and `/var`** (both tmpfs/RAM on
  OpenWrt, wiped on reboot). State lives under `STRAVA_STATE_DIR`
  (default `/usr/lib/strava-leaderboard`, in the overlay).
- **Config is sourced by `/bin/sh`** — `KEY="value"`, no spaces around `=`.

## strava-lib.sh shared functions

These functions exist beyond `log/die/ensure_access_token` — know them before touching weather or scrape logic:

- **`curl_retry [args…]`** — wraps every `curl` call with exponential back-off. Config: `STRAVA_CURL_RETRIES` (default 3), `STRAVA_CURL_RETRY_DELAY` (default 15 s). Exit 22 (HTTP 4xx/5xx from `curl -f`) is **not** retried — only network errors are. Retry messages go to stderr only, so `code="$(curl_retry … -w '%{http_code}')"` capture patterns stay clean.

- **`fetch_weather_temp lat lon date`** — Open-Meteo archive API (ERA5, data since 1940, ~5-day lag); falls back to forecast API for very recent dates. Sets globals: `_fw_temp_source` ("archive"/"forecast"), `_fw_apparent_temp`, `_fw_wind_speed`, `_fw_wind_dir`, `_fw_weathercode`, `_fw_precipitation`. If caller sets `_fw_archive_only=1`, forecast fallback is skipped (used by Pass 3 to avoid downgrading archive entries).

- **`_rw_coords id gpx_file detail_dir web_dir`** — resolves lat/lon for weather fetch. Five-priority chain: (1) `detail_dir/<id>.json` `.start_latlng`; (2) first `<trkpt>` in `web_dir/<gpx_file>`; (3) first `<trkpt>` in GPX referenced by detail JSON `.gpx_file` (scrape-mode path); (4) polyline decode from detail JSON `.map.summary_polyline`; (5) `WEATHER_LAT`/`WEATHER_LON` env vars. Sets `_wlat`/`_wlon`. All paths exit 0 under `set -eu`.

- **`run_weather_backfill store cache tmp detail_dir web_dir`** — three-pass cache fill/upgrade. Pass 1: activities with `average_temp==null` not yet in cache → fetch all fields. Pass 2: activities with device temp but no extended cache entry → fetch extended fields. Pass 3: `s=="forecast"` entries older than 7 days → archive-only re-fetch (upgrade to `s=="archive"`). Entries with `s=="no-coord"` are never retried. Sets `_rw_changed` to the update count.

- **`ensure_session_cookie`** — scrape mode only. 25-day session validity window (2 160 000 s). Caches CSRF token to `$STATE_DIR/strava_csrf.txt` and cookies to `$STATE_DIR/strava_cookies.txt`. Empty or non-numeric timestamp is treated as 0 (expired).

## HTML page JS architecture

All five pages (`index.html`, `activity.html`, `bike.html`, `stats.html`, `heatmap.html`) follow the same pattern — knowing this prevents reaching for Chart.js or adding `$`-expansion to heredocs:

- **Fetch** — `fetch('activities.json')` (or `heatmap.json` for the heatmap). No server-side rendering; all logic runs in the browser.
- **Filter** — year/month/sport dropdowns. State is stored in `sessionStorage` so it survives page refreshes. A Reset button clears `sessionStorage` and reloads defaults.
- **Render** — inline SVG bar charts only (no external charting library). Column sorting on table headers (↑/↓ via CSS `::after`). A `#pbar` element at the top animates during fetch (fake tick to 80%, then snap to 100%).
- **Progress bar** — `#pbar` is the only animated element; it is not a real progress indicator.
- `bike.html` is the only read/write page — all others are purely read-only renders of `activities.json`.

## Algorithm notes

- Activity dedupe by content **signature** (club leaderboard): a pipe-joined
  string of athlete name + activity shape — `firstname|lastname|name|distance|
  moving_time|elapsed_time|total_elevation_gain|sport_type`. Strava's club feed
  has **no dates and no activity IDs**, so this is the only stable identity.
- Leaderboard grouping/summing/ranking: group by `firstname|lastname|profile_medium`,
  sum distance/time/elevation, rank by distance, avg speed in km/h.

**activities.ndjson store fields** (My Activities / HealthSync — the exact set projected into the store and emitted to `activities.json`):
```
id, date, name, sport_type, gear_id, distance, moving_time, elapsed_time,
total_elevation_gain, average_speed, max_speed, average_heartrate, max_heartrate,
average_cadence, average_watts, weighted_average_watts, max_watts, kilojoules,
average_temp, suffer_score, elev_high, elev_low
```
`gpx_file` is **not** in the standard Strava store record — it exists only in HealthSync store records and in detail JSONs (`$DETAIL_DIR/<id>.json`). The `activities.json` output merges in weather fields from `weather-cache.json`, gear name from detail JSONs, and `bike_id` from `bike-assignments.json`.

**Key constraint:** Strava's `/clubs/{id}/activities` feed has **no dates and no
activity IDs** — it's just _recent_ activities. The script works around this by
accumulating a persistent store and stamping each newly seen activity with its
**first-seen date** (today, or `STRAVA_FIRST_SEEN_DATE` for the initial seeding
run). Dates are therefore approximate — first-seen, not performed.

## Bike-service tracker (the one read/WRITE page)

Every other page here is static and read-only. The bike-service page
(`/www/strava/me/bike.html`, §6b of `strava-my-activities.sh`) is the exception:
the browser **saves** data back through a CGI.

- **CGI (§6c):** `strava-my-activities.sh` generates a tiny POSIX-sh CGI to
  `$CGI_DIR/bike-service` (`STRAVA_MY_CGI_DIR`, default `/www/cgi-bin` — uhttpd's
  default `cgi_prefix`). `GET` returns the stored JSON; `POST` validates the body
  with `jq -e` (must be an object with a `bikes` array, ≤1 MB), stamps
  `updatedAt`, and writes `$BIKE_DATA` atomically (`tmp` + `mv`). The CGI is the
  **only writer** of the data file, so the daily cron run that regenerates
  `bike.html` never clobbers user data. Only the data-file path is shell-injected
  into the CGI (a `DATA_FILE="…"` line prepended before a quoted `<<'CGI'` body);
  keep the rest non-expanded.
- **Data store:** `$BIKE_DATA` (`STRAVA_MY_BIKE_DATA`, default
  `$STATE_DIR/bike-service.json`) — must stay on persistent storage like the rest
  of the state.
- **Mileage** is computed **client-side** from `activities.json`: cumulative
  distance of `sport_type=="Ride"` activities up to a date, optionally filtered to
  a bike's mapped Strava `gear_id`. This required adding `gear_id` to the store
  projection (§3) and to the emitted `activities.json` (§4), plus a `gears` map
  (`gear_id → {name}`) built from the detail files' `.gear` object for labelling.
- **No auth.** Open-on-LAN trust model; the CGI accepts any valid-JSON write from
  the LAN. Fine for a private home router only.
- **First-time serving:** uhttpd serves `/www/cgi-bin` as CGI by default;
  `install.sh` sets `uhttpd.main.cgi_prefix=/cgi-bin` idempotently. A bare
  `scp + run` deploy works once that prefix is set.

## Token handling

The scripts hold a long-lived **refresh token in the config** and manage access
tokens themselves: the last token response is cached in `$STATE_DIR/token.json`,
the cached access token is reused until it's within `STRAVA_TOKEN_REFRESH_MARGIN`
of expiry, then refreshed. Strava may rotate the refresh token on refresh, so the
script persists whatever it returns and prefers that next run.

## Editing notes

- The HTML dashboards are **single quoted heredocs** (`<<'HTML'`) at the bottom
  of each script — nothing in them is shell-expanded; all runtime data flows
  through `activities.json`, which each page fetches and filters in the browser.
  Keep the heredoc quoted; don't introduce `$`-expansion into it.
- When changing config knobs for the club leaderboard, update **all three**: the
  default in [strava-leaderboard.sh](strava-leaderboard.sh) (`${VAR:-default}`),
  [config.example](config.example), and the README docs. Same for
  `strava-my-activities.sh` / `config-my.example`.
- `install.sh` must stay **idempotent**: overwrite both binaries, leave existing
  configs untouched, replace (not append) both cron lines.
- The README documents real user-facing behavior — update it whenever you
  change defaults, paths, cron times, deps, or the run output.
- The **GitHub wiki** (`https://github.com/raczeja/StatsServiceBook/wiki`) holds
  detailed documentation split across pages: Features, Installation, data-source
  setup guides, Running Locally, Email Notifications, Upgrading, Switching Data
  Sources, and Operations. Wiki source files live locally at `../StatsServiceBook.wiki/*.md`
  (sibling directory, its own git repo — commit and push changes there separately). Update the relevant
  wiki page whenever you add a feature, change behaviour, add a config option, or
  change a file path. The pages that most commonly need updating are:
  - `../StatsServiceBook.wiki/Features.md` — add/update any new feature description
  - `../StatsServiceBook.wiki/Installation.md` — new config keys, path variables, install steps
  - `../StatsServiceBook.wiki/Data-Source-*.md` — changes to a specific data source
  - `../StatsServiceBook.wiki/Operations.md` — new file paths or URLs

## After every change (Claude checklist)

When you finish implementing a new feature or behaviour change, always do the following before considering the task done:

1. **Update `Dockerfile` (and only `Dockerfile`) when scripts change.** The test image (`test/Containerfile`) is built on top of the production image — it inherits all scripts automatically. So there is only **one** place to maintain the script list:
   - **[Dockerfile](Dockerfile)** — add/remove the `COPY` line and the matching entry in the `chmod 0644` or `chmod 0755` block.
   - If the file is also needed in the web root at test time, add/remove it in [test/run.sh](test/run.sh).
   - Add/remove the script path from the `script-syntax-check` loop in [test/shell-tests.sh](test/shell-tests.sh) (paths are `/usr/bin/` — the prod install paths).
   - `test/Containerfile` only needs changes when **test-data files** (under `test/`) are added or removed.

   **Why this matters:** `shell-tests.sh`'s `script-syntax-check` suite runs `sh -n` on every script at its `/usr/bin/` path. If a script is missing from `Dockerfile`, it won't be in the image and the test will fail with "not found in container", surfacing the omission before it reaches the router.

2. **Run the functional test suite** to catch regressions:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\test\run-tests.ps1
   ```
   If any test fails, fix the regression before proceeding. Do not skip this step.

3. **Consider whether new tests are needed.** Don't silently assume existing tests are sufficient — the suite only proves what it asserts.
   - **Shell logic changes** (parsing, calculations, POSIX functions, skip guards, store merging): propose a new suite in `test/shell-tests.sh`. Shell tests are self-contained, run without credentials, and are the right tool for any logic that lives in `.sh` files.
   - **UI/HTML changes** (new feature, filter, chart, button, sorting, CGI endpoint): propose a new suite or assertions in `test/functional-tests.mjs`.

4. **Propose README and wiki updates.** After any feature addition or behaviour change, tell the user exactly which sections of `README.md` and which wiki page(s) (`../StatsServiceBook.wiki/*.md`) need updating, and offer to write the changes. The most commonly affected pages are listed in "Editing notes" above. Never silently skip docs.

5. **Propose a deploy command.** Once tests pass and docs are updated, offer the user the exact `scp`/`ssh` command(s) to push the changed file(s) to the router (use the per-script patterns in the "Deploy" section above). Do not run the deploy yourself without explicit user confirmation — deploying to the router is an irreversible action on shared infrastructure.

6. **Update service/install instructions if necessary.** If the change adds, renames, or removes a script or helper file; changes a default path or config key; adds a new cron entry; or changes how the service is installed or started, propose updates to:
   - `install.sh` — keep it idempotent and complete so a full reinstall still works
   - The "Deploy" section in this file — add/update the per-script `scp`/`ssh` pattern
   - `config.example` / `config-my.example` / `config-healthsync.example` — add/remove/document any new config keys
   Do not leave `install.sh` out of sync with the deployed scripts.

7. **Update `/etc/sysupgrade.conf` if new installed files are added.** Whenever a change adds a new script to `/usr/bin/`, a new state directory, or a new config file to `/etc/`, tell the user to add the path to `/etc/sysupgrade.conf` on the router so it survives firmware upgrades. The complete canonical list is documented in the "After a router sysupgrade" section above — keep it in sync. CGI scripts (`/www/cgi-bin/`) are the only exception: they are regenerated on first run and do not need to be listed. Always explicitly remind the user to update `sysupgrade.conf` when this applies.
