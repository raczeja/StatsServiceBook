# StravaStats for OpenWrt — Wiki

Router-native activity stats and bike service tracker. POSIX shell scripts + curl + jq. Three data sources: Strava API, Strava scrape mode, HealthSync/Google Drive.

## Pages

| Page | Description |
| ---- | ----------- |
| [Installation](Installation.md) | Full install guide: copy repo, run install.sh, edit config, verify, scheduling |
| [Data-Source-Strava-API](Data-Source-Strava-API.md) | Create a Strava API app, one-time OAuth flow, token handling |
| [Data-Source-Scrape-Mode](Data-Source-Scrape-Mode.md) | My Activities scrape mode and Club leaderboard scrape mode — session cookie, no subscription needed |
| [Data-Source-HealthSync](Data-Source-HealthSync.md) | HealthSync / Google Drive setup, Magene FIT files, dual-source detection, token expiry |
| [Running-Locally](Running-Locally.md) | Docker/Podman preview with sample data, real-credentials Docker, Windows WSL |
| [Email-Notifications](Email-Notifications.md) | Monthly leaderboard email, cron error alerts, Gmail App Password setup |
| [Upgrading](Upgrading.md) | Binary-only scp deploy, full install.sh re-run, surviving an OpenWrt sysupgrade |
| [Switching-Data-Sources](Switching-Data-Sources.md) | Switch from Strava API to scrape mode; migrate full history to HealthSync |
| [Operations](Operations.md) | Complete file and URL reference, limitations, rate limits, persistent storage notes |
