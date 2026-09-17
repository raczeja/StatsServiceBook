# StravaStats for OpenWrt
[![CI](https://github.com/raczeja/StatsServiceBook/actions/workflows/ci.yml/badge.svg)](https://github.com/raczeja/StatsServiceBook/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/raczeja/6941c42a1229a771c51380029a6fd797/raw/tests.json)](https://github.com/raczeja/StatsServiceBook/actions/workflows/ci.yml)
[![Docker Hub](https://img.shields.io/docker/pulls/jraczek/statsservicebook)](https://hub.docker.com/r/jraczek/statsservicebook)

A router-native activity stats and bike service tracker for OpenWrt. A single POSIX shell script driven by cron uses `curl` and `jq` to fetch activity data, then writes static HTML and JSON into uhttpd's web root — no extra daemon, almost no RAM. Three data sources are supported; the router's built-in web server serves everything. Can also run locally via Docker or Windows WSL.

## Data sources

| Source | Config file | When to use |
| ------ | ----------- | ----------- |
| **Strava API** (OAuth) | `/etc/strava-my-activities.conf` | You have a Strava API subscription. See [Data-Source-Strava-API](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-Strava-API) |
| **Strava scrape mode** | `/etc/strava-my-activities.conf` (`STRAVA_MY_SOURCE=scrape`) | No subscription — uses the browser session cookie. See [Data-Source-Scrape-Mode](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-Scrape-Mode) |
| **HealthSync / Google Drive** | `/etc/healthsync-activities.conf` | Fully Strava-API-free — [healthsync.app](https://healthsync.app/) exports to Drive. See [Data-Source-HealthSync](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-HealthSync) |

## Pages

| Page | URL | What it shows |
| ---- | --- | ------------- |
| **Club leaderboard** | `/strava/` | Monthly/yearly distance ranking for your Strava club, filterable by year and month |
| **My Activities** | `/strava/me/` | Sortable activity table with year/month/sport filters, bests strip, and monthly bar charts |
| **Activity detail** | `/strava/me/activity.html` | Stat cards, interactive route map (Leaflet + OSM), per-km splits, elevation, HR, cadence charts |
| **Personal stats** | `/strava/me/stats.html` | Aggregate KPIs, year-over-year heatmap, personal records, sport breakdown, day-of-week chart |
| **Activity heatmap** | `/strava/me/heatmap.html` | Full-viewport Leaflet heat overlay of all GPS routes; period + sport-type filter, city label overlay |
| **Bike service** | `/strava/me/bike.html` | Maintenance log per bike: parts, service types with km/hour/calendar thresholds, auto-mileage, cost tracking |

## Features

**My Activities dashboard**
- Sortable table: distance, time, elevation, avg/max speed, VAM, avg HR, avg power, work (kJ)
- Year/month/sport-type filters; period "bests" strip (longest, most climbing, fastest, best VAM, most work)
- Monthly bar charts for distance, time, and elevation — all client-side from a single JSON file

**Activity detail**
- Interactive route map (Leaflet + OpenStreetMap), per-km splits bar chart, elevation profile, HR chart, cadence chart
- Stat cards: pace/speed, VAM, normalized power + variability index, work, calories, relative effort, gear; Walk/Hike activities additionally show **estimated total steps** (cadence × 2 × moving time)
- Weather: temperature, feels-like, wind speed + direction, WMO code icon, precipitation — from [Open-Meteo](https://open-meteo.com/) per activity date + GPS location

**Club leaderboard**
- Month/year filter, multiple clubs (`STRAVA_CLUB_IDS`), ranked by distance with avg speed
- Per-club sections: filtered-period tiles, Top 5 year athletes, single-activity highlights (fastest / longest / most elevation), this-year summary, all-time club totals
- Accumulating store — deduplicated daily, filter back through full history

**Personal stats**
- KPI cards, year overview table, monthly breakdown chart, year-over-year km/month heatmap
- **Annual Goals** — set a yearly ride distance target per year; progress bar + projected year-end km + monthly breakdown (green = hit, orange = current, blue = past)
- **Personal records** — longest ride, most climbing, fastest avg speed, best VAM, most power, most energy (kJ), most steps (Walk/Hike), best week, best month by km and by count, longest streak — all-time across all sports; each record links to the activity

**Activity heatmap**
- Full-viewport dark map (Esri World Dark Gray + OSM fallback) showing all GPS activity routes as a heat overlay
- Period filter: Last 3 months (default), Last 30 days, Last 7 days, All time, or individual years
- Sport-type filter: defaults to Ride; dynamically populated from your data; "All sports" option
- City label overlay on a separate Leaflet pane (z-index 450) so names stay readable above the heat layer
- Point count and activity count shown in the top bar; fits the map to visible tracks

**Bike service tracker**
- Parts with multiple named service types, each with independent km / riding-hours / calendar-time thresholds
- Mileage auto-computed from `activities.json` rides; gear mapping per bike; calendar picker for any date
- Replace flow: old part moves to Archived with final mileage + calendar duration; successor fitted on same day
- **Bike comparison** — when 2+ bikes exist, a "Bike Statistics" section compares all bikes side by side (distance, ride time, elevation, avg ride, services, current parts)
- **Cost tracking** — optional purchase price per part and cost per service; total and per-year summary shown in the bike header; currency set via `STRAVA_MY_CURRENCY` in the config (default `PLN`)
- **Email alerts** — per-part checkbox in the Edit modal; set `STRAVA_MY_BIKE_EMAIL` in the config to activate sending; warning at ≥ 90%, alert at ≥ 100% of any threshold; each tier fires once, alert re-sends weekly while overdue
- Saves via a small CGI — daily cron never touches your data

**Data management**
- Historical sync: renamed rides, corrected sport types, deleted activities all reflected automatically
- Per-activity detail backfill: fetches full activity JSON (`/activities/{id}`) gradually over nightly runs
- Scrape mode: auto-exports GPX per activity; cookie health banner (green/amber/red) shows renewal status
- HealthSync + Magene dual-source: watch HR merged with wheel-sensor distance from Magene FIT files

**Section reordering** *(desktop only)*
- Drag any section heading (⠿ handle) to a new position on the Personal stats, Activity detail, Bike service, and Club leaderboard pages
- ↺ Reset order button restores the default section layout
- Order is saved per page in `localStorage` and restored on the next visit
- Not available on touch/mobile devices (handle and reset button are hidden)

**Dark mode**
- Every page (except the always-dark heatmap) has a 🌙/☀️ toggle button in the top-right corner
- Defaults to the OS `prefers-color-scheme` setting; manual choice is remembered in `localStorage` across sessions
- Full CSS variable conversion — SVG charts, bar fills, tooltips, and all UI elements adapt without re-rendering

**Cron self-healing** (via `strava-cron-guard`)
- Network pre-flight: pings a configurable IP before each run; if unreachable, waits up to `STRAVA_NET_CHECK_WAIT` seconds (default 2 min) for the WAN to come back, then aborts cleanly — no false-positive alerts during a brief reconnect
- Automatic retry: re-runs the script up to `STRAVA_CRON_RETRIES` times (default 2) with `STRAVA_CRON_RETRY_DELAY` seconds (default 5 min) between attempts; alert email is only sent after all retries are exhausted, and the subject line reports the total attempt count

Full feature details: [Features](https://github.com/raczeja/StatsServiceBook/wiki/Features)

## Screenshots

| Club dashboard | My Activities dashboard |
| :------------: | :---------------------: |
| ![Club dashboard](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/club-dashboard.png) | ![My Activities](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/my-activities.png) |

| Personal stats | Activity detail (map + splits) | Bike service tracker |
| :------------: | :----------------------------: | :------------------: |
| ![My Stats](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/stats.png) | ![Activity detail](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/activity-detail.png) | ![Bike service](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/bike-service.png) |

| Activity heatmap |
| :--------------: |
| ![Heatmap](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/heatmap.png) |

### Dark mode

| My Activities (dark) | Personal stats (dark) |
| :------------------: | :-------------------: |
| ![My Activities dark](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/my-activities-dark.png) | ![Stats dark](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/stats-dark.png) |

| Activity detail (dark) | Bike service (dark) |
| :--------------------: | :-----------------: |
| ![Activity detail dark](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/activity-detail-dark.png) | ![Bike service dark](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/bike-service-dark.png) |

| Club leaderboard (dark) |
| :---------------------: |
| ![Club leaderboard dark](https://raw.githubusercontent.com/raczeja/StatsServiceBook/main/test/screenshots/club-dashboard-dark.png) |

> Screenshots generated from sample data via `node test/take-screenshots.mjs` (or `powershell -File test/make-screenshots.ps1` on Windows).

## Quick start

**1. Install on the router** (run from the repo root on your PC):

```powershell
scp -r . root@192.168.1.1:/tmp/strava
ssh root@192.168.1.1 sh /tmp/strava/install.sh
```

**2. Edit the config** (choose one data source):

```sh
vi /etc/strava-my-activities.conf     # Strava API or scrape mode
# — or —
vi /etc/healthsync-activities.conf    # HealthSync / Google Drive
```

**3. Run once to verify:**

```sh
strava-my-activities      # (or: healthsync-activities)
strava-leaderboard
```

A healthy run ends with `done.`. Any `ERROR:` line means the run aborted — check credentials.

**4. Browse:**
- My Activities: `http://<router-ip>/strava/me/`
- Club leaderboard: `http://<router-ip>/strava/`

**5. Cron is already installed** (23:50 leaderboard, 23:55 my-activities, Warsaw time). Check with `crontab -l`.

For full install options, path variables, and post-install verification see [Installation](https://github.com/raczeja/StatsServiceBook/wiki/Installation).

## Docker Hub

The easiest way to run StatsServiceBook on any machine (Linux, Mac, Windows, Raspberry Pi):

```sh
# 1. Copy and fill in config template(s):
cp docker/strava-my-activities.conf.example my-activities.conf
# edit my-activities.conf — add CLIENT_ID / CLIENT_SECRET / REFRESH_TOKEN

# Optional: club leaderboard
cp docker/strava-leaderboard.conf.example leaderboard.conf
# edit leaderboard.conf — add CLIENT_ID / CLIENT_SECRET / REFRESH_TOKEN / CLUB_IDS

# Optional: HealthSync / Google Drive (Strava-API-free)
# cp docker/healthsync-activities.conf.example healthsync.conf

# 2. Start:
docker compose up -d

# 3. Open http://localhost/strava/me/
```

Or without compose:

```sh
docker run -d --name statsservicebook \
  -p 80:80 \
  -v "$(pwd)/my-activities.conf:/etc/strava-my-activities.conf:ro" \
  -v statsservicebook_data:/data \
  -e TZ=Europe/Warsaw \
  -e RUN_ON_START=1 \
  jraczek/statsservicebook:latest
```

Supported architectures: `amd64`, `arm64`, `arm/v7` (Raspberry Pi).
Full setup, config options, and docker-compose reference: [Docker](https://github.com/raczeja/StatsServiceBook/wiki/Docker).

## Running locally (Docker / WSL)

Quick preview with sample data — no credentials needed:

```sh
podman build -f test/Containerfile -t stravame-test .
podman run --rm -p 8080:8080 stravame-test
# Open http://localhost:8080/strava/me/
```

Run functional tests:

```powershell
powershell -ExecutionPolicy Bypass -File .\test\run-tests.ps1
```

Full instructions for running with real credentials, HealthSync, or Windows WSL: [Running-Locally](https://github.com/raczeja/StatsServiceBook/wiki/Running-Locally).

## Requirements

- OpenWrt 21.02+ on the router, SSH access as `root`
- Free space for `curl`, `jq`, `ca-bundle` (~1–2 MB); use [extroot](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration) on tight 128 MB flash
- A Strava account that is a member of the club you want to rank (for club leaderboard)
- Node.js ≥ 18 and PowerShell Core (`pwsh`) for running the test suite locally

## Documentation

| Wiki page | Contents |
| --------- | -------- |
| [Home](https://github.com/raczeja/StatsServiceBook/wiki) | Index of all wiki pages |
| [Features](https://github.com/raczeja/StatsServiceBook/wiki/Features) | Detailed description of every feature across all five pages |
| [Installation](https://github.com/raczeja/StatsServiceBook/wiki/Installation) | Full install guide, path variables, scheduling, verification |
| [Data-Source-Strava-API](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-Strava-API) | Create Strava app, one-time OAuth, token handling |
| [Data-Source-Scrape-Mode](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-Scrape-Mode) | My Activities scrape mode, Club leaderboard scrape mode, session cookie |
| [Data-Source-HealthSync](https://github.com/raczeja/StatsServiceBook/wiki/Data-Source-HealthSync) | Google Drive OAuth, HealthSync setup, Magene FIT, dual-source detection |
| [Docker](https://github.com/raczeja/StatsServiceBook/wiki/Docker) | Docker Hub quick start, config templates, docker-compose, publishing |
| [Running-Locally](https://github.com/raczeja/StatsServiceBook/wiki/Running-Locally) | Docker preview, real-data Docker, WSL, HealthSync local test |
| [Email-Notifications](https://github.com/raczeja/StatsServiceBook/wiki/Email-Notifications) | Bike service alerts, monthly/weekly/yearly leaderboard email, cron error alerts, Gmail App Password |
| [Upgrading](https://github.com/raczeja/StatsServiceBook/wiki/Upgrading) | Binary-only scp deploy, full reinstall, surviving sysupgrade |
| [Switching-Data-Sources](https://github.com/raczeja/StatsServiceBook/wiki/Switching-Data-Sources) | API → scrape mode, Strava → HealthSync migration steps |
| [Operations](https://github.com/raczeja/StatsServiceBook/wiki/Operations) | Full file/URL reference, limitations, rate limits |
