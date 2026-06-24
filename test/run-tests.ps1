# run-tests.ps1 — build the test container, run it, execute functional tests,
# stop the container. Exits 0 on all pass, 1 on any failure.
#
# Run from anywhere (uses $PSScriptRoot):
#   powershell -ExecutionPolicy Bypass -File test\run-tests.ps1
#
# Requires: Podman (running machine), Node.js >= 18, Microsoft Edge.

$ErrorActionPreference = 'Stop'
$TestDir   = $PSScriptRoot                          # openwrt/test/
$ScriptDir = Split-Path -Parent $TestDir            # openwrt/  (Podman build context)
$Container = 'stravame-tests'
$Image     = 'stravame-test'
$ExitCode  = 0

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
    } catch { Write-Host "  [$i] not yet ready ..." }
}
if (-not $ready) {
    Write-Host "==> Container logs:"
    & podman logs $Container
    throw "httpd did not become ready in 20 s"
}
Write-Host "   httpd is ready."

# ---- 4. Set up a temp npm project with puppeteer-core ------------------------
$TmpDir = Join-Path $env:TEMP "strava-tests-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Force $TmpDir | Out-Null
Write-Host "==> Installing puppeteer-core into $TmpDir ..."
Push-Location $TmpDir
try {
    & npm init -y 2>&1 | Out-Null
    & npm install --save puppeteer-core 2>&1 | Where-Object { $_ -match 'added|warn|error' }
    if ($LASTEXITCODE -ne 0) { throw "npm install puppeteer-core failed" }
    Copy-Item (Join-Path $TestDir 'functional-tests.mjs') (Join-Path $TmpDir 'functional-tests.mjs')

    # ---- 5. Run tests ----------------------------------------------------------
    Write-Host "==> Running functional tests ..."
    & node functional-tests.mjs
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -ne 0) {
        Write-Host ""
        Write-Host "==> Container logs (on test failure):"
        & podman logs $Container
    }
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
if ($ExitCode -eq 0) {
    Write-Host "All functional tests passed."
} else {
    Write-Host "Functional tests FAILED (exit code $ExitCode)."
}
exit $ExitCode
