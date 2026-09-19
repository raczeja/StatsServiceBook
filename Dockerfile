# StatsServiceBook — production image
# Runs all three data-source pipelines (Strava API, Strava scrape, HealthSync)
# under crond + lighttpd on Alpine Linux.
#
# Usage: see docker-compose.yml or https://github.com/raczeja/StatsServiceBook/wiki/Docker
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache \
    curl \
    jq \
    ca-certificates \
    lighttpd \
    msmtp \
    tzdata

# Shared library (sourced, not executed directly)
COPY strava-lib.sh               /usr/bin/strava-lib.sh

# Main executable scripts
COPY strava-leaderboard.sh       /usr/bin/strava-leaderboard
COPY strava-my-activities.sh     /usr/bin/strava-my-activities
COPY healthsync-activities.sh    /usr/bin/healthsync-activities
COPY strava-cron-guard.sh        /usr/bin/strava-cron-guard
COPY strava-email-monthly.sh     /usr/bin/strava-email-monthly
COPY strava-email-monthly.sh     /usr/bin/strava-email-weekly

# HTML helper scripts (sourced by main scripts, not run directly)
COPY strava-my-html-dashboard.sh /usr/bin/strava-my-html-dashboard.sh
COPY strava-my-html-detail.sh    /usr/bin/strava-my-html-detail.sh
COPY strava-my-html-bike.sh      /usr/bin/strava-my-html-bike.sh
COPY strava-my-html-stats.sh     /usr/bin/strava-my-html-stats.sh
COPY strava-my-html-heatmap.sh   /usr/bin/strava-my-html-heatmap.sh

RUN chmod 0755 \
    /usr/bin/strava-leaderboard \
    /usr/bin/strava-my-activities \
    /usr/bin/healthsync-activities \
    /usr/bin/strava-cron-guard \
    /usr/bin/strava-email-monthly \
    /usr/bin/strava-email-weekly \
 && chmod 0644 \
    /usr/bin/strava-lib.sh \
    /usr/bin/strava-my-html-dashboard.sh \
    /usr/bin/strava-my-html-detail.sh \
    /usr/bin/strava-my-html-bike.sh \
    /usr/bin/strava-my-html-stats.sh \
    /usr/bin/strava-my-html-heatmap.sh

COPY docker/lighttpd.conf /etc/lighttpd/lighttpd.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# /data holds all persistent state (token cache, activity store, bike-service data).
# Mount this as a named volume or host directory so data survives container restarts.
VOLUME ["/data"]

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
