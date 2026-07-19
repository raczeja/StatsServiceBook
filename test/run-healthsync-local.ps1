# run-healthsync-local.ps1
# -----------------------------------------------------------------------------
# Test healthsync-activities.sh (including dual-source detection) using local
# files instead of Google Drive. No Google credentials required.
#
# Place your exported activity files in a local folder:
#   - HealthSync CSV/TCX/GPX exports (HealthSync app format):
#       "YYYY.MM.DD HH.MM-TYPE.csv" / ".tcx" / ".gpx"
#       or the older format: "TYPE YYYY.MM.DD HH.MM.csv" etc.
#   - Magene FIT files:
#       "Magene_MODEL_YYYY-MM-DD_ID_*.fit"
#   - Pre-converted Magene GPX (skips GPS Visualizer, faster):
#       "magene_YYYY-MM-DD_ID.gpx"  (same date+ID as the FIT file)
#
# The script processes all files, detects dual-source rides (watch TCX + Magene
# FIT/GPX recorded at the same time), merges them into one record, and serves
# the result in a browser on http://localhost:PORT/strava/me/.
#
# Usage (first run):
#   powershell -ExecutionPolicy Bypass -File test\run-healthsync-local.ps1 `
#       -LocalFilesDir C:\path\to\exported\files
#
# Re-render only (reuse state from a previous -KeepOutput run):
#   powershell -ExecutionPolicy Bypass -File test\run-healthsync-local.ps1 `
#       -LocalFilesDir C:\path\to\exported\files `
#       -StateDir C:\Temp\healthsync-local-20260719120000\state `
#       -SkipImport
#
# Parameters:
#   -LocalFilesDir <path>  Folder with exported activity files (required)
#   -Port <int>            Host port (default: 8089)
#   -StateDir <path>       Reuse an existing state dir from a -KeepOutput run
#   -SkipImport            Skip file processing; only re-render HTML from store
#   -KeepOutput            Keep temp dirs when done (shows paths for reuse)
#   -NoBrowser             Do not open a browser window automatically
#
# Requirements:
#   - Podman (podman.exe on PATH)
#   - Internet access for Open-Meteo weather API (optional; gracefully skipped)
# -----------------------------------------------------------------------------

