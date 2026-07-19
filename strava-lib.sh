#!/bin/sh
# Shared utilities for strava-leaderboard and strava-my-activities.
# Source with:  . "$STRAVA_LIBDIR/strava-lib.sh"
# where STRAVA_LIBDIR="$(dirname "$0")" is set by the calling script.
#
# Requires (set by the calling script before sourcing):
#   TOKEN_STATE, TOKEN_REFRESH_MARGIN, STRAVA_CLIENT_ID,
#   STRAVA_CLIENT_SECRET, STRAVA_REFRESH_TOKEN, TMP
# Sets: ACCESS_TOKEN (used by the calling script after ensure_access_token)

log() { logger -t strava "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
die() { logger -t strava "ERROR: $*"; echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $*" >&2; exit 1; }

# curl_retry — wraps curl with retry on network-level failure.
# Transient DNS gaps (e.g. router dnsmasq restart) clear within seconds;
# retrying with a short back-off recovers automatically.
# Config: STRAVA_CURL_RETRIES (default 3 retries), STRAVA_CURL_RETRY_DELAY (default 15s).
# Retry messages go to stderr so stdout-capturing callers like
# code="$(curl_retry ... -w '%{http_code}')" are not contaminated.
curl_retry() {
  _cr_n=0
  while true; do
    curl "$@" && return 0
    _cr_n=$((_cr_n + 1))
    [ "$_cr_n" -le "${STRAVA_CURL_RETRIES:-3}" ] || return 1
    _cr_wait=$((_cr_n * ${STRAVA_CURL_RETRY_DELAY:-15}))
    log "curl failed, retry $_cr_n/${STRAVA_CURL_RETRIES:-3} in ${_cr_wait}s..." >&2
    sleep "$_cr_wait"
  done
}

# fetch_weather_temp lat lon date  →  prints integer °C or "" on error/unavailable
# On success sets globals: _fw_temp_source ("archive"/"forecast"),
# _fw_apparent_temp (feels-like °C integer), _fw_wind_speed (km/h integer),
# _fw_wind_dir (dominant direction degrees), _fw_weathercode (WMO code),
# _fw_precipitation (mm).
# If caller sets _fw_archive_only=1, skips the forecast fallback — used by the
# upgrade path so a still-missing archive value doesn't overwrite a forecast temp.
# Tries Open-Meteo archive first (ERA5, data since 1940, ~5 day lag), then falls
# back to the forecast API (covers recent dates up to 92 days back) when the
# archive returns no value for very recent activities.
_fw_parse_weather() {
  # Parse all daily weather fields from a cached Open-Meteo JSON response ($1).
  # Populates _fw_t and the five extra globals.
  _fw_t=$(printf '%s' "$1" | jq -r '.daily.temperature_2m_mean[0] // empty | round' 2>/dev/null || true)
  [ -n "$_fw_t" ] || return 1
  _fw_apparent_temp=$(printf '%s' "$1" | jq -r '.daily.apparent_temperature_mean[0] // empty | round' 2>/dev/null || true)
  _fw_wind_speed=$(printf '%s' "$1" | jq -r '.daily.windspeed_10m_max[0] // empty | round' 2>/dev/null || true)
  _fw_wind_dir=$(printf '%s' "$1" | jq -r '.daily.winddirection_10m_dominant[0] // empty | round' 2>/dev/null || true)
  _fw_weathercode=$(printf '%s' "$1" | jq -r '.daily.weathercode[0] // empty' 2>/dev/null || true)
  _fw_precipitation=$(printf '%s' "$1" | jq -r '.daily.precipitation_sum[0] // empty' 2>/dev/null || true)
}
_fw_vars="temperature_2m_mean,apparent_temperature_mean,windspeed_10m_max,winddirection_10m_dominant,weathercode,precipitation_sum"
fetch_weather_temp() {
  [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return 1
  _fw_temp_source="" _fw_t=""
  _fw_apparent_temp="" _fw_wind_speed="" _fw_wind_dir="" _fw_weathercode="" _fw_precipitation=""
  _fw_resp=$(curl -fsS --max-time 15 \
    "https://archive-api.open-meteo.com/v1/archive?latitude=$1&longitude=$2&start_date=$3&end_date=$3&daily=${_fw_vars}&timezone=auto" \
    2>/dev/null) && _fw_parse_weather "$_fw_resp" && _fw_temp_source="archive" || true
  if [ -z "$_fw_t" ] && [ "${_fw_archive_only:-0}" != "1" ]; then
    _fw_resp=$(curl -fsS --max-time 15 \
      "https://api.open-meteo.com/v1/forecast?latitude=$1&longitude=$2&start_date=$3&end_date=$3&daily=${_fw_vars}&timezone=auto" \
      2>/dev/null) || return 1
    _fw_parse_weather "$_fw_resp" && _fw_temp_source="forecast" || true
  fi
  [ -n "$_fw_t" ] || return 1
  printf '%s\n' "$_fw_t"
}

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
  curl_retry -fsS https://www.strava.com/oauth/token \
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

# ensure_session_cookie — prepare the Strava web session for the scrape data
# source. Strava uses OTP/magic-link login, so automated password login is not
# possible. Instead, the caller supplies the _strava4_session cookie value
# copied from their browser (DevTools → Application → Cookies → strava.com).
# This function writes that value to a curl cookie file and fetches the AJAX
# CSRF token from /dashboard. The CSRF token is cached for 25 days; the cookie
# file is rewritten every run from STRAVA_SESSION_COOKIE so a config update
# takes effect immediately.
# Requires: STRAVA_SESSION_COOKIE, STATE_DIR, TMP
ensure_session_cookie() {
  _sc_cookie_file="$STATE_DIR/strava_cookies.txt"
  _sc_csrf="$STATE_DIR/strava_csrf.txt"
  _sc_age="$STATE_DIR/strava_session_age.txt"

  # Always (re)write the cookie file — the value in config may have changed.
  printf '# Netscape HTTP Cookie File\n' > "$_sc_cookie_file"
  printf '.strava.com\tTRUE\t/\tTRUE\t0\t_strava4_session\t%s\n' \
    "$STRAVA_SESSION_COOKIE" >> "$_sc_cookie_file"
  chmod 600 "$_sc_cookie_file"

  # Reuse cached CSRF token if < 25 days old.
  if [ -f "$_sc_csrf" ] && [ -f "$_sc_age" ]; then
    _sc_ts="$(cat "$_sc_age" 2>/dev/null || echo 0)"
    case "$_sc_ts" in ''|*[!0-9]*) _sc_ts=0 ;; esac
    if [ "$(( $(date +%s) - _sc_ts ))" -lt 2160000 ]; then
      log "reusing cached Strava CSRF token"
      return 0
    fi
  fi

  log "fetching Strava CSRF token from dashboard..."
  curl_retry -fsS \
    -b "$_sc_cookie_file" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
    "https://www.strava.com/dashboard" \
    -o "$TMP/sc_dashboard.html" \
    || die "failed to fetch Strava dashboard — check network connectivity"

  _sc_csrf_val="$(awk -F'"' '/name="csrf-token"/{
    for(i=1;i<=NF;i++){if($i==" content=" || $i=="content="){print $(i+1);exit}}
  }' "$TMP/sc_dashboard.html")"
  [ -n "$_sc_csrf_val" ] \
    || die "could not extract csrf-token — STRAVA_SESSION_COOKIE has expired; copy a fresh _strava4_session value from browser DevTools (Application → Cookies → strava.com) into your config"

  printf '%s\n' "$_sc_csrf_val" > "$_sc_csrf"
  chmod 600 "$_sc_csrf"
  printf '%s\n' "$(date +%s)" > "$_sc_age"
  log "Strava session verified"
}

# check_session_cookie_status — non-fatal cookie probe used by the api+cookie
# dry-run mode. Sets _sc_check_valid=1 on success, 0 on failure. Returns 0/1.
# Re-uses the cached CSRF token when fresh (< 25 days); does a live dashboard
# fetch otherwise. On success the cookie/CSRF/age files are written identically
# to ensure_session_cookie so the two functions share state safely.
# Requires: STRAVA_SESSION_COOKIE, STATE_DIR, TMP
check_session_cookie_status() {
  _sc_check_valid=0
  _sc_cookie_file="$STATE_DIR/strava_cookies.txt"
  _sc_csrf="$STATE_DIR/strava_csrf.txt"
  _sc_age="$STATE_DIR/strava_session_age.txt"

  # Always (re)write the cookie file from the current config value.
  printf '# Netscape HTTP Cookie File\n' > "$_sc_cookie_file"
  printf '.strava.com\tTRUE\t/\tTRUE\t0\t_strava4_session\t%s\n' \
    "$STRAVA_SESSION_COOKIE" >> "$_sc_cookie_file"
  chmod 600 "$_sc_cookie_file"

  # Reuse cached CSRF token if < 25 days old.
  if [ -f "$_sc_csrf" ] && [ -f "$_sc_age" ]; then
    _sc_ts="$(cat "$_sc_age" 2>/dev/null || echo 0)"
    case "$_sc_ts" in ''|*[!0-9]*) _sc_ts=0 ;; esac
    if [ "$(( $(date +%s) - _sc_ts ))" -lt 2160000 ]; then
      log "cookie dry-run: CSRF cache fresh ($(( ( $(date +%s) - _sc_ts ) / 86400 ))d old) — session assumed valid"
      _sc_check_valid=1
      return 0
    fi
  fi

  log "cookie dry-run: verifying session cookie via Strava dashboard..."
  if ! curl_retry -fsS \
    -b "$_sc_cookie_file" \
    -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36" \
    "https://www.strava.com/dashboard" \
    -o "$TMP/sc_probe.html" 2>/dev/null; then
    log "cookie dry-run: network error — cannot reach Strava dashboard"
    return 1
  fi

  _sc_csrf_val="$(awk -F'"' '/name="csrf-token"/{
    for(i=1;i<=NF;i++){if($i==" content=" || $i=="content="){print $(i+1);exit}}
  }' "$TMP/sc_probe.html")"

  if [ -z "$_sc_csrf_val" ]; then
    log "cookie dry-run: STRAVA_SESSION_COOKIE has expired (no CSRF token found)"
    return 1
  fi

  printf '%s\n' "$_sc_csrf_val" > "$_sc_csrf"
  chmod 600 "$_sc_csrf"
  printf '%s\n' "$(date +%s)" > "$_sc_age"
  _sc_check_valid=1
  log "cookie dry-run: session cookie verified OK"
  return 0
}
