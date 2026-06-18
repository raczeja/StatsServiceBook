# StravaStats for OpenWrt

A router-native port of StravaStats' leaderboard, sized for a router-class device running OpenWrt.

This is a single POSIX shell script driven by **cron**, using **`curl`** to talk to the
Strava API and **`jq`** to aggregate. The result is written as a static HTML page
(plus JSON) into **uhttpd's** web root, so the router's built-in web server serves
it with no extra daemon and almost no RAM.

```
cron (23:50) ──► strava-leaderboard.sh
                   │  1. refresh access token (curl)
                   │  2. page club activities feed (curl)
                   │  3. merge into activity store (jq)  ← mirrors activityStore.ts
                   │       dedupe by signature, stamp firstSeen = today's date
                   │  4. emit activities.json + all-time leaderboard.json (+ snapshot)
                   └► 5. render static /www/strava/index.html
                                    │
   browser on LAN ◄── uhttpd ◄──────┘   http://<router-ip>/strava/
                   │
                   └─ page fetches activities.json and filters by year/month
                      (defaulting to the current month) entirely in the browser

cron (23:55) ──► strava-my-activities.sh
                   │  1. refresh access token (curl)
                   │  2. page /athlete/activities feed (curl)
                   │       real Strava IDs + real dates (start_date_local)
                   │  3. merge into activity store (jq)
                   │       dedupe by Strava activity ID — no approximation
                   └► 4. render static /www/strava/me/{index,activity,stats,bike}.html
                                    │
   browser on LAN ◄── uhttpd ◄──────┘   http://<router-ip>/strava/me/
                   │
                   ├─ index.html  — sortable table + monthly bar charts
                   ├─ activity.html — per-activity detail (map, splits)
                   ├─ stats.html  — KPIs, year comparison, records, DOW chart
                   └─ bike.html   — bike service tracker (reads/writes via CGI)
```

## Screenshots

|                     Club dashboard                     |
| :----------------------------------------------------: |
| ![Club dashboard](test/screenshots/club-dashboard.png) |

|               My Activities dashboard                |         Personal stats summary          |
| :--------------------------------------------------: | :-------------------------------------: |
| ![My Activities](test/screenshots/my-activities.png) | ![My Stats](test/screenshots/stats.png) |

|              Activity detail (map + splits)              |                Bike service tracker                |
| :------------------------------------------------------: | :------------------------------------------------: |
| ![Activity detail](test/screenshots/activity-detail.png) | ![Bike service](test/screenshots/bike-service.png) |

> Screenshots generated from sample data via `powershell -File test/make-screenshots.ps1`.

## Why it differs from the main app

- **No Node, no React, no build step.** Just `sh` + `curl` + `jq`.
- **No OAuth callback server.** You authorize once on your PC and store a
  long-lived refresh token in a config file; the script refreshes the access
  token itself on every run (and persists the rotated refresh token).
- **Accumulating activity store + month/year filtering (club leaderboard).**
  Strava's `/clubs/{id}/activities` feed returns **no dates and no activity
  IDs** — it's just the club's _recent_ activities. So each daily run merges
  the feed into a persistent store (`activities.ndjson`), deduping by a content
  signature and stamping every newly seen activity with **today's date** as its
  "first seen" day. With a daily cron and a feed that spans ~2 weeks, that date
  tracks the performed day to within the polling interval — enough to **filter
  the dashboard by year and month** (defaulting to the current month), which the
  live app and earlier versions of this script couldn't do. This mirrors
  [activityStore.ts](../server/src/services/activityStore.ts) in the main app.
- **My Activities dashboard (individual athlete).** The
  `/athlete/activities` endpoint returns full activity objects with real Strava
  IDs and real dates (`start_date_local`), so **no first-seen approximation is
  needed**. Activities are deduped by Strava ID, not content signature. The
  resulting dashboard offers year/month/sport-type filters, a sortable table
  (distance, time, elevation, avg/max speed, **VAM** climb rate, avg HR, avg
  power, work in kJ), a period **"bests"** strip (longest ride, most climbing,
  fastest avg, best VAM, most work), and monthly bar charts for distance, time,
  and elevation — all rendered client-side from a single JSON file. The
  power/HR/VAM columns are populated for activities that carry that data (e.g.
  rides with a power meter) and show "—" otherwise.
