# CLAUDE.md — openwrt/

Guidance for Claude Code when working in this subfolder. It supplements the
root [../CLAUDE.md](../CLAUDE.md); read that first for the main app.

## Overview

This is a **self-contained router-native port** of StravaStats' leaderboard,
sized for a router-class device running OpenWrt. A single POSIX shell script driven by cron, using `curl`
to talk to Strava and `jq` to aggregate, writing a static HTML page + JSON into
uhttpd's web root.

## Files

| File                                                           | Purpose                                                                                                                                                                                      |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [strava-lib.sh](strava-lib.sh)                                 | Shared library: `log()`, `die()`, `ensure_access_token()`. Sourced by both main scripts. Installed to `/usr/bin/strava-lib.sh` (0644 — not executable directly).                             |
| [strava-leaderboard.sh](strava-leaderboard.sh)                 | Club leaderboard: token refresh → page club feed → merge store → emit JSON → render HTML. Installed to `/usr/bin/strava-leaderboard`.                                                        |
| [config.example](config.example)                               | Config template → `/etc/strava-leaderboard.conf` (holds secrets, `chmod 600`).                                                                                                               |
| [strava-my-activities.sh](strava-my-activities.sh)             | My Activities: token refresh → page `/athlete/activities` → merge store (dedup by Strava ID) → emit JSON → source the four HTML helpers below. Installed to `/usr/bin/strava-my-activities`. |
| [strava-my-html-dashboard.sh](strava-my-html-dashboard.sh)     | Sourced by `strava-my-activities.sh`: writes `index.html` (activities dashboard with year/month/sport filter + reset button).                                                                |
| [strava-my-html-detail.sh](strava-my-html-detail.sh)           | Sourced by `strava-my-activities.sh`: writes `activity.html` (per-activity detail page with Leaflet map and splits chart).                                                                   |
| [strava-my-html-bike.sh](strava-my-html-bike.sh)               | Sourced by `strava-my-activities.sh`: writes `bike.html` + installs the bike-service CGI.                                                                                                    |
| [strava-my-html-stats.sh](strava-my-html-stats.sh)             | Sourced by `strava-my-activities.sh`: writes `stats.html` (personal stats summary — yearly/monthly/records/sport breakdown).                                                                 |
| [config-my.example](config-my.example)                         | Config template → `/etc/strava-my-activities.conf` (holds secrets, `chmod 600`). Needs `activity:read` scope; `activity:read_all` for private activities.                                    |
| [install.sh](install.sh)                                       | Installs deps (`curl jq ca-bundle`), both scripts, all helper files, both config templates, timezone, and both daily cron entries. Idempotent.                                               |
| [README.md](README.md)                                         | End-user setup: Strava API app, one-time OAuth, install, scheduling, ops, limitations. Keep it in sync with behavior changes.                                                                |
| [test/Containerfile](test/Containerfile)                       | Alpine container that serves all four pages via BusyBox httpd for local testing. Build context is `openwrt/`.                                                                                |
| [test/run.sh](test/run.sh)                                     | Container entrypoint: extracts HTML from each helper script's `<<'HTML'` heredoc, sets up the CGI, and starts httpd on :8080.                                                                |
| [test/screenshot.mjs](test/screenshot.mjs)                     | Node.js (puppeteer-core + system Edge) script called by `make-screenshots.ps1` to capture all four pages.                                                                                    |
| [test/make-screenshots.ps1](test/make-screenshots.ps1)         | PowerShell driver: builds the container, starts it, runs the screenshot script, saves PNGs to `test/screenshots/`.                                                                           |
| [test/make-test-html.ps1](test/make-test-html.ps1)             | Extracts the dashboard heredoc from `strava-my-html-dashboard.sh`, inlines `activities.json`, writes `test/test.html` for offline preview.                                                   |
| [test/activities.sample.json](test/activities.sample.json)     | Sample activities dataset served inside the container (and used by `make-test-html.ps1`).                                                                                                    |
| [test/bike-service.sample.json](test/bike-service.sample.json) | Sample bike-service store served inside the container.                                                                                                                                       |
| [test/18784255013.json](test/18784255013.json)                 | Sample per-activity detail JSON (served at `details/18784255013.json` inside the container).                                                                                                 |
| [test/screenshots/](test/screenshots/)                         | Screenshots generated by `make-screenshots.ps1`; embedded in README.md.                                                                                                                      |

