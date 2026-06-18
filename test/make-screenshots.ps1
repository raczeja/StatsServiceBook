# make-screenshots.ps1 — build the test container, run it, take screenshots of
# the club dashboard and all My Activities pages, save to test/screenshots/, stop the container.
#
# Run from anywhere (uses $PSScriptRoot):
#   powershell -ExecutionPolicy Bypass -File openwrt/test/make-screenshots.ps1
#
# Requires: Podman (running machine), Node.js >= 18, Microsoft Edge.

$ErrorActionPreference = 'Stop'
$TestDir    = $PSScriptRoot                          # openwrt/test/
$ScriptDir  = Split-Path -Parent $TestDir            # openwrt/  (Podman build context)
$OutDir     = Join-Path $TestDir 'screenshots'
$Container  = 'stravame-screenshots'
$Image      = 'stravame-test'

# ---- 1. Build the Podman image -----------------------------------------------
Write-Host "==> Building image '$Image' (context: $ScriptDir) ..."
& podman build -f "$TestDir\Containerfile" -t $Image $ScriptDir
if ($LASTEXITCODE -ne 0) { throw "podman build failed" }

# ---- 2. Start the container --------------------------------------------------
Write-Host "==> Starting container '$Container' on :8080 ..."
& podman rm -f $Container 2>$null
& podman run -d --name $Container -p 8080:8080 $Image
if ($LASTEXITCODE -ne 0) { throw "podman run failed" }

# ---- 3. Wait for httpd to be ready ------------------------------------------
Write-Host "==> Waiting for httpd to become ready ..."
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    try {
        $null = Invoke-WebRequest -Uri 'http://localhost:8080/strava/me/index.html' `
                                  -UseBasicParsing -TimeoutSec 2
        $ready = $true; break
    } catch { Write-Host "  [$i] not yet ready ..."; }
}
if (-not $ready) {
    Write-Host "==> Container logs:"
    & podman logs $Container
    throw "httpd did not become ready in 20 s"
}
Write-Host "   httpd is ready."

# ---- 4. Set up a temp npm project with puppeteer-core ------------------------
# Copy screenshot.mjs into the temp dir so Node ESM resolves bare imports
# from co-located node_modules.
$TmpDir = Join-Path $env:TEMP "strava-screenshots-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Force $TmpDir | Out-Null
Write-Host "==> Installing puppeteer-core into $TmpDir ..."
Push-Location $TmpDir
try {
    & npm init -y 2>&1 | Out-Null
    & npm install --save puppeteer-core 2>&1 | Where-Object { $_ -match 'added|warn|error' }
    if ($LASTEXITCODE -ne 0) { throw "npm install puppeteer-core failed" }
    Copy-Item (Join-Path $TestDir 'screenshot.mjs') (Join-Path $TmpDir 'screenshot.mjs')

    # ---- 5. Take screenshots --------------------------------------------------
    Write-Host "==> Taking screenshots ..."
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    & node screenshot.mjs $OutDir
    if ($LASTEXITCODE -ne 0) { throw "screenshot.mjs failed - check Edge path and container logs" }
} finally {
    Pop-Location
    # ---- 6. Stop the container -----------------------------------------------
    Write-Host "==> Stopping container ..."
    & podman stop $Container 2>$null | Out-Null
    & podman rm   $Container 2>$null | Out-Null
    # ---- 7. Clean up temp dir ------------------------------------------------
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Screenshots saved to: $OutDir"
Get-ChildItem $OutDir -Filter '*.png' | Sort-Object Name | ForEach-Object {
    $kb = [math]::Round($_.Length / 1024); Write-Host "  $($_.Name)  ($kb KB)"
}