- **Per-activity detail backfill (My Activities).** Beyond the summary feed,
  each run also fetches the _full_ activity object (`GET /activities/{id}`) for
  activities that don't yet have one and saves it as `<id>.json` under
  `STRAVA_MY_DETAIL_DIR` (default `…/details/`). Because Strava's read API is
  rate limited (default 100 req / 15 min, 1000 / day for a non-premium app), it
  fetches at most `STRAVA_MY_DETAIL_MAX_PER_RUN` new files per run (newest
  first), so the whole history backfills gradually over successive daily cron
  runs and new activities are picked up the next day. Activities Strava reports
  gone (HTTP 404/410) are recorded in a skip list and not retried.
- **Historical sync (My Activities).** The store isn't merely appended to — each
  run reconciles it against the feed, so changes you make on Strava show up
  locally: a renamed ride, a corrected sport type or a recalculated distance/time
  are refreshed in place, and an activity you delete on Strava is pruned from the
  dashboard (its cached detail file removed too, and changed activities have their
  detail re-fetched). Deletion is conservative — it only happens when the run
  reached the end of your feed, or, on a run capped at `STRAVA_MY_MAX_PAGES`, for
  activities inside the date window actually fetched; an empty feed never prunes.
  Set `STRAVA_MY_PRUNE_DELETED=0` to keep deletions disabled (additions and
  in-place updates still apply).
- **Activity detail page (My Activities).** Once an activity has its detail
  file, its name in the dashboard links to `activity.html?id=<id>` — a readable
  detail page (instead of raw JSON) rendered client-side from that same
  `<id>.json`. It shows core-stat cards (distance, time, stopped time,
  pace/speed, elevation, **VAM** climb rate, climb per km, heart rate, cadence,
  power including **normalized power + variability index**, work in kJ, calories,
  relative effort, temperature, gear), an interactive **route map**
  (Leaflet + OpenStreetMap), and a **per-km splits** bar chart. Cycling-specific
  metrics (VAM, power, work) appear
  only when the activity carries that data. The map needs
  internet **in the viewing browser** (Leaflet + tiles load from a CDN); the
  rest of the page works offline. A "Raw JSON" link and "Open on Strava" link
  are still provided.
- **Personal stats summary (My Activities).** A separate page at
  `http://<router-ip>/strava/me/stats.html` (linked from the My Activities
  header) with sport/year filters and: aggregate KPI cards (distance, time,
  elevation, activities, avg speed), a year overview table, a monthly breakdown
  bar chart + table, a year-over-year km-per-month heatmap, personal records
  (longest, most climbing, fastest avg, best VAM, most work — all time for the
  selected sport), a by-sport breakdown, and an average-distance-per-day-of-week
  bar chart. All computed client-side from `activities.json`.
- **Bike service tracker (My Activities).** A separate page at
  `http://<router-ip>/strava/me/bike.html` (linked from the My Activities footer)
  for tracking bike maintenance. You add **parts** to a bike (free-text name +
  note — chain, tyres, brake pads…); each records the date it was fitted and the
  bike's **mileage** at that moment. Mileage is the cumulative distance of your
  outdoor `Ride` activities up to a date, computed in the browser from
  `activities.json`; every date is a calendar picker (default today) and changing
  it **auto-recomputes** the mileage. You can **service** a part (logs a date +
  mileage + note) and **replace** it (the old part moves to an **Archived**
  section with its final mileage; optionally a successor part is fitted on the
  same day). You can track **multiple bikes**, each optionally mapped to a Strava
  **gear** so only that bike's rides count toward its mileage.
  Unlike every other page here this one **writes data back**: it reads and saves a
  single `bike-service.json` through a tiny POSIX-sh **CGI** that
  `strava-my-activities` installs to `STRAVA_MY_CGI_DIR` (uhttpd's `/www/cgi-bin`,
  served as CGI by default). The CGI is the only writer of the data file, so daily
  cron runs that regenerate the page never touch your data. There is **no auth** —
  same open-on-the-LAN posture as the other dashboards; intended for a private
  home router only.