## Router

- **IP:** `192.168.1.1` — router on the local network
- **Dashboard:** `http://192.168.1.1/strava/me/` (my activities), `http://192.168.1.1/strava/` (club leaderboard)

## Deploy (update binary only, no full reinstall)

Run from the repo root on the dev machine:

```sh
# Push updated scripts+helpers and regenerate the dashboard immediately
scp openwrt/strava-my-activities.sh root@192.168.1.1:/usr/bin/strava-my-activities && \
scp openwrt/strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh && \
scp openwrt/strava-my-html-dashboard.sh openwrt/strava-my-html-detail.sh \
    openwrt/strava-my-html-bike.sh openwrt/strava-my-html-stats.sh \
    root@192.168.1.1:/usr/bin/ && \
ssh root@192.168.1.1 strava-my-activities
```

For the club leaderboard script:

```sh
scp openwrt/strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard && \
ssh root@192.168.1.1 strava-leaderboard
```

Full reinstall (first time or after `install.sh` changes):

```sh
scp -r openwrt root@192.168.1.1:/tmp/strava && ssh root@192.168.1.1 sh /tmp/strava/install.sh
```

## How it runs (no dev server, no tests)

There is **no test framework, linter, or local run loop** for this folder. The
script targets BusyBox `sh` on the router, not your Windows dev box — you can't
meaningfully execute it here. To validate changes:

- **Syntax / lint:** `shellcheck openwrt/*.sh` if available (the script already
  carries `# shellcheck disable=` pragmas). Otherwise `sh -n strava-leaderboard.sh`.
- **Real testing happens on the router** via scp + ssh, then a manual
  `strava-leaderboard` run whose output must end in `done.` (see README §5).

## Hard constraints (do not break these)

- **Pure POSIX sh / BusyBox** — no bashisms. No arrays, no `[[ ]]`, no
  `local` (BusyBox `sh` does support `local`, but stay conservative), no
  process substitution. Stick to `[ ]`, `case`, `printf`, here-docs.
- **Only `curl` + `jq`** as external deps. Don't introduce `awk`/`sed`/`python`
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

## Parity with the main app

The shell rewrite deliberately mirrors the TypeScript services; if you change
aggregation logic in one place, check the other:

- Activity dedupe by content **signature** mirrors
  [../server/src/services/activityStore.ts](../server/src/services/activityStore.ts)
  (`buildSignature`).
- Leaderboard grouping/summing/ranking mirrors
  [../server/src/services/stats.service.ts](../server/src/services/stats.service.ts):
  group by `firstname|lastname|profile_medium`, sum distance/time/elevation,
  rank by distance, avg speed in km/h. This matches the main app's
  `buildAthleteKey` fallback for the feed's missing athlete `id`.

**Key shared constraint:** Strava's `/clubs/{id}/activities` feed has **no dates
and no activity IDs** — it's just _recent_ activities. The script works around
this by accumulating a persistent store and stamping each newly seen activity
with its **first-seen date** (today, or `STRAVA_FIRST_SEEN_DATE` for the initial
seeding run). Dates are therefore approximate — first-seen, not performed.

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
- **No auth.** Same open-on-LAN trust model as the other dashboards; the CGI
  accepts any valid-JSON write from the LAN. Fine for a private home router only.
- **First-time serving:** uhttpd serves `/www/cgi-bin` as CGI by default;
  `install.sh` sets `uhttpd.main.cgi_prefix=/cgi-bin` idempotently. A bare
  `scp + run` deploy works once that prefix is set.

## Token handling

Unlike the server (cookie JWT, no refresh-token persistence), this script holds
a long-lived **refresh token in the config** and manages access tokens itself:
it caches the last token response in `$STATE_DIR/token.json`, reuses the cached
access token until it's within `STRAVA_TOKEN_REFRESH_MARGIN` of expiry, then
refreshes. Strava may rotate the refresh token on refresh, so the script
persists whatever it returns and prefers that next run.

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