param(
    [Parameter(Mandatory=$true)]
    [string]$LocalFilesDir,

    [int]$Port = 8089,

    [string]$StateDir = '',

    [switch]$SkipImport,

    [switch]$KeepOutput,

    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot   # test/ -> repo root

# ---- Validate inputs ---------------------------------------------------------

if (-not (Test-Path $LocalFilesDir -PathType Container)) {
    Write-Error "LocalFilesDir not found or is not a directory: $LocalFilesDir"
    exit 1
}
$LocalFilesDirAbsolute = (Resolve-Path $LocalFilesDir).Path

if ($SkipImport -and -not $StateDir) {
    Write-Error "-SkipImport requires -StateDir pointing at a populated state directory."
    exit 1
}
if ($StateDir -and -not (Test-Path $StateDir)) {
    Write-Error "StateDir not found: $StateDir"
    exit 1
}

# ---- Show local files --------------------------------------------------------

$allFiles = Get-ChildItem -File $LocalFilesDirAbsolute
Write-Host ""
Write-Host "==> Local files directory: $LocalFilesDirAbsolute" -ForegroundColor Cyan
Write-Host "    $($allFiles.Count) file(s) found:"
$csvCount = ($allFiles | Where-Object { $_.Extension -eq '.csv' }).Count
$tcxCount = ($allFiles | Where-Object { $_.Extension -eq '.tcx' }).Count
$gpxCount = ($allFiles | Where-Object { $_.Extension -eq '.gpx' -and $_.Name -notmatch '^magene_' }).Count
$fitCount = ($allFiles | Where-Object { $_.Extension -eq '.fit' }).Count
$mgpxCount= ($allFiles | Where-Object { $_.Name -match '^magene_.*\.gpx$' }).Count
if ($csvCount)  { Write-Host "      CSV (summaries)    : $csvCount" }
if ($tcxCount)  { Write-Host "      TCX (HR/calories)  : $tcxCount" }
if ($gpxCount)  { Write-Host "      GPX (watch tracks) : $gpxCount" }
if ($fitCount)  { Write-Host "      Magene FIT files   : $fitCount" }
if ($mgpxCount) { Write-Host "      Magene GPX (local) : $mgpxCount  (GPS Visualizer skipped)" }
if ($fitCount -gt 0 -and $mgpxCount -lt $fitCount) {
    Write-Host ""
    Write-Host "    Note: $($fitCount - $mgpxCount) FIT file(s) have no pre-converted GPX." -ForegroundColor Yellow
    Write-Host "    GPS Visualizer (internet) will be used to convert them." -ForegroundColor Yellow
    Write-Host "    To skip, place 'magene_YYYY-MM-DD_ID.gpx' alongside each FIT file." -ForegroundColor Yellow
}
Write-Host ""

# ---- Prepare directories -----------------------------------------------------

$TempRoot = Join-Path $env:TEMP "healthsync-local-$(Get-Date -Format 'yyyyMMddHHmmss')"
$WebDir   = Join-Path $TempRoot 'web'

if ($StateDir) {
    $UseStateDir = (Resolve-Path $StateDir).Path
    Write-Host "==> Reusing state dir: $UseStateDir"
} else {
    $UseStateDir = Join-Path $TempRoot 'state'
    New-Item -ItemType Directory -Force $UseStateDir | Out-Null
}

New-Item -ItemType Directory -Force "$WebDir\strava\me\details" | Out-Null
New-Item -ItemType Directory -Force "$WebDir\strava\me\gpx"     | Out-Null
New-Item -ItemType Directory -Force "$WebDir\cgi-bin"           | Out-Null

# ---- Generate a minimal config (no real Google credentials needed) -----------
# LOCAL_DRIVE_DIR env var in the container replaces Drive OAuth + file listing.
# The config still needs the mandatory vars defined to pass the :? checks; they
# are never actually used when LOCAL_DRIVE_DIR is set.

$WrapperConfig = Join-Path $TempRoot 'container.conf'
[System.IO.File]::WriteAllText($WrapperConfig, @'
# Auto-generated by run-healthsync-local.ps1 - do not edit.
# Dummy Google credentials: real OAuth is bypassed by LOCAL_DRIVE_DIR.
GOOGLE_CLIENT_ID="local"
GOOGLE_CLIENT_SECRET="local"
GOOGLE_REFRESH_TOKEN="local"
DRIVE_FOLDER_ID="local"
# Container-local paths
HEALTHSYNC_STATE_DIR="/state"
HEALTHSYNC_WEB_DIR="/www/strava/me"
HEALTHSYNC_BIKE_DATA="/state/bike-service.json"
HEALTHSYNC_BIKE_ASSIGN="/state/bike-assignments.json"
HEALTHSYNC_CGI_DIR="/www/cgi-bin"
'@)

$RunName   = 'healthsync-local-run'
$ServeName = 'healthsync-local-serve'

function Stop-Containers {
    & podman rm -f $RunName   2>$null | Out-Null
    & podman rm -f $ServeName 2>$null | Out-Null
}

Stop-Containers

try {
    # ---- 1. Run healthsync-activities.sh -------------------------------------
    $importFlag = if ($SkipImport) { '0' } else { '1' }
    $modeLabel  = if ($SkipImport) { 're-render only (HEALTHSYNC_IMPORT_ENABLED=0)' } `
                                   else { "processing local files from $LocalFilesDirAbsolute" }

    Write-Host "==> Running healthsync-activities.sh ($modeLabel) ..."
    Write-Host "    State dir : $UseStateDir"
    Write-Host "    Web dir   : $WebDir"
    Write-Host ""

    $volArgs = @(
        '-v', "${RepoRoot}:/app:ro",
        '-v', "${WrapperConfig}:/etc/healthsync-activities.conf:ro",
        '-v', "${UseStateDir}:/state",
        '-v', "${WebDir}:/www",
        '-v', "${LocalFilesDirAbsolute}:/local-drive:ro"
    )

    & podman run --rm --name $RunName @volArgs `
        -e "HEALTHSYNC_IMPORT_ENABLED=$importFlag" `
        -e 'LOCAL_DRIVE_DIR=/local-drive' `
        alpine:3.20 `
        sh -c 'apk add --no-cache curl jq ca-certificates >/dev/null 2>&1 && sh /app/healthsync-activities.sh'

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "healthsync-activities.sh failed - check output above." -ForegroundColor Red
        exit 1
    }

    # ---- 2. Summarise results ------------------------------------------------
    $activitiesJson = Join-Path $WebDir 'strava\me\activities.json'
    if (Test-Path $activitiesJson) {
        try {
            $data  = Get-Content $activitiesJson -Raw | ConvertFrom-Json
            $count = $data.activities.Count
            $gen   = $data.generatedAt
            Write-Host ""
            Write-Host "==> activities.json: $count activities, generated $gen" -ForegroundColor Cyan
        } catch {}
    }

    $storeFile  = Join-Path $UseStateDir 'activities.ndjson'
    $storeLines = $null
    $dualLines  = $null
    $dualCount  = 0
    if (Test-Path $storeFile) {
        $storeLines = @(Get-Content $storeFile)
        $total      = $storeLines.Count
        $dualLines  = @($storeLines | Where-Object { $_ -match '"dual_source":true' })
        $dualCount  = $dualLines.Count
        Write-Host "==> Store: $total total records" -ForegroundColor Cyan
        if ($dualCount -gt 0) {
            Write-Host "==> Dual-source merged rides: $dualCount" -ForegroundColor Green
        } else {
            Write-Host "==> No dual-source merges found yet." -ForegroundColor Yellow
            Write-Host "    (Need matching watch TCX + Magene FIT/GPX with delta-start<600s, delta-end<300s)"
        }
    }

    # ---- 3. Serve with lighttpd (same image the functional tests use) -----------
    Write-Host ""
    Write-Host "==> Starting server on port $Port (lighttpd) ..."

    # Lighttpd config written line-by-line (avoids here-string CRLF/LF issues).
    $confFile = Join-Path $TempRoot 'lighttpd.conf'
    [System.IO.File]::WriteAllLines($confFile, [string[]]@(
        'server.port            = 8080',
        'server.document-root   = "/www"',
        'server.modules         = ("mod_dirlisting","mod_staticfile")',
        'dir-listing.activate   = "enable"',
        'index-file.names       = ("index.html")',
        'mimetype.assign        = (',
        '  ".html" => "text/html",',
        '  ".css"  => "text/css",',
        '  ".js"   => "application/javascript",',
        '  ".json" => "application/json",',
        '  ".gpx"  => "application/gpx+xml",',
        '  ".svg"  => "image/svg+xml",',
        '  ".png"  => "image/png",',
        '  ".jpg"  => "image/jpeg"',
        ')'
    ))

    & podman run -d --name $ServeName `
        -p "${Port}:8080" `
        -v "${WebDir}:/www:ro" `
        -v "${confFile}:/etc/lighttpd/lighttpd.conf:ro" `
        alpine:3.20 `
        sh -c 'apk add --no-cache lighttpd >/dev/null 2>&1 && lighttpd -D -f /etc/lighttpd/lighttpd.conf'

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to start serve container." -ForegroundColor Red
        exit 1
    }

    Write-Host "    Container started - waiting for lighttpd (up to 30 s) ..."
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try {
            $null = Invoke-WebRequest -Uri "http://localhost:$Port/strava/me/index.html" `
                                      -UseBasicParsing -TimeoutSec 2
            $ready = $true
            Write-Host "    Ready after $($i+1) s." -ForegroundColor Green
            break
        } catch {}
    }

    if (-not $ready) {
        Write-Host ""
        Write-Host "WARN: server did not respond in 30 s. Diagnostics:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  -- podman ps --"
        & podman ps -a --filter "name=$ServeName"
        Write-Host ""
        Write-Host "  -- container logs --"
        & podman logs $ServeName 2>&1
        Write-Host ""
        Write-Host "  -- Windows TCP listeners on port $Port --"
        $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        $hit = @($listeners | Where-Object { $_.Port -eq $Port })
        if ($hit.Count -gt 0) {
            Write-Host "    Port $Port IS listening on Windows (Podman port-forward OK)." -ForegroundColor Green
            Write-Host "    lighttpd or the page itself may have an error - check logs above."
        } else {
            Write-Host "    Port $Port is NOT listening on Windows." -ForegroundColor Red
            Write-Host "    Podman port-forward failed. Try a different port with -Port 8080."
        }
        Write-Host ""
    }

    # ---- 4. Print URLs -------------------------------------------------------
    $baseUrl = "http://localhost:$Port/strava/me"
    Write-Host ""
    Write-Host "==> Pages:" -ForegroundColor Green
    Write-Host "    Dashboard  : $baseUrl/"
    Write-Host "    Stats      : $baseUrl/stats.html"
    Write-Host "    Bike service: $baseUrl/bike.html"

    # Activity links - use store data already read in the Summarize section.
    # $storeLines/$dualLines/$dualCount are set only if the file existed then;
    # if not (e.g. Podman volume not visible from Windows side), we just skip.
    if ($null -ne $storeLines) {
        # Dual-source activity links
        if ($null -ne $dualLines -and $dualLines.Count -gt 0) {
            Write-Host ""
            Write-Host "    Dual-source merged rides:" -ForegroundColor Green
            @($dualLines) | Select-Object -First 5 | ForEach-Object {
                if ($_ -match '"id":"([^"]+)"') {
                    $id = $Matches[1]
                    $dt = if ($_ -match '"date":"([^"]+)"') { $Matches[1] } else { '' }
                    Write-Host "      $dt  $baseUrl/activity.html?id=$id"
                }
            }
        }

        # Last 5 imported activities
        Write-Host ""
        Write-Host "    Last 5 imported activities:"
        @($storeLines) | Select-Object -Last 5 | ForEach-Object {
            $id = if ($_ -match '"id":"([^"]+)"')    { $Matches[1] } else { '?' }
            $dt = if ($_ -match '"date":"([^"]+)"')  { $Matches[1] } else { '' }
            $nm = if ($_ -match '"name":"([^"]+)"')  { $Matches[1] } else { '' }
            $ds = if ($_ -match '"dual_source":true') { ' [MERGED]' } else { '' }
            Write-Host "      $dt  $nm$ds"
            Write-Host "        $baseUrl/activity.html?id=$id"
        }
    }

    Write-Host ""
    if ($KeepOutput) {
        Write-Host "    State dir (kept): $UseStateDir"
        Write-Host "    Web dir   (kept): $WebDir"
        Write-Host ""
        Write-Host "    Re-render next time with:"
        Write-Host "      -LocalFilesDir `"$LocalFilesDirAbsolute`" -StateDir `"$UseStateDir`" -SkipImport"
        Write-Host ""
    }

    if (-not $NoBrowser) {
        try { Start-Process "$baseUrl/" } catch {
            Write-Host "    (browser open failed: $($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
    Read-Host "Press Enter to stop"

} finally {
    Write-Host ""
    Write-Host "==> Stopping containers ..."
    Stop-Containers

    if ($KeepOutput) {
        Write-Host "Output kept:"
        Write-Host "  State : $UseStateDir"
        Write-Host "  Web   : $WebDir"
    } else {
        Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue
        Write-Host "Temp output removed."
    }
}