## Testing locally with Docker / Podman

You can test all four pages locally with sample data (no Strava API credentials needed) by running the test container. This is useful for previewing the UI, testing changes, or generating screenshots.

**Prerequisites:**

- Docker or Podman installed
- PowerShell (Windows) or shell (Linux/macOS) to run the build/screenshot scripts

**a. Build and start the test container:**

```sh
# From the repo root, build the image
podman build -f test/Containerfile -t stravame-test .

# Or with Docker
docker build -f test/Containerfile -t stravame-test .
```

Then start it:

```sh
podman run --rm -p 8080:8080 stravame-test
```

**b. Open a browser and view the pages:**

- Club leaderboard: <http://localhost:8080/strava/index.html>
- My Activities dashboard: <http://localhost:8080/strava/me/index.html>
- Personal stats: <http://localhost:8080/strava/me/stats.html>
- Activity detail (map + splits): <http://localhost:8080/strava/me/activity.html?id=18784255013>
- Bike service tracker: <http://localhost:8080/strava/me/bike.html>

**c. Generate screenshots (Windows PowerShell only):**

From the repo root, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\test\make-screenshots.ps1
```

This builds the image, starts the container, captures all five pages with Puppeteer + Edge, and saves them to `test/screenshots/`. Screenshots are embedded in the README and used for documentation.

**Test data:**

- `test/activities.sample.json` — 24 sample activities (My Activities dashboard)
- `test/club-activities.sample.json` — 10 anonymized club activities (Club leaderboard)
- `test/bike-service.sample.json` — Sample bike service data with 3 bikes and maintenance history
- `test/18784255013.json` — Full detail for a sample activity (Wrocław, Poland bike ride with map and splits)

All sample data uses synthetic/anonymized names and realistic Strava IDs; no personal data is included.

## Requirements

- OpenWrt 21.02+ on the router, SSH access as `root`.
- Free space for `curl`, `jq`, `ca-bundle` and their libs (~1–2 MB). On a tight
  128 MB flash device, consider [extroot / a USB drive](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration)
  and point `STRAVA_STATE_DIR` at it.
- A Strava account that is a **member of the club** you want to rank.

## 1. Create a Strava API application

Your `CLIENT_ID` and `CLIENT_SECRET` come from a free Strava API application
(one per account). The account you use must be a **member of the club** you want
to rank.

1. Logged into Strava, go to <https://www.strava.com/settings/api>
   (or: profile → **Settings** → **My API Application**).
2. If you've never made one, fill in the form:
   - **Application Name** — anything, e.g. `RouterStats`
   - **Category** — anything, e.g. _Data Importer_
   - **Club** — leave blank
   - **Website** — anything valid, e.g. `http://localhost`
   - **Authorization Callback Domain** — **`localhost`** (must match the
     `redirect_uri=http://localhost` used in step 2)
   - Upload an image if asked, then **Create**.
3. The page now shows your credentials:
   - **Client ID** — a short number (e.g. `123456`) → `STRAVA_CLIENT_ID`
   - **Client Secret** — click _Show_ to reveal the long hex string → `STRAVA_CLIENT_SECRET`

> **Note:** Strava allows only **one API app per account** — if you already have
> one, just reuse its Client ID rather than creating a second. Keep the Client
> Secret private; it stays in the `chmod 600` config on the router, never in the
> web root.

These two values identify your _app_. To actually read the club feed you also
need a **refresh token** — get it via the one-time authorization in step 2 below
(which uses this same Client ID).

## 2. One-time authorization (get a refresh token)

Do this once on your PC. It returns a long-lived refresh token you'll paste into
the router's config.

