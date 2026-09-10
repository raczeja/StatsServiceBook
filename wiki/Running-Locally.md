# Running Locally

The app can run on your local machine — either with sample data for a quick UI preview, or with your real credentials.

---

## Quick preview with sample data (no credentials needed)

The test container serves all five pages from bundled sample data. Nothing to configure.

**Prerequisites:** Docker or Podman installed.

```sh
# From the repo root
podman build -f test/Containerfile -t stravame-test .
podman run --rm -p 8080:8080 stravame-test

# Or with Docker:
docker build -f test/Containerfile -t stravame-test .
docker run --rm -p 8080:8080 stravame-test
```

**Open in a browser:**

- Club leaderboard: <http://localhost:8080/strava/index.html>
- My Activities dashboard: <http://localhost:8080/strava/me/index.html>
- Personal stats: <http://localhost:8080/strava/me/stats.html>
- Activity detail (map + splits): <http://localhost:8080/strava/me/activity.html?id=18784255013>
- Bike service tracker: <http://localhost:8080/strava/me/bike.html>

**Test data:** `test/activities.sample.json` (24 rides), `test/club-activities.sample.json` (10 club activities), `test/bike-service.sample.json` (3 bikes), `test/18784255013.json` (full activity detail). All synthetic/anonymized.

**Run functional regression tests:**

```powershell
powershell -ExecutionPolicy Bypass -File .\test\run-tests.ps1
```

Builds the image, runs Puppeteer assertions across all five pages and the bike-service CGI, exits 0 on pass. Requires Node.js ≥ 18 and PowerShell Core (`pwsh`) on Linux/macOS. On Linux, Puppeteer downloads and uses its bundled Chromium automatically.

Set `STRAVA_TEST_PORT` before running to force a specific host port for the container.

**Generate screenshots:**

```powershell
powershell -ExecutionPolicy Bypass -File .\test\make-screenshots.ps1
```

Builds the image, captures all five pages with Puppeteer, saves PNGs to `test/screenshots/`. `STRAVA_TEST_PORT` is also supported here.

---

## Running with real Strava data (Docker, Linux/WSL)

From the repo root:

```sh
# 1. Copy the My Activities config and fill in your credentials
cp config-my.example my-activities.conf
```

Edit `my-activities.conf` and set:

- `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_REFRESH_TOKEN` — your Strava credentials (see [Data-Source-Strava-API](Data-Source-Strava-API.md))
- `STRAVA_MY_STATE_DIR="/state"` — change from the OpenWrt default
- `STRAVA_MY_BIKE_DATA="/state/bike-service.json"` — change from the OpenWrt default
- Leave all other paths at their defaults

```sh
# 2. Fetch your activities and render HTML into named Docker volumes
docker run --rm \
  -v "$(pwd):/app:ro" \
  -e STRAVA_MY_CONFIG=/app/my-activities.conf \
  -v strava-state:/state \
  -v strava-web:/www \
  alpine:3.20 \
  sh -c "apk add --no-cache curl jq ca-certificates && sh /app/strava-my-activities.sh"

# 3. Serve — busybox httpd runs /www/cgi-bin as CGI so the bike tracker save button works
docker run --rm -p 8080:8080 \
  -v strava-web:/www \
  alpine:3.20 \
  sh -c "apk add --no-cache busybox-extras && httpd -f -p 8080 -h /www"

# Browse to http://localhost:8080/strava/me/
```

Re-run step 2 daily to keep the dashboard fresh.

> **Windows PowerShell (without WSL):** replace `$(pwd)` with `${PWD}` and use a backtick `` ` `` for line continuation instead of `\`.

> **Club leaderboard:** same pattern — copy `config.example` to `strava-leaderboard.conf`, set credentials and `STRAVA_STATE_DIR="/state"`, then run `sh /app/strava-leaderboard.sh` with `-v strava-web:/www/strava` added. Browse to `http://localhost:8080/strava/`.

---

## Docker with HealthSync / Google Drive

Use this instead of (or after) the Strava variant. Same pages, same URLs.

```sh
# 1. Copy the healthsync config and fill in your Google credentials
cp config-healthsync.example healthsync.conf
```

Edit `healthsync.conf` and set:

- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN` — see [Data-Source-HealthSync](Data-Source-HealthSync.md)
- `DRIVE_FOLDER_ID` — the ID from the Drive folder URL
- `HEALTHSYNC_STATE_DIR="/state"` — change from the OpenWrt default
- `HEALTHSYNC_BIKE_DATA="/state/bike-service.json"`

```sh
# 2. Download activities from Drive, parse, and render HTML
docker run --rm \
  -v "$(pwd):/app:ro" \
  -e HEALTHSYNC_CONFIG=/app/healthsync.conf \
  -v healthsync-state:/state \
  -v strava-web:/www \
  alpine:3.20 \
  sh -c "apk add --no-cache curl jq ca-certificates && sh /app/healthsync-activities.sh"

# 3. Serve
docker run --rm -p 8080:8080 \
  -v strava-web:/www \
  alpine:3.20 \
  sh -c "apk add --no-cache busybox-extras && httpd -f -p 8080 -h /www"

# Browse to http://localhost:8080/strava/me/
```

Re-run step 2 daily. The script only downloads files not yet in the local store — incremental runs are fast.

> **Skip-import flag:** set `HEALTHSYNC_IMPORT_ENABLED=0` (in the config or as an env var) to skip the Google Drive download and just re-render the HTML from the existing local store.

---

## Quick test with local files, no Google credentials (Podman, Windows)

`test/run-healthsync-local.ps1` lets you test HealthSync and Magene dual-source processing against local exported files — no Google Drive credentials required. Point it at a folder containing your exported HealthSync CSV/TCX/GPX files and any Magene FIT files:

```powershell
powershell -ExecutionPolicy Bypass -File test\run-healthsync-local.ps1 `
    -LocalFilesDir C:\path\to\exported\files
```

