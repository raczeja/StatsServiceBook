# Data Source: Scrape Mode

Scrape mode uses the same internal endpoints Strava's own web dashboard uses, authenticated with a browser session cookie (`_strava4_session`). No Strava API subscription or OAuth app required.

Two distinct scripts have scrape mode:

- **My Activities scrape mode** (`STRAVA_MY_SOURCE=scrape`) — replaces the Strava `/athlete/activities` API
- **Club leaderboard scrape mode** (`STRAVA_SOURCE=scrape`) — replaces the `/clubs/{id}/activities` API (deprecated 2026-09-01)

---

## My Activities scrape mode

### When to use

When your Strava API subscription lapses or you never had one.

### Setup

**1. Get the session cookie:**

1. Log in to [strava.com](https://www.strava.com) in any browser.
2. Open **DevTools** → **Application** → **Cookies** → `www.strava.com`.
3. Find `_strava4_session` and copy its **Value** (a long alphanumeric string).

Sessions last approximately **30 days**. When the script says `STRAVA_SESSION_COOKIE has expired`, repeat this step.

**2. Edit the config:**

```sh
vi /etc/strava-my-activities.conf
```

Add or change:

```sh
STRAVA_MY_SOURCE="scrape"
STRAVA_SESSION_COOKIE="<paste _strava4_session value here>"
```

The OAuth credentials (`STRAVA_CLIENT_ID` etc.) can remain but are ignored in scrape mode.

**3. Run once to verify:**

```sh
strava-my-activities
```

### What scrape mode does

- Uses Strava's internal `/athlete/training_activities` endpoint (the same one Strava's own dashboard uses)
- Normalizes locale-formatted distances, string times, and locale dates automatically
- Backfills per-activity detail by fetching each activity's HTML page and extracting stats (distance, time, elevation, cadence, power, gear)
- Downloads the GPX export (`/activities/{id}/export_gpx`) and saves it alongside the detail file — the interactive route map on `activity.html` renders the full GPS track via Leaflet

### Non-destructive switch

Existing activities are matched by Strava ID and updated in place — no duplicates when switching from API mode to scrape mode.

### Cookie health banner

The My Activities dashboard shows a green / amber / red banner indicating when the `_strava4_session` cookie was last verified and when it will expire (~30 days). The banner is hidden in API mode.

### Testing locally

Use the provided PowerShell helper (requires Podman):

```powershell
powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1 `
    -SessionCookie "<paste _strava4_session value>" `
    -MaxPages 3 -DetailMax 10 -KeepOutput
```

---

## Club leaderboard scrape mode

### When to use

Strava removes the `/clubs/{id}/activities` API on **2026-09-01**. Switch to `STRAVA_SOURCE=scrape` when the API stops responding.

Scrape mode gives **real activity dates and Strava IDs** (not first-seen approximations).

### Step 1 — Get a session cookie

1. Log in to [strava.com](https://www.strava.com) in any browser.
2. Open **DevTools** → **Application** → **Cookies** → `www.strava.com`.
3. Find `_strava4_session` and copy its **Value**.

Sessions last approximately **30 days**. When the script says `STRAVA_SESSION_COOKIE has expired`, repeat this step.

### Step 2 — Update the config

```sh
vi /etc/strava-leaderboard.conf
```

Add or change:

```sh
STRAVA_SOURCE="scrape"
STRAVA_SESSION_COOKIE="<paste _strava4_session value here>"
STRAVA_CLUB_IDS="123456,789012"
```

The OAuth credentials can remain but are ignored in scrape mode.

### Step 3 — Avoid overlap duplicates at transition

The Strava club feed covers roughly the last 3–4 weeks of activity. Those same activities are already in the store from the API's last few runs (with content-hash signatures). On the first scrape run, the dedup check looks for numeric IDs, not content hashes — those overlap-period activities would be added again.

To avoid this, set `STRAVA_SCRAPE_START_DATE` in `/etc/strava-leaderboard.conf` **before** the first scrape run:

```sh
# ~4 weeks before your switch date
STRAVA_SCRAPE_START_DATE="2026-09-01"
```

The script silently ignores any scraped activity whose actual start date is before this value. Once the overlap window has passed, you can comment this line out.

> If you skip this, the duplication resolves within one month — duplicated activities fall out of the current-month filter and only affect all-time totals briefly. It is cosmetic, not data-destroying.

### Step 4 — Deploy updated scripts

```powershell
scp strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard `
  && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh
```

No `install.sh` re-run needed unless you changed paths or cron timing.

### Healthy scrape run output

```
2026-09-15 23:50:01 reusing cached Strava CSRF token
2026-09-15 23:50:01 fetching club 123456 feed (cursor pagination)...
2026-09-15 23:50:02   page 1: 15 entries
2026-09-15 23:50:02   page 2: 14 entries
2026-09-15 23:50:03   page 3: empty, stopping
2026-09-15 23:50:03 fetched 29 entries from club 123456 (actual dates)
2026-09-15 23:50:03 club 123456: +5 new (actual dates), 412 total
2026-09-15 23:50:05 wrote /www/strava/activities.json and per-club leaderboard JSON (snapshot 20260915)
2026-09-15 23:50:05 wrote /www/strava/index.html
2026-09-15 23:50:05 done.
```

### How API history and scrape history coexist

The `.ndjson` store is additive. API-mode entries use a content-hash string as their `signature`; scrape-mode entries use the numeric Strava activity ID. They never collide:

```
# API entry — content-hash signature, approximate first-seen date:
{"signature":"jakub|r|morning ride|34300|5400|ride","firstSeen":"2026-06-15",...}

# Scrape entry — Strava activity ID signature, real date:
{"signature":12345678901,"firstSeen":"2026-08-22",...}
```

Old entries keep their first-seen dates; new scrape-mode entries get real dates going forward.

### Testing locally before the cutover

Test against real Strava data without touching the router's live leaderboard. Prerequisites: Podman (or Docker), PowerShell.

```powershell
# From the repo root:
$env:STRAVA_SESSION_COOKIE = "<paste _strava4_session value>"
$env:STRAVA_CLUB_IDS       = "123456,789012"

# Run scrape + open dashboard in browser:
powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1 -Serve

# Or just run without opening browser:
powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1
```

The `-Serve` flag starts a Python HTTP server on port 8088 (change with `-Port 9090`). The browser opens automatically. Press **Enter** to stop.

The test builds a minimal Alpine image, runs `strava-leaderboard.sh` with `STRAVA_SOURCE=scrape`, writes HTML/JSON to a Windows temp directory, and serves that directory. The router's live leaderboard is completely unaffected.
