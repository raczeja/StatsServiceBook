# Data Source: Strava API

Use this when you have a Strava API subscription. You authorize once on your PC and store a long-lived refresh token; the script refreshes the access token itself on every run.

## Step 1 — Create a Strava API application

Your `CLIENT_ID` and `CLIENT_SECRET` come from a free Strava API application (one per Strava account).

1. Logged into Strava, go to <https://www.strava.com/settings/api> (or: profile → Settings → My API Application).
2. Fill in the form:
   - **Application Name** — anything, e.g. `RouterStats`
   - **Category** — anything, e.g. `Data Importer`
   - **Club** — leave blank
   - **Website** — anything valid, e.g. `http://localhost`
   - **Authorization Callback Domain** — **`localhost`** (must match the `redirect_uri` used in step 2)
   - Upload an image if asked, then **Create**.
3. The page shows your credentials:
   - **Client ID** — a short number (e.g. `123456`) → `STRAVA_CLIENT_ID`
   - **Client Secret** — click *Show* to reveal the long hex string → `STRAVA_CLIENT_SECRET`

> Strava allows only one API app per account. If you already have one, reuse its Client ID. Keep the Client Secret private; it lives in the `chmod 600` config on the router, never in the web root.

## Step 2 — One-time authorization (get a refresh token)

Do this once on your PC. It returns a long-lived refresh token to paste into the router's config.

**a.** Open this URL in a browser (replace `CLIENT_ID`):

```
https://www.strava.com/oauth/authorize?client_id=CLIENT_ID&response_type=code&redirect_uri=http://localhost&approval_prompt=force&scope=activity:read
```

Use `scope=activity:read_all` if you want private activities included.

**b.** Click **Authorize**. Your browser redirects to `http://localhost/?...` — that URL will fail to load. Copy the **`code`** value from the address bar (`...&code=THE_CODE_HERE&scope=...`).

**c.** Exchange the code for tokens (run on any machine with `curl`):

```sh
curl -X POST https://www.strava.com/oauth/token \
  -d client_id=CLIENT_ID \
  -d client_secret=CLIENT_SECRET \
  -d code=THE_CODE_HERE \
  -d grant_type=authorization_code
```

**d.** From the JSON response, copy the value of **`refresh_token`**. That goes into `STRAVA_REFRESH_TOKEN`.

## Step 3 — Edit the config

### My Activities

```sh
vi /etc/strava-my-activities.conf
```

Required settings:

```sh
STRAVA_CLIENT_ID="123456"
STRAVA_CLIENT_SECRET="abc123..."
STRAVA_REFRESH_TOKEN="def456..."
```

Scope `activity:read` is required; use `activity:read_all` to include private activities. All other options are documented inline in [config-my.example](../config-my.example).

### Club leaderboard

```sh
vi /etc/strava-leaderboard.conf
```

Required settings:

```sh
STRAVA_CLIENT_ID="123456"
STRAVA_CLIENT_SECRET="abc123..."
STRAVA_REFRESH_TOKEN="def456..."
STRAVA_CLUB_IDS="1234567"
```

**Multiple clubs:** set `STRAVA_CLUB_IDS="123456,789012"` (comma-separated). Each club gets its own NDJSON store and per-club leaderboard JSON; the combined `activities.json` holds all clubs and the dashboard lets you switch between them.

All other options are documented inline in [config.example](../config.example).

## Token handling

- The last token response is cached in `$STATE_DIR/token.json`.
- The cached access token is reused until it is within `STRAVA_TOKEN_REFRESH_MARGIN` seconds of expiry, then refreshed automatically.
- Strava may rotate the refresh token on refresh; the script persists whatever it returns and prefers that value next run.
- Access tokens last ~6 hours, but a daily cron always has a fresh token — no action needed on upgrade.

> The token file is written `chmod 600`. Keep the state directory (`STRAVA_MY_STATE_DIR`, `STRAVA_STATE_DIR`) on persistent storage — not on `/tmp` or `/var` (RAM on OpenWrt).

## Skip-import mode

To re-render HTML from the existing local store without making any API calls (useful after editing a dashboard helper):

```sh
STRAVA_MY_IMPORT_ENABLED=0 strava-my-activities
```

Set in the config or pass as an environment variable.
