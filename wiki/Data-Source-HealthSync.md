# Data Source: HealthSync / Google Drive

A fully Strava-API-free alternative. [healthsync.app](https://healthsync.app/) runs on Android or iPhone and exports activities to Google Drive as CSV + GPX + TCX files. `healthsync-activities.sh` downloads those files, parses them with `curl` + `jq`, and produces the exact same `activities.json` and HTML pages as `strava-my-activities.sh`.

## What HealthSync gives you

- Activity summary from CSV (distance, duration, elevation, calories, sport type)
- GPS track from GPX (rendered in-browser via Leaflet polyline, same as Strava)
- Heart rate and cadence from TCX (`<AverageCadence>` / `AvgRunCadence`), or from GPX trackpoint extensions (`<gpxtpx:cad>`) when no TCX is present
- All five pages: My Activities dashboard, activity detail (with map, splits, HR/cadence charts), personal stats, bike service tracker

Strava activity IDs are numeric; HealthSync IDs are date-based strings like `2026-06-22-20-01-ride`. All pages handle both transparently.

## Getting Google OAuth credentials

**1. Create a project and enable the Drive API:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use an existing one)
3. Enable the **Google Drive API** (APIs & Services → Enable APIs → search "Drive")

**2. Create an OAuth client:**

1. Go to APIs & Services → Credentials → Create Credentials → OAuth client ID
2. Choose **Web application** as the application type
3. Add `https://developers.google.com/oauthplayground` as an authorized redirect URI
4. Save; note the **Client ID** and **Client Secret**

**3. Add yourself as a test user:**

1. Go to APIs & Services → OAuth consent screen
2. Under Test users, add your Google account email
3. This lets you authorize without publishing the app (see note on token expiry below)

**4. Get a refresh token via OAuth Playground:**

1. Go to [OAuth Playground](https://developers.google.com/oauthplayground)
2. Click the gear icon → check **Use your own OAuth credentials**
3. Enter your Client ID and Client Secret
4. In Step 1, find **Drive API v3** and select `https://www.googleapis.com/auth/drive.readonly`
5. Click **Authorize APIs** and grant access
6. In Step 2, click **Exchange authorization code for tokens**
7. Copy the **Refresh token** value

> Full step-by-step with screenshots is in [config-healthsync.example](../config-healthsync.example).

## Step 2 — Edit the config

```sh
vi /etc/healthsync-activities.conf
```

Required settings:

```sh
GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
GOOGLE_CLIENT_SECRET="GOCSPX-..."
GOOGLE_REFRESH_TOKEN="1//0..."
DRIVE_FOLDER_ID="1AbCdEfGhIjKlMnOpQrStUvWxYz"   # from the Drive folder URL
```

The `DRIVE_FOLDER_ID` is the last segment of the Google Drive folder's URL: `https://drive.google.com/drive/folders/FOLDER_ID_HERE`.

Set `HEALTHSYNC_DEFAULT_BIKE` to the name of your default bike (used as the seed when no bikes are stored yet).

## Step 3 — Run once to verify

```sh
healthsync-activities
```

A healthy run ends with `done.` and includes:

```
activities.json: N activities
drive-status.json: ok
```

## Magene FIT file support

Place `Magene_MODEL_YYYY-MM-DD_ID_*.fit` files (exported from a Magene cycling computer) in the same Google Drive folder as your HealthSync exports. On each run, `healthsync-activities.sh`:

1. Downloads new FIT files
2. Converts them to GPX via the free [GPS Visualizer](https://www.gpsvisualizer.com/) API (no account required)
3. Caches the GPX locally

Only active in `HEALTHSYNC_MODE=full` (the default).

## Dual-source detection

If a Magene FIT file covers the same ride as a HealthSync watch export (TCX/GPX) — start times match within ±10 min and end times match within ±5 min — the two records are **merged** rather than creating a separate Magene activity:

- The watch record keeps its heart-rate data (which the Magene doesn't have)
- The merged record gains the Magene's wheel-sensor-accurate distance, speed, cadence, and elevation
- The merged record carries a `dual_source:true` flag and a `magene_id` back-reference

**FIT odometer.** For a standalone Magene activity (no matching watch record), distance is extracted directly from the FIT binary's odometer field — wheel-sensor accuracy, typically more precise than GPS. Falls back to Haversine if the FIT doesn't contain usable odometer data.

## Drive token expiry and re-authorization

Google OAuth refresh tokens for apps in **Testing** mode expire after **7 days**. Apps with a **published** OAuth consent screen keep their token as long as the script runs at least once every 6 months (cron guarantees this).

When a token refresh fails, `healthsync-activities.sh` writes `drive-status.json` with `{"ok":false}` to the web dir and the My Activities dashboard shows a yellow **"Google Drive access expired"** banner.

**To re-authorize:** repeat the OAuth Playground flow (Step D in [config-healthsync.example](../config-healthsync.example)) to get a new refresh token, then update `GOOGLE_REFRESH_TOKEN` in `/etc/healthsync-activities.conf` over SSH:

```sh
ssh root@192.168.1.1
vi /etc/healthsync-activities.conf   # update GOOGLE_REFRESH_TOKEN
healthsync-activities                # verify it works
```

The banner clears on the next successful run.

> Note: Google does not support the device authorization flow for Drive scopes, and the OOB redirect was removed in 2022. The `/cgi-bin/drive-auth` CGI link is non-functional. Use the OAuth Playground flow described above.

## Skip-import mode

To re-render HTML from the existing local store without making any Drive API calls:

```sh
HEALTHSYNC_IMPORT_ENABLED=0 healthsync-activities
```

Set in the config or pass as an environment variable. Useful after editing a dashboard helper script to preview changes without re-fetching.

## Switching from Strava to HealthSync

See [Switching-Data-Sources](Switching-Data-Sources.md) for migration steps that preserve your full Strava history.
