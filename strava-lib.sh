#!/bin/sh
# Shared utilities for strava-leaderboard and strava-my-activities.
# Source with:  . "$STRAVA_LIBDIR/strava-lib.sh"
# where STRAVA_LIBDIR="$(dirname "$0")" is set by the calling script.
#
# Requires (set by the calling script before sourcing):
#   TOKEN_STATE, TOKEN_REFRESH_MARGIN, STRAVA_CLIENT_ID,
#   STRAVA_CLIENT_SECRET, STRAVA_REFRESH_TOKEN, TMP
# Sets: ACCESS_TOKEN (used by the calling script after ensure_access_token)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
die() { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2; exit 1; }

# Strava access tokens live only ~6 hours (expires_in 21600). We cache the last
# token response and reuse its access_token as long as it isn't within
# TOKEN_REFRESH_MARGIN seconds of expiry; otherwise we refresh. Strava may
# rotate the refresh token on refresh, so we persist whatever it returns and
# prefer that next time, falling back to the one in the config. Sets
# ACCESS_TOKEN for the rest of the run.
ensure_access_token() {
  now="$(date +%s)"

  # Reuse the cached token if it's present and still comfortably valid.
  if [ -f "$TOKEN_STATE" ]; then
    cached_token="$(jq -r '.access_token // empty' "$TOKEN_STATE" 2>/dev/null || true)"
    cached_exp="$(jq -r '.expires_at // 0' "$TOKEN_STATE" 2>/dev/null || echo 0)"
    case "$cached_exp" in ''|*[!0-9]*) cached_exp=0 ;; esac
    if [ -n "$cached_token" ] && [ "$cached_exp" -gt "$((now + TOKEN_REFRESH_MARGIN))" ]; then
      ACCESS_TOKEN="$cached_token"
      log "reusing cached access token (valid for $((cached_exp - now))s more)"
      return 0
    fi
  fi

  # Otherwise refresh. Prefer the most recently rotated refresh token.
  refresh="$STRAVA_REFRESH_TOKEN"
  if [ -f "$TOKEN_STATE" ]; then
    saved="$(jq -r '.refresh_token // empty' "$TOKEN_STATE" 2>/dev/null || true)"
    [ -n "$saved" ] && refresh="$saved"
  fi

  log "access token missing/expiring, refreshing..."
  curl -fsS https://www.strava.com/oauth/token \
    -d client_id="$STRAVA_CLIENT_ID" \
    -d client_secret="$STRAVA_CLIENT_SECRET" \
    -d grant_type=refresh_token \
    -d refresh_token="$refresh" \
    -o "$TMP/token.json" || die "token refresh request failed"

  ACCESS_TOKEN="$(jq -r '.access_token // empty' "$TMP/token.json")"
  [ -n "$ACCESS_TOKEN" ] || die "no access_token in response: $(cat "$TMP/token.json")"

  # persist rotated refresh token + access token + expiry for the next run
  cp "$TMP/token.json" "$TOKEN_STATE"
  chmod 600 "$TOKEN_STATE"
  log "access token refreshed (valid ~$(jq -r '.expires_in // "?"' "$TMP/token.json")s)"
}
