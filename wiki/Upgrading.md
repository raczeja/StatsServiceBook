# Upgrading

## Binary-only update (most common)

For script changes that don't involve new config keys, cron timing changes, or path changes, `scp` the updated scripts directly. No `install.sh` re-run needed.

**My Activities + HTML helpers:**

```powershell
scp strava-my-activities.sh root@192.168.1.1:/usr/bin/strava-my-activities `
  && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh `
  && scp strava-my-html-dashboard.sh strava-my-html-detail.sh strava-my-html-bike.sh strava-my-html-stats.sh root@192.168.1.1:/usr/bin/ `
  && ssh root@192.168.1.1 strava-my-activities
```

**HealthSync (also push `strava-lib.sh` — it holds the shared weather backfill):**

```powershell
scp healthsync-activities.sh root@192.168.1.1:/usr/bin/healthsync-activities `
  && scp strava-lib.sh root@192.168.1.1:/usr/bin/strava-lib.sh `
  && ssh root@192.168.1.1 healthsync-activities
```

**Club leaderboard:**

```powershell
scp strava-leaderboard.sh root@192.168.1.1:/usr/bin/strava-leaderboard `
  && ssh root@192.168.1.1 strava-leaderboard
```

**Email / cron-guard scripts (push both together; no manual run needed):**

```powershell
scp strava-cron-guard.sh root@192.168.1.1:/usr/bin/strava-cron-guard `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-monthly `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-weekly `
  && ssh root@192.168.1.1 "chmod 0755 /usr/bin/strava-cron-guard /usr/bin/strava-email-monthly /usr/bin/strava-email-weekly"
```

## Full reinstall

Run this after changes to `install.sh`, new config keys, or path changes. Re-running `install.sh` is idempotent: it overwrites all binaries, leaves existing config files untouched, and replaces the cron lines.

```powershell
scp -r . root@192.168.1.1:/tmp/strava
ssh root@192.168.1.1 sh /tmp/strava/install.sh
strava-leaderboard         # verify
strava-my-activities       # verify
```

---

## Surviving a sysupgrade (OpenWrt firmware update)

OpenWrt's `sysupgrade` wipes the overlay filesystem and reinstalls packages from scratch — **nothing installed by `install.sh` survives by default**. To protect your scripts, configs, and state data, list the paths in `/etc/sysupgrade.conf` — OpenWrt backs them up before flashing and restores them after.

### One-time setup (run on the router)

```sh
cat >> /etc/sysupgrade.conf << 'EOF'
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
/etc/strava-leaderboard.conf
/etc/strava-my-activities.conf
/etc/healthsync-activities.conf
/usr/lib/strava-leaderboard
/usr/lib/strava-my-activities
/usr/lib/healthsync
EOF
```

`/etc/sysupgrade.conf` itself is always preserved by sysupgrade — this is a one-time step.

### Post-sysupgrade restore steps

| What needs restoring | Plain sysupgrade + keep settings | Attended Sysupgrade (ASU) + keep settings |
| -------------------- | -------------------------------- | ----------------------------------------- |
| Scripts / configs / state | Automatic (from backup) | Automatic (from backup) |
| `curl`, `jq`, `ca-bundle` | **Must reinstall** | Baked into firmware — nothing to do |
| Cron entries | Automatic (`cron` package registers `/etc/crontabs/`) | Automatic |
| `/www` symlinks + CGI | **Must run `install.sh`** | **Must run `install.sh`** |

**Plain sysupgrade — post-upgrade steps:**

```sh
# Re-install packages (wiped by sysupgrade)
opkg update && opkg install curl jq ca-bundle

# Restore /www symlinks and CGI (copy repo to /tmp/strava first)
sh /tmp/strava/install.sh
```

**Attended Sysupgrade (ASU) — post-upgrade steps:**

```sh
# Packages are already in the new firmware; just restore /www symlinks and CGI
sh /tmp/strava/install.sh
```

State and configs are already back (restored from the sysupgrade backup). `install.sh` won't overwrite existing configs, so your secrets and activity history are safe.
