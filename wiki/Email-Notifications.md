# Email Notifications

Two optional email features are built in. Both are no-ops when not configured. All settings go in `/etc/strava-leaderboard.conf`.

---

## Monthly leaderboard email

On the 1st of each month at 08:00, `/usr/bin/strava-email-monthly` sends a plain-text leaderboard for the previous month (one section per club) to every address in `STRAVA_EMAIL_TO`. Each address receives a separate email.

### Configuration

```sh
# /etc/strava-leaderboard.conf
STRAVA_EMAIL_SMTP="smtps://smtp.gmail.com:465"
STRAVA_EMAIL_USER="your.address@gmail.com:xxxx-xxxx-xxxx-xxxx"   # Gmail App Password
STRAVA_EMAIL_FROM="your.address@gmail.com"                        # must match the Gmail account
STRAVA_EMAIL_TO="alice@example.com,bob@example.com"
```

### Gmail App Password setup

1. Enable 2-Step Verification on your Google account
2. Go to <https://myaccount.google.com/apppasswords>
3. Generate an App Password for "Mail" / "Other"
4. Use the 16-character password in `STRAVA_EMAIL_USER` (format: `email:apppassword`)

The `From:` address must match the authenticated Gmail account — Gmail rejects mail whose `From:` differs from the logged-in user.

### Test without waiting for the 1st

```sh
STRAVA_EMAIL_TEST_MONTH=2026-07 /usr/bin/strava-email-monthly
```

Replace `2026-07` with any `YYYY-MM` value to send the leaderboard for that month.

### Data note

Leaderboard dates are *first-seen* dates in API mode (approximate) and real activity dates in scrape mode. The monthly filter uses whatever date is stored in the NDJSON activity store.

---

## Weekly leaderboard email

`/usr/bin/strava-email-weekly` sends a combined leaderboard showing the current month totals plus a "last week" column. Scheduled by cron; the last-week window is always auto-computed from today.

### Test

```sh
# Send weekly email with August month leaderboard + last-week column
STRAVA_WEEKLY_TEST_MONTH=2026-08 /usr/bin/strava-email-weekly
```

---

## Cron error alerts

All three nightly scripts are wrapped by `/usr/bin/strava-cron-guard`. When any of them exits non-zero, the guard sends an alert to every address in `STRAVA_EMAIL_ALERTS_TO`, with the script name, exit code, and the last 50 lines of output in the email body. Uses the same SMTP settings as above.

### Configuration

```sh
# /etc/strava-leaderboard.conf
STRAVA_EMAIL_ALERTS_TO="admin@example.com,ops@example.com"
```

`STRAVA_EMAIL_SMTP`, `STRAVA_EMAIL_USER`, and `STRAVA_EMAIL_FROM` must also be set.

### Test

```sh
strava-cron-guard false
```

Runs `/usr/bin/false` (exits 1) and triggers the alert if SMTP is configured.

### Cron entries

The guard is already wired into the cron lines installed by `install.sh`:

```
50 23 * * *  /usr/bin/strava-cron-guard strava-leaderboard   >> /var/log/strava-leaderboard.log 2>&1
55 23 * * *  /usr/bin/strava-cron-guard strava-my-activities >> /var/log/strava-my-activities.log 2>&1
0  8  1 * *  /usr/bin/strava-email-monthly                   >> /var/log/strava-email-monthly.log 2>&1
```

### Deploy / update the email scripts

```powershell
scp strava-cron-guard.sh root@192.168.1.1:/usr/bin/strava-cron-guard `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-monthly `
  && scp strava-email-monthly.sh root@192.168.1.1:/usr/bin/strava-email-weekly `
  && ssh root@192.168.1.1 "chmod 0755 /usr/bin/strava-cron-guard /usr/bin/strava-email-monthly /usr/bin/strava-email-weekly"
```