**a.** Open this URL in a browser (replace `CLIENT_ID`):

```
https://www.strava.com/oauth/authorize?client_id=CLIENT_ID&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read
```

**b.** Click **Authorize**. Your browser will redirect to a `http://localhost/?...`
URL that fails to load — that's fine. Copy the **`code`** value out of the address
bar (`...&code=THE_CODE_HERE&scope=...`).

**c.** Exchange the code for tokens (run on any machine with `curl`):

```sh
curl -X POST https://www.strava.com/oauth/token \
  -d client_id=CLIENT_ID \
  -d client_secret=CLIENT_SECRET \
  -d code=THE_CODE_HERE \
  -d grant_type=authorization_code
```

**d.** From the JSON response, copy the value of **`refresh_token`**. That's what
goes into `STRAVA_REFRESH_TOKEN`.

## 3. Install on the router

### 3.0 Find your router's IP and confirm SSH

The OpenWrt-capable home router's LAN/gateway IP is usually **`192.168.1.1`** (ASUS firmware often
uses `192.168.50.1`; on OpenWrt it's whatever you set). On your PC:

```powershell
# Windows / PowerShell — the "Default Gateway" is your router
ipconfig | Select-String "Default Gateway"
```

SSH must be enabled on the router (LuCI → _System → Administration → SSH Access_,
or it's on by default on a fresh OpenWrt). Test the connection — the first time
you'll be asked to accept the host key, and then for the `root` password:

```powershell
ssh root@192.168.1.1
exit
```

> Windows 10/11 ship with `ssh` and `scp` built in. If `ssh` isn't found, enable
> _Settings → Apps → Optional features → OpenSSH Client_, or use PuTTY/WinSCP.

### 3.1 Copy the folder over and run the installer

Run this **from your PC**, in the `StravaStats` directory (so the `openwrt`
folder is present). Replace the IP if yours differs:

```powershell
# from /path/to/repo
scp -r openwrt root@192.168.1.1:/tmp/strava
ssh root@192.168.1.1
```

Then, **on the router** (you're now in the SSH session):

```sh
sh /tmp/strava/install.sh
```

Optional overrides when running the installer (see "Scheduling" below):

```sh
CRON_TIME="0 6 * * *" sh /tmp/strava/install.sh   # different time
TZ_POSIX="" sh /tmp/strava/install.sh             # don't change router timezone
```

The installer will:

- install deps `curl jq ca-bundle` (auto-detects **`apk`** on 24.10+/snapshots, or **`opkg`** on older releases)
- install `strava-leaderboard` to `/usr/bin/strava-leaderboard` and drop a config template at `/etc/strava-leaderboard.conf`
- install `strava-my-activities` to `/usr/bin/strava-my-activities` and drop a config template at `/etc/strava-my-activities.conf`
- set the router timezone to **Europe/Warsaw** (so cron times are local, DST-aware)
- add two daily cron entries: leaderboard at **23:50** and my-activities at **23:55** Warsaw time, and (re)start `cron`

### 3.2 If the dependency install fails for lack of space

The 128 MB flash can fill up (the writable overlay is only ~16 MB — check free
space with `df -h /overlay`). If it's tight, either install the deps to a USB
drive via
[extroot](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration)
and point `STRAVA_STATE_DIR` there, or free space by removing unused packages.
A failed package-list update (`apk update` / `opkg update`) usually means no
internet/DNS on the router — check with `ping -c1 downloads.openwrt.org`.

You can also move the **web output** off flash by pointing `STRAVA_WEB_DIR` /
`STRAVA_MY_WEB_DIR` at persistent storage (e.g. `/mnt/sda5/.../web`). `uhttpd`
only serves `/www`, so `install.sh` recreates the bridging symlinks under
`/www/strava` on every run — re-run it (or `sh install.sh`) after changing those
paths. The store (`STRAVA_STATE_DIR`) and web output can share the same disk.

## 4. Configure and run

**Club leaderboard:**

```sh
vi /etc/strava-leaderboard.conf     # fill in client id/secret, refresh token, club id
strava-leaderboard                  # run once now to verify
```

Browse to **`http://<router-ip>/strava/`**. Config options are documented inline
in [config.example](config.example) — client credentials, club id, optional
sport-type filter, page cap, output/state paths, and snapshot retention.

**My Activities:**

```sh
vi /etc/strava-my-activities.conf   # fill in client id/secret, refresh token
strava-my-activities                # run once now to verify
```

Browse to **`http://<router-ip>/strava/me/`**. Config options are documented
inline in [config-my.example](config-my.example) — client credentials, refresh
token (needs `activity:read` scope; `activity:read_all` to include private
activities), page cap, output/state paths, the per-activity detail backfill
(`STRAVA_MY_DETAIL_DIR`, `STRAVA_MY_DETAIL_MAX_PER_RUN`, `STRAVA_MY_DETAIL_SLEEP`),
historical sync (`STRAVA_MY_PRUNE_DELETED`), and the bike service tracker
(`STRAVA_MY_BIKE_DATA` — where the data is stored; `STRAVA_MY_CGI_DIR` — where the
saving CGI is installed). The bike page is at **`http://<router-ip>/strava/me/bike.html`**.

> **CGI must be served.** The bike page saves through `/cgi-bin/bike-service`.
> uhttpd serves `/www/cgi-bin` as CGI out of the box and `install.sh` ensures it
> (`uci set uhttpd.main.cgi_prefix=/cgi-bin`). If you only `scp` the script
> instead of running the installer, confirm with
> `uci get uhttpd.main.cgi_prefix` (should print `/cgi-bin`).

## 5. Verify it ran (check the logs)

Both scripts log every step with a timestamp. A **manual run** prints straight
to your terminal; **cron runs** append to their respective log files.

Run once by hand and read the output top to bottom:

```sh
strava-leaderboard       # club leaderboard
strava-my-activities     # my activities
```

A healthy run ends with `done.`:

```
2026-06-01 23:50:01 reusing cached access token (valid for 18230s more)
2026-06-01 23:50:01 fetching club 1234567 activities (up to 5 pages)...
2026-06-01 23:50:02 page 1: 143 activities
2026-06-01 23:50:02 short page, stopping
2026-06-01 23:50:02 fetched 143 activities total
2026-06-01 23:50:02 store: +12 new (firstSeen 2026-06-01), 387 activities total
2026-06-01 23:50:03 wrote /www/strava/index.html, .../activities.json and .../leaderboard.json (snapshot 20260601)
2026-06-01 23:50:03 done.
```

```
2026-06-01 23:55:01 reusing cached access token (valid for 17930s more)
2026-06-01 23:55:01 fetching athlete activities (up to 20 pages of 200)...
2026-06-01 23:55:02 page 1: 200 activities
2026-06-01 23:55:02 page 2: 87 activities
2026-06-01 23:55:02 short page, stopping
2026-06-01 23:55:02 fetched 287 activities total
2026-06-01 23:55:02 store: +3 new, ~1 updated, -0 removed, 1042 total
2026-06-01 23:55:02 wrote /www/strava/me/bike.html
2026-06-01 23:55:02 installed bike-service CGI -> /www/cgi-bin/bike-service (data: /mnt/sda5/strava-my-activities/bike-service.json)
2026-06-01 23:55:02 wrote /www/strava/me/index.html, /www/strava/me/activity.html, /www/strava/me/stats.html and /www/strava/me/activities.json
2026-06-01 23:55:02 done.
```

Any line starting with `ERROR:` means the run aborted. Common causes: a wrong
`STRAVA_REFRESH_TOKEN` (`token refresh request failed`), a bad `STRAVA_CLUB_ID`
(`activities fetch failed`), or `curl`/`jq` not installed.

To confirm the **scheduled** (cron) runs are working, read the log files:

```sh
tail -n 40 /var/log/strava-leaderboard.log      # club leaderboard: most recent run
tail -n 40 /var/log/strava-my-activities.log    # my activities: most recent run
```

If the log is missing or empty after the scheduled time, work down this list:

```sh
crontab -l | grep strava        # is the cron line installed?
/etc/init.d/cron status         # is the cron daemon running? (or: ps | grep crond)
logread | grep cron             # did cron actually fire the job?
date                            # is the router clock/zone right? (cron uses local time)
```

> **Note:** on OpenWrt `/var/log` lives in RAM (tmpfs), so these logs are
> **cleared on reboot** — they're for spot-checking recent runs, not long-term
> history. To keep logs across reboots, point the cron redirects at persistent
> storage (e.g. `>> /mnt/sda5/strava-leaderboard.log 2>&1` via `crontab -e`).

## Scheduling

Cron runs daily: leaderboard at **23:50**, my-activities at **23:55**, both in
Warsaw time. OpenWrt's cron uses the router's local timezone, so the installer
sets it to `Europe/Warsaw` (POSIX `CET-1CEST,M3.5.0,M10.5.0/3`, which follows
DST automatically). Verify with `date`.

To change the times, edit the entries directly:

```sh
crontab -e
# 50 23 * * *  /usr/bin/strava-leaderboard    >> /var/log/strava-leaderboard.log 2>&1
# 55 23 * * *  /usr/bin/strava-my-activities  >> /var/log/strava-my-activities.log 2>&1
```

…or reinstall with custom times:
`CRON_TIME="0 6 * * *" CRON_TIME_ME="5 6 * * *" sh install.sh`, or
`TZ_POSIX="" sh install.sh` to leave the router's timezone untouched.

## Upgrading an existing install

The new version is backward compatible — it reuses your existing configs, token
state, and snapshots. Nothing to migrate.

**From your PC**, in the `StravaStats` directory (replace the IP if yours
differs):

```powershell
scp -r openwrt root@192.168.1.1:/tmp/strava
ssh root@192.168.1.1
```

Then **on the router**:

```sh
sh /tmp/strava/install.sh     # overwrites both scripts, keeps configs, re-adds cron
strava-leaderboard            # run once to verify
strava-my-activities          # run once to verify
```

Re-running `install.sh` is idempotent: it overwrites both binaries, leaves
existing config files untouched, and replaces the two cron lines. If you'd
rather not touch deps/cron/timezone, you can upgrade individual scripts:

```powershell
# Club leaderboard only
scp openwrt/strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard
ssh root@192.168.1.1 "chmod 0755 /usr/bin/strava-leaderboard && strava-leaderboard"

# My activities only
scp openwrt/strava-my-activities.sh root@192.168.1.1:/usr/bin/strava-my-activities
ssh root@192.168.1.1 "chmod 0755 /usr/bin/strava-my-activities && strava-my-activities"
```

> **Tokens:** access tokens last only ~6 hours, but both scripts refresh the
> token at the start of each run and reuse a cached one only while still valid,
> so a daily cron always has a fresh token. No action needed on upgrade.

## Operations

| What                          | Where                                                                     |
| ----------------------------- | ------------------------------------------------------------------------- |
| Club leaderboard dashboard    | `http://<router-ip>/strava/`                                              |
| Club activities JSON          | `http://<router-ip>/strava/activities.json`                               |
| All-time leaderboard JSON     | `http://<router-ip>/strava/leaderboard.json`                              |
| Club activity store           | `$STRAVA_STATE_DIR/activities.ndjson`                                     |
| Dated leaderboard snapshots   | `$STRAVA_STATE_DIR/snapshots/YYYYMMDD.json`                               |
| Club token state              | `$STRAVA_STATE_DIR/token.json` (chmod 600)                                |
| Club leaderboard log          | `/var/log/strava-leaderboard.log`                                         |
| My Activities dashboard       | `http://<router-ip>/strava/me/`                                           |
| Activity detail page          | `http://<router-ip>/strava/me/activity.html?id=<id>`                      |
| Personal stats summary        | `http://<router-ip>/strava/me/stats.html`                                 |
| Bike service tracker          | `http://<router-ip>/strava/me/bike.html`                                  |
| Bike service CGI (read/write) | `http://<router-ip>/cgi-bin/bike-service`                                 |
| Bike service data store       | `$STRAVA_MY_BIKE_DATA` (default `$STRAVA_MY_STATE_DIR/bike-service.json`) |
| My activities JSON            | `http://<router-ip>/strava/me/activities.json`                            |
| Per-activity detail JSON      | `$STRAVA_MY_DETAIL_DIR/<id>.json` (default `…/strava/me/details/`)        |
| My activity store             | `$STRAVA_MY_STATE_DIR/activities.ndjson`                                  |
| Detail backfill skip list     | `$STRAVA_MY_STATE_DIR/detail-skip.txt`                                    |
| My activities token state     | `$STRAVA_MY_STATE_DIR/token.json` (chmod 600)                             |
| My activities log             | `/var/log/strava-my-activities.log`                                       |

## Limitations & notes

- **Dates are approximate.** The club feed carries no real activity dates, so
  each activity is dated by the **day the script first saw it**, not when it was
  actually performed. Run daily, that's accurate to within a day or two; an
  activity that's already older than the ~2-week feed window when you first
  install will be dated to install day. The year/month filter therefore reflects
  _first-seen_ day, and history only goes back to when you started running this.
- **The store grows over time.** The club leaderboard's `activities.ndjson` is
  append-only and never pruned (only the full-leaderboard `snapshots/` are capped
  by `STRAVA_KEEP_SNAPSHOTS`). The _My Activities_ store is instead reconciled
  with the feed each run, so it reflects edits and deletions and can shrink. For a
  club this stays small for years, but it's the one file to watch if flash is very
  tight — keep `STRAVA_STATE_DIR` on roomy persistent storage.
- **Names are truncated** by Strava in the club feed (e.g. last name as an
  initial); athletes are grouped by `firstname|lastname|profile_medium`, matching
  the main app's `buildAthleteKey`. Activities are deduped by a content
  signature of those names plus the activity's shape — so two genuinely
  identical activities by the same person collapse into one.
- **Rate limits:** Strava allows 100 requests / 15 min, 1000 / day. A daily run
  uses a handful of requests — well within limits.
- **Persistent storage:** keep `STRAVA_STATE_DIR` off `/tmp` and `/var` (RAM on
  OpenWrt). The default `/usr/lib/...` lives in the overlay and survives reboots.
- **TLS:** `ca-bundle` is required so `curl` can verify `strava.com`.

## Files

| File                                                       | Purpose                                                                  |
| ---------------------------------------------------------- | ------------------------------------------------------------------------ |
| [strava-leaderboard.sh](strava-leaderboard.sh)             | Club leaderboard: fetch feed, aggregate, render HTML                     |
| [config.example](config.example)                           | Config template → `/etc/strava-leaderboard.conf`                         |
| [strava-my-activities.sh](strava-my-activities.sh)         | My Activities: fetch own activities, merge store, source HTML helpers    |
| [strava-my-html-dashboard.sh](strava-my-html-dashboard.sh) | Renders `index.html` (sortable table + monthly bar charts)               |
| [strava-my-html-detail.sh](strava-my-html-detail.sh)       | Renders `activity.html` (Leaflet map, per-km splits, stat cards)         |
| [strava-my-html-stats.sh](strava-my-html-stats.sh)         | Renders `stats.html` (KPIs, year comparison, records, DOW chart)         |
| [strava-my-html-bike.sh](strava-my-html-bike.sh)           | Renders `bike.html` + installs the bike-service CGI                      |
| [strava-lib.sh](strava-lib.sh)                             | Shared library: `log()`, `die()`, `ensure_access_token()`                |
| [config-my.example](config-my.example)                     | Config template → `/etc/strava-my-activities.conf`                       |
| [install.sh](install.sh)                                   | Installs deps, both scripts, all helpers, both configs, and cron entries |
