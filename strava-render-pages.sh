# strava-render-pages.sh — sourced by strava-my-activities.sh and healthsync-activities.sh.
# Renders the four main HTML pages (dashboard, detail, bike, stats) by sourcing
# their respective helpers in order. The heatmap is always sourced separately
# at the end of each caller (GPX scan is slow; placement differs per script).
# Variables required from caller: WEB_DIR, plus STRAVA_LIBDIR (strava-my-activities)
# or LIBDIR (healthsync-activities).

# shellcheck disable=SC1090
. "${STRAVA_LIBDIR:-$LIBDIR}/strava-my-html-dashboard.sh"
# shellcheck disable=SC1090
. "${STRAVA_LIBDIR:-$LIBDIR}/strava-my-html-detail.sh"
# shellcheck disable=SC1090
. "${STRAVA_LIBDIR:-$LIBDIR}/strava-my-html-bike.sh"
# shellcheck disable=SC1090
. "${STRAVA_LIBDIR:-$LIBDIR}/strava-my-html-stats.sh"