The script runs `healthsync-activities.sh` in `LOCAL_DRIVE_DIR` mode (reads files from the local folder instead of Drive), then opens the dashboard at `http://localhost:8089/strava/me/`. Press **Enter** to stop and clean up.

Accepted parameters: `-Port`, `-StateDir`, `-SkipImport`, `-KeepOutput`, `-NoBrowser`. Use `-KeepOutput` to keep the state directory between runs, then `-StateDir + -SkipImport` for re-render-only iterations.

---

## Quick test with real Google credentials (Podman, Windows)

`test/run-healthsync-podman.ps1` wraps the full cycle: runs `healthsync-activities.sh` inside Alpine, then serves the output on localhost.

**Prerequisites:** Podman installed and running (`podman machine start` on Windows).

**First run:**

```powershell
powershell -ExecutionPolicy Bypass -File test\run-healthsync-podman.ps1 `
    -Config .\config-healthsync.conf
```

Opens your browser at `http://localhost:8088/strava/me/` when the pages are ready. Press **Enter** to stop.

**With Strava history import:**

```powershell
powershell -ExecutionPolicy Bypass -File test\run-healthsync-podman.ps1 `
    -Config .\config-healthsync.conf `
    -StravaStore C:\path\to\strava-my-activities\state\activities.ndjson
```

**Keep output and re-render later:**

```powershell
# First run: keep the temp state dir
powershell -ExecutionPolicy Bypass -File test\run-healthsync-podman.ps1 `
    -Config .\config-healthsync.conf -KeepOutput

# Subsequent runs: re-render from kept state, no Drive download
powershell -ExecutionPolicy Bypass -File test\run-healthsync-podman.ps1 `
    -Config .\config-healthsync.conf `
    -StateDir C:\Users\<you>\AppData\Local\Temp\healthsync-run-<timestamp>\state `
    -SkipImport
```

The exact `-StateDir` path is printed when `-KeepOutput` is used.

**What to verify:**

- Script prints `activities.json: N activities` — confirms Drive download worked
- `drive-status.json: ok` — Google OAuth token is valid
- Dashboard opens at `http://localhost:8088/strava/me/`

If the Drive token has expired, get a new refresh token via the OAuth Playground flow (Step D in [config-healthsync.example](../config-healthsync.example)) and update `GOOGLE_REFRESH_TOKEN` in your config file before re-running.

---

## Windows WSL (Windows Subsystem for Linux)

WSL gives you a full Linux environment on Windows — the scripts run directly with no container overhead.

**a. Install WSL2 (one-time, in PowerShell as Administrator):**

```powershell
wsl --install -d Ubuntu
```

Reboot if prompted, then open the Ubuntu app from the Start menu.

**b. Install dependencies:**

```sh
sudo apt update && sudo apt install -y curl jq
```

**c. Navigate to the repo:**

```sh
cd /mnt/c/CProjektyGIT/Git_OS/StatsServiceBook   # adjust to your clone path
```

**d. Create a config with your credentials and local paths:**

```sh
cp config-my.example ~/.strava-my.conf
nano ~/.strava-my.conf
```

Set the three required credentials and change the path lines:

```sh
STRAVA_MY_WEB_DIR="$HOME/strava-web/strava/me"
STRAVA_MY_STATE_DIR="$HOME/strava-state"
STRAVA_MY_CGI_DIR="$HOME/strava-web/cgi-bin"
STRAVA_MY_BIKE_DATA="$HOME/strava-state/bike-service.json"
STRAVA_MY_DETAIL_DIR="$HOME/strava-web/strava/me/details"
```

**e. Create directories and run:**

```sh
mkdir -p ~/strava-state ~/strava-web/strava/me/details ~/strava-web/cgi-bin
STRAVA_MY_CONFIG="$HOME/.strava-my.conf" sh strava-my-activities.sh
```

The run ends with `done.`.

**f. Serve the output:**

```sh
python3 -m http.server 8080 --directory ~/strava-web
# Browse to http://localhost:8080/strava/me/
```

> **Bike service CGI:** Python's `http.server` does not execute CGI scripts, so the bike page's **Save** button won't work in this setup. Either use the Docker approach above (busybox httpd serves CGI natively), or install busybox in WSL (`sudo apt install busybox`) and serve with `busybox httpd -f -p 8080 -h ~/strava-web`.

**To keep the dashboard fresh**, add a cron job in WSL:

```sh
crontab -e
# Add (adjust path to your repo):
55 23 * * *  STRAVA_MY_CONFIG="$HOME/.strava-my.conf" sh /mnt/c/CProjektyGIT/Git_OS/StatsServiceBook/strava-my-activities.sh >> ~/strava-my-activities.log 2>&1
```

---

## Using PowerShell (pwsh) in GitHub Codespaces

Some test scripts require PowerShell (`pwsh`). To install it in a Codespaces session:

```sh
curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
rm -f /tmp/packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y --no-install-recommends powershell
pwsh
```

For automatic installation, add the `scripts/install-pwsh-in-codespaces.sh` helper to `devcontainer.json`:

```json
"postCreateCommand": "bash /workspaces/StatsServiceBook/scripts/install-pwsh-in-codespaces.sh"
```
