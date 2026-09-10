# Installation

This guide covers installing StravaStats on an OpenWrt router from scratch.

## Prerequisites

- OpenWrt 21.02+ with SSH access as `root`
- ~1–2 MB free space for `curl`, `jq`, `ca-bundle` and their libs
- The repo cloned or downloaded to your PC

## Step 1 — Find your router IP and confirm SSH

Your router's LAN/gateway IP is usually `192.168.1.1`. On Windows:

```powershell
ipconfig | Select-String "Default Gateway"
```

SSH must be enabled (LuCI → System → Administration → SSH Access, or on by default on a fresh OpenWrt). Test:

```powershell
ssh root@192.168.1.1
exit
```

Windows 10/11 ship with `ssh` and `scp` built in. If not found, enable Settings → Apps → Optional features → OpenSSH Client.

## Step 2 — Copy the repo and run the installer

From the repo root on your PC:

```powershell
scp -r . root@192.168.1.1:/tmp/strava
ssh root@192.168.1.1 sh /tmp/strava/install.sh
```

Optional overrides:

```sh
CRON_TIME="0 6 * * *" sh /tmp/strava/install.sh     # different cron time
TZ_POSIX="" sh /tmp/strava/install.sh               # don't change router timezone
```

### What install.sh does

- Installs deps `curl jq ca-bundle` (auto-detects `apk` on OpenWrt 24.10+/snapshots, or `opkg` on older releases)
- Installs `strava-leaderboard` to `/usr/bin/strava-leaderboard`
- Installs `strava-my-activities` to `/usr/bin/strava-my-activities`
- Installs `healthsync-activities` to `/usr/bin/healthsync-activities`
- Installs all HTML helper scripts to `/usr/bin/`
- Drops config templates at `/etc/strava-leaderboard.conf`, `/etc/strava-my-activities.conf`, `/etc/healthsync-activities.conf`
- Sets the router timezone to **Europe/Warsaw** (POSIX `CET-1CEST,M3.5.0,M10.5.0/3`, DST-aware)
- Adds cron entries: leaderboard at **23:50**, my-activities at **23:55**, healthsync at **23:55** (Warsaw time), then (re)starts cron
- Creates `HEALTHSYNC_STATE_DIR` if set in an existing config (safe for USB mounts)

**Config files are never overwritten.** If a config already exists, `install.sh` leaves it untouched. Re-running after an upgrade is safe.

**Both my-activities and healthsync are scheduled.** They write to the same output directory, so only run one at a time. When you switch to HealthSync, remove the strava-my-activities cron line:

```sh
crontab -l | grep -v 'strava-my-activities' | crontab -
```

## Step 3 — If the dependency install fails for lack of space

The writable overlay on a 128 MB flash device is only ~16 MB. Check free space:

```sh
df -h /overlay
```

