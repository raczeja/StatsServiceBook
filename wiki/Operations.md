# Operations

## File and URL reference

| What | Where |
| ---- | ----- |
| **Club leaderboard dashboard** | `http://<router-ip>/strava/` |
| **Club activities JSON** | `http://<router-ip>/strava/activities.json` |
| **Per-club all-time JSON** | `http://<router-ip>/strava/leaderboard_<clubid>.json` |
| **Club activity store** | `$STRAVA_STATE_DIR/activities_<clubid>.ndjson` |
| **Dated leaderboard snapshots** | `$STRAVA_STATE_DIR/snapshots/YYYYMMDD_<clubid>.json` |
| **Club token state** | `$STRAVA_STATE_DIR/token.json` (chmod 600) |
| **Club leaderboard log** | `/var/log/strava-leaderboard.log` |
| **My Activities dashboard** | `http://<router-ip>/strava/me/` |
| **Activity detail page** | `http://<router-ip>/strava/me/activity.html?id=<id>` |
| **Personal stats summary** | `http://<router-ip>/strava/me/stats.html` |
| **Bike service tracker** | `http://<router-ip>/strava/me/bike.html` |
| **Bike service CGI (read/write)** | `http://<router-ip>/cgi-bin/bike-service` |
| **Bike service data store** | `$STRAVA_MY_BIKE_DATA` (default `$STRAVA_MY_STATE_DIR/bike-service.json`) |
| **My activities JSON** | `http://<router-ip>/strava/me/activities.json` |
| **Per-activity detail JSON** | `$STRAVA_MY_DETAIL_DIR/<id>.json` (default `…/strava/me/details/`) |
| **My activity store** | `$STRAVA_MY_STATE_DIR/activities.ndjson` |
| **Detail backfill skip list** | `$STRAVA_MY_STATE_DIR/detail-skip.txt` |
| **My activities token state** | `$STRAVA_MY_STATE_DIR/token.json` (chmod 600) |
| **My activities log** | `/var/log/strava-my-activities.log` |
| **HealthSync Drive auth status** | `$HEALTHSYNC_WEB_DIR/drive-status.json` (`ok:true` / `ok:false`) |
| **HealthSync re-auth CGI** | `http://<router-ip>/cgi-bin/drive-auth` (non-functional — device flow blocked for Drive scopes; use OAuth Playground + SSH instead) |
| **HealthSync log** | `/var/log/healthsync-activities.log` |

Note: on this project's router the state directories are under `/mnt/sda5/` (USB persistent storage, not flash overlay).

---

## Limitations and notes

### Dates are approximate (API mode only)

In `STRAVA_SOURCE=api` mode the club feed carries no real activity dates, so each activity is dated by the **day the script first saw it**, not when it was performed. Run daily, that is accurate to within a day or two; an activity older than the ~2-week feed window when you first install will be dated to install day.

In `STRAVA_SOURCE=scrape` mode, real activity dates are available and used directly — no approximation needed. When you switch from API to scrape mode, old entries keep their first-seen dates and new ones get real dates going forward.

### The store grows over time

Each club leaderboard store (`activities_<clubid>.ndjson`) is append-only and never pruned (only per-club `snapshots/` are capped by `STRAVA_KEEP_SNAPSHOTS`). The My Activities store is instead reconciled with the feed each run, so it reflects edits and deletions and can shrink.

For a club the store stays small for years, but it is the one file to watch if flash is very tight — keep `STRAVA_STATE_DIR` on roomy persistent storage.

### Names are truncated

Strava truncates last names to an initial in the club feed (e.g. `John D.`). Athletes are grouped by `firstname|lastname|profile_medium`, matching the main app's `buildAthleteKey`. Activities are deduped by a content signature of those names plus the activity's shape — so two genuinely identical activities by the same person collapse into one.

### Rate limits

Strava allows 100 requests / 15 min, 1000 / day for a standard (non-premium) API app. A daily cron run uses a handful of requests — well within limits.

### Persistent storage

Keep `STRAVA_STATE_DIR` off `/tmp` and `/var` — both are RAM (tmpfs) on OpenWrt and are cleared on reboot. The default `/usr/lib/...` lives in the overlay and survives reboots, but for larger datasets or USB drives point the config variables accordingly.

### TLS

`ca-bundle` is required so `curl` can verify `strava.com`. This is installed by `install.sh` automatically.

### Don't run both data-source scripts simultaneously

`strava-my-activities.sh` and `healthsync-activities.sh` have separate NDJSON stores (different state directories), so there is no storage duplication. However, both write to the same web directory (`/www/strava/me`) by default — whichever runs last overwrites `activities.json` and all HTML. The dashboard ends up showing only that source's activities.

To run both side-by-side you would need to point them at different web directories and serve at different URLs. In practice: run `strava-my-activities` while you still have API access, then switch cron to `healthsync-activities` when it ends. See [Switching-Data-Sources](Switching-Data-Sources.md) for migration steps.

### CGI must be served

The bike page saves through `/cgi-bin/bike-service`. uhttpd serves `/www/cgi-bin` as CGI out of the box and `install.sh` ensures it (`uci set uhttpd.main.cgi_prefix=/cgi-bin`). If you only `scp` the script instead of running the installer, confirm with `uci get uhttpd.main.cgi_prefix` (should print `/cgi-bin`).
