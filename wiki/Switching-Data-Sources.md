# Switching Data Sources

---

## Switching from Strava API to scrape mode

Use this when your Strava API subscription lapses (or when the Club Activities API is deprecated after 2026-09-01).

See [Data-Source-Scrape-Mode](Data-Source-Scrape-Mode.md) for complete step-by-step instructions. Summary:

1. Get a `_strava4_session` cookie from your browser DevTools
2. Set `STRAVA_MY_SOURCE="scrape"` and `STRAVA_SESSION_COOKIE="..."` in `/etc/strava-my-activities.conf` (for My Activities), or `STRAVA_SOURCE="scrape"` and `STRAVA_SESSION_COOKIE="..."` in `/etc/strava-leaderboard.conf` (for the club leaderboard)
3. For the club leaderboard, set `STRAVA_SCRAPE_START_DATE` to avoid overlap duplicates at transition
4. Deploy updated scripts: `scp strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh`
5. Run once to verify: `strava-leaderboard`

Switching is non-destructive: existing activities are matched by Strava ID and updated in place.

---

## Switching from Strava to HealthSync (keeping full history)

HealthSync only keeps approximately 30 days of exports on Google Drive. If you switch cold — just change which script cron runs — the HealthSync dashboard will start from scratch and show only recent activities.

To carry over your full Strava history, use `HEALTHSYNC_IMPORT_STRAVA_STORE`.

### Why not just run both scripts?

Both `strava-my-activities.sh` and `healthsync-activities.sh` write to the same `WEB_DIR` (`/www/strava/me`). Whichever runs last overwrites `activities.json` and all HTML — you'd see only one source's activities. The migration approach below is the right path: merge the Strava store into HealthSync once, then switch cron.

### Migration steps

**1. Configure HealthSync with Google credentials and the Strava store path:**

```sh
vi /etc/healthsync-activities.conf
```

Add:

```sh
HEALTHSYNC_IMPORT_STRAVA_STORE="/usr/lib/strava-my-activities/activities.ndjson"
```

(Adjust the path if your `STRAVA_MY_STATE_DIR` differs — the default on this project's router is `/mnt/sda5/strava-my-activities/`.)

Also fill in your Google OAuth credentials and `DRIVE_FOLDER_ID`. See [Data-Source-HealthSync](Data-Source-HealthSync.md) for the full Google OAuth setup.

**2. Run once — imports Strava history, downloads new HealthSync activities, renders HTML:**

```sh
healthsync-activities
```

Verify the log output:
- `Strava history: 1234 activities merged from …`
- `store: N activities total`

**3. Switch cron — healthsync is already scheduled by install.sh; just remove strava-my-activities:**

```sh
crontab -l | grep -v 'strava-my-activities' | crontab -
```

### How the merge works

`HEALTHSYNC_IMPORT_STRAVA_STORE` is **idempotent** — safe to leave in place permanently.

- Strava IDs are numeric (`18784255013`); HealthSync IDs are date strings (`2026-06-22-20-01-ride`) — they never collide, so there is no risk of mixing up or duplicating activities across the two sources.
- On each run, `healthsync-activities` reads the Strava NDJSON file and appends any records whose ID is not yet in the HealthSync store.

The Strava detail JSON files (per-activity maps and splits) stay in `DETAIL_DIR` (`/www/strava/me/details/` by default) and are served by the HealthSync dashboard unchanged — numeric Strava IDs still link correctly from the activity list. New HealthSync activities use GPX files cached in `$WEB_DIR/gpx/` instead.

### Important: keep Strava cron running until your API access ends

Every daily Strava run adds activities to `activities.ndjson`. The more history you accumulate before switching, the more complete the HealthSync dashboard will be from day one. Do not switch cron early.

### Important: do not delete the Strava NDJSON after switching

`/usr/lib/strava-my-activities/activities.ndjson` is the migration source that `HEALTHSYNC_IMPORT_STRAVA_STORE` reads on every run. It is safe to leave it in place — it will not change once the Strava API is gone, and it takes up almost no flash space. Deleting it would prevent future `healthsync-activities` runs from re-importing history (e.g. after a router reset).