If it is tight, consider [extroot / a USB drive](https://openwrt.org/docs/guide-user/additional-software/extroot_configuration) and point `STRAVA_STATE_DIR` at it.

A failed package-list update (`apk update` / `opkg update`) usually means no internet or DNS on the router. Check with `ping -c1 downloads.openwrt.org`.

You can also move **web output** and **state** off flash by setting path variables in the config:

| Config | State dir variable | Web dir variable |
| ------ | ------------------ | ---------------- |
| `/etc/strava-my-activities.conf` | `STRAVA_MY_STATE_DIR` | `STRAVA_MY_WEB_DIR` |
| `/etc/strava-leaderboard.conf` | `STRAVA_STATE_DIR` | `STRAVA_WEB_DIR` |
| `/etc/healthsync-activities.conf` | `HEALTHSYNC_STATE_DIR` | `HEALTHSYNC_WEB_DIR` |

Example for a USB drive at `/mnt/sda5`:

```sh
HEALTHSYNC_STATE_DIR="/mnt/sda5/healthsync"
HEALTHSYNC_BIKE_DATA="/mnt/sda5/healthsync/bike-service.json"
HEALTHSYNC_BIKE_ASSIGN="/mnt/sda5/healthsync/bike-assignments.json"
```

`uhttpd` only serves `/www`, so `install.sh` recreates the bridging symlinks under `/www/strava` on every run, and creates `HEALTHSYNC_STATE_DIR` if it does not exist. Re-run `install.sh` after changing any path.

## Step 4 — Edit config and run once to verify

**Club leaderboard:**

```sh
vi /etc/strava-leaderboard.conf    # fill in client id/secret, refresh token, club id(s)
strava-leaderboard                 # run once now to verify
```

Browse to `http://<router-ip>/strava/`. For credentials setup see [Data-Source-Strava-API](Data-Source-Strava-API.md) or [Data-Source-Scrape-Mode](Data-Source-Scrape-Mode.md).

**My Activities:**

```sh
vi /etc/strava-my-activities.conf   # fill in credentials
strava-my-activities                # run once now to verify
```

Browse to `http://<router-ip>/strava/me/`.

**HealthSync / Google Drive:**

```sh
vi /etc/healthsync-activities.conf  # fill in GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
                                    # GOOGLE_REFRESH_TOKEN, DRIVE_FOLDER_ID
healthsync-activities               # run once now to verify
```

See [Data-Source-HealthSync](Data-Source-HealthSync.md) for the Google OAuth setup steps.

## Step 5 — Verify it ran

A healthy run ends with `done.`:

```
2026-06-01 23:50:01 reusing cached access token (valid for 18230s more)
2026-06-01 23:50:01 fetching club 1234567 activities (up to 5 pages)...
2026-06-01 23:50:02   page 1: 143 activities
2026-06-01 23:50:02   short page, stopping
2026-06-01 23:50:02 club 1234567: +12 new (firstSeen 2026-06-01), 387 total
2026-06-01 23:50:03 wrote /www/strava/activities.json and per-club leaderboard JSON (snapshot 20260601)
2026-06-01 23:50:03 wrote /www/strava/index.html
2026-06-01 23:50:03 done.
```

Any line starting with `ERROR:` means the run aborted. Common causes: wrong `STRAVA_REFRESH_TOKEN` (`token refresh request failed`), bad `STRAVA_CLUB_IDS` (`activities fetch failed`), or `curl`/`jq` not installed.

To check **scheduled** (cron) runs:

```sh
tail -n 40 /var/log/strava-leaderboard.log
tail -n 40 /var/log/strava-my-activities.log
```

If the log is missing or empty after the scheduled time:

```sh
crontab -l | grep strava        # is the cron line installed?
/etc/init.d/cron status         # is the cron daemon running?
logread | grep cron             # did cron actually fire the job?
date                            # is the router clock/zone right?
```

Note: `/var/log` lives in RAM (tmpfs) on OpenWrt, so logs are cleared on reboot. To keep logs across reboots, point cron redirects at persistent storage, e.g. `>> /mnt/sda5/strava-leaderboard.log 2>&1` via `crontab -e`.

## Scheduling

Cron runs daily: leaderboard at **23:50**, my-activities at **23:55**, both in Warsaw time. OpenWrt's cron uses the router's local timezone, so `install.sh` sets it to `Europe/Warsaw`. Verify with `date`.

To change the times:

```sh
crontab -e
# 50 23 * * *  /usr/bin/strava-cron-guard strava-leaderboard   >> /var/log/strava-leaderboard.log 2>&1
# 55 23 * * *  /usr/bin/strava-cron-guard strava-my-activities >> /var/log/strava-my-activities.log 2>&1
# 0  8  1 * *  /usr/bin/strava-email-monthly                   >> /var/log/strava-email-monthly.log 2>&1
```

Or reinstall with custom times:

```sh
CRON_TIME="0 6 * * *" CRON_TIME_ME="5 6 * * *" sh install.sh
```

Use `TZ_POSIX="" sh install.sh` to leave the router's timezone untouched.
