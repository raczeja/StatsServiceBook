# run-scrape-test.ps1 - smoke-test strava-leaderboard.sh in STRAVA_SOURCE=scrape
# mode inside an Alpine container (matches the router's BusyBox environment).
#
# Set these env vars before running:
#   $env:STRAVA_SESSION_COOKIE = "sm7ds67uj..."          (_strava4_session from browser DevTools)
#   $env:STRAVA_CLUB_IDS       = "1280831,1280790"       (comma-separated numeric club IDs)
#
# How to get the session cookie:
#   1. Log in to strava.com in your browser
#   2. Open DevTools -> Application -> Cookies -> www.strava.com
#   3. Copy the Value of _strava4_session
#
# Example one-liner from the repo root:
#   $env:STRAVA_SESSION_COOKIE="sm7ds..."; $env:STRAVA_CLUB_IDS="1280831,1280790"
#   powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1
#   powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1 -Serve       # also open dashboard in browser
#   powershell -ExecutionPolicy Bypass -File test\run-scrape-test.ps1 -Serve -Port 8099
#
# Requires: Podman (running machine).

param([switch]$Serve, [int]$Port = 8088)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

# ---- 1. Validate required env vars ------------------------------------------
foreach ($v in @('STRAVA_SESSION_COOKIE', 'STRAVA_CLUB_IDS')) {
    if (-not [System.Environment]::GetEnvironmentVariable($v)) {
        Write-Error "Missing env var: $v - set it before running this script"
        exit 1
    }
}

# ---- 2. Build minimal Alpine image with curl + jq ---------------------------
$Image = 'strava-scrape-test'
$Containerfile = @'
FROM alpine:3.21
RUN apk add --no-cache curl jq ca-certificates python3
'@
$CfPath = Join-Path ([System.IO.Path]::GetTempPath()) 'Containerfile.scrape'
[System.IO.File]::WriteAllText($CfPath, $Containerfile.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)

Write-Host "==> Building image '$Image'..."
& podman build -f $CfPath -t $Image $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "podman build failed" }
Remove-Item $CfPath -ErrorAction SilentlyContinue

# ---- 3. Write the in-container test script to a temp file -------------------
$TestScript = @'
#!/bin/sh
set -eu
STATE=/tmp/strava-state
WEB=/tmp/strava-web
mkdir -p "$STATE" "$WEB"

# Empty config file — env vars supply all settings
touch /tmp/strava-leaderboard.conf

export STRAVA_LIBDIR=/opt/strava
export STRAVA_CONFIG=/tmp/strava-leaderboard.conf
export STRAVA_STATE_DIR="$STATE"
export STRAVA_WEB_DIR="$WEB"
export STRAVA_SOURCE=scrape
export STRAVA_KEEP_SNAPSHOTS=3

printf '==> club IDs: %s\n' "$STRAVA_CLUB_IDS"

sh /opt/strava/strava-leaderboard.sh

printf '\n--- per-club NDJSON stores ---\n'
for f in "$STATE"/activities_*.ndjson; do
  [ -f "$f" ] || continue
  printf '%s: %s entries\n' "$f" "$(wc -l < "$f")"
done

printf '\n--- activities.json summary ---\n'
jq '{clubs: (.clubs | length), per_club: [.clubs[] | {id: .clubId, name: (.club.name // "(no name)"), activities: (.activities | length)}]}' \
  "$WEB/activities.json" 2>/dev/null || printf '(not created)\n'
printf '\n'

if jq -e '.clubs | length > 0' "$WEB/activities.json" >/dev/null 2>&1; then
  printf '==> PASS: activities.json written with club data\n'
  exit 0
else
  printf '==> FAIL: activities.json missing or has no clubs\n'
  exit 1
fi
'@
$ScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) 'strava-scrape-test.sh'
# Write with Unix line endings (LF) so the shebang is readable inside the container.
[System.IO.File]::WriteAllText($ScriptPath, $TestScript.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)

# ---- 4. Prepare web output dir (persists after container exits) --------------
# Mounted as a volume so the generated HTML/JSON survives --rm cleanup.
$WebDir = Join-Path ([System.IO.Path]::GetTempPath()) 'strava-scrape-web'
New-Item -ItemType Directory -Force $WebDir | Out-Null

# ---- 5. Run the container ---------------------------------------------------
Write-Host "==> Running strava-leaderboard.sh (STRAVA_SOURCE=scrape) in Alpine..."
& podman run --rm `
    --volume "${RepoRoot}:/opt/strava:ro" `
    --volume "${ScriptPath}:/tmp/run.sh:ro" `
    --volume "${WebDir}:/tmp/strava-web" `
    --env "STRAVA_SESSION_COOKIE=$env:STRAVA_SESSION_COOKIE" `
    --env "STRAVA_CLUB_IDS=$env:STRAVA_CLUB_IDS" `
    $Image sh /tmp/run.sh

$ExitCode = $LASTEXITCODE
Remove-Item $ScriptPath -ErrorAction SilentlyContinue

Write-Host ""
if ($ExitCode -eq 0) {
    Write-Host "==> Scrape smoke test PASSED."
} else {
    Write-Host "==> Scrape smoke test FAILED (exit $ExitCode)."
    exit $ExitCode
}

# ---- 6. Optionally serve the generated dashboard ----------------------------
if ($Serve) {
    $ServeName = "strava-scrape-serve"
    & podman rm -f $ServeName 2>$null | Out-Null

    Write-Host "==> Starting dashboard on http://localhost:$Port/ ..."
    & podman run -d --name $ServeName `
        -p "${Port}:8080" `
        --volume "${WebDir}:/www:ro" `
        $Image `
        python3 -m http.server --directory /www 8080
    if ($LASTEXITCODE -ne 0) { throw "failed to start server container" }

    Start-Sleep -Seconds 2
    # Show logs if the container already exited (startup failure)
    $running = & podman inspect --format '{{.State.Running}}' $ServeName 2>$null
    if ($running -ne 'true') {
        Write-Host "==> Server container exited unexpectedly. Logs:"
        & podman logs $ServeName
        & podman rm -f $ServeName 2>$null | Out-Null
        exit 1
    }
    Start-Process "http://localhost:$Port/"
    Write-Host "==> Dashboard open in browser. Press Enter to stop the server."
    $null = Read-Host
    & podman rm -f $ServeName 2>$null | Out-Null
    Write-Host "==> Server stopped."
}

exit $ExitCode
