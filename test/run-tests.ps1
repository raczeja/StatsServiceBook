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
$HostPort  = if ($env:STRAVA_TEST_PORT) { [int]$env:STRAVA_TEST_PORT } else {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); ($listener.LocalEndpoint).Port } finally { $listener.Stop() }
}
$ContainerPort = 8080

# ---- 1. Build the Podman image -----------------------------------------------
Write-Host "==> Building image '$Image' (context: $ScriptDir) ..."
& podman build -f "$(Join-Path $TestDir 'Containerfile')" -t $Image $ScriptDir
if ($LASTEXITCODE -ne 0) { throw "podman build failed" }

# ---- 2. Start the container --------------------------------------------------
Write-Host "==> Starting container '$Container' on :$HostPort ..."
& podman rm -f $Container 2>$null
& podman run -d --name $Container -p "${HostPort}:$ContainerPort" $Image
if ($LASTEXITCODE -ne 0) { throw "podman run failed" }

# ---- 3. Wait for httpd to become ready ------------------------------------------
Write-Host "==> Waiting for httpd to become ready ..."
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:$HostPort/strava/me/index.html" `
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

# ---- 4. Set up a temp npm project with puppeteer -----------------------------
$TmpRoot = [System.IO.Path]::GetTempPath()
$TmpDir  = Join-Path $TmpRoot "strava-tests-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Force $TmpDir | Out-Null
Write-Host "==> Installing puppeteer into $TmpDir ..."
Push-Location $TmpDir
try {
    & npm init -y 2>&1 | Out-Null
    & npm install --save puppeteer 2>&1 | Where-Object { $_ -match 'added|warn|error' }
    if ($LASTEXITCODE -ne 0) { throw "npm install puppeteer failed" }
    Copy-Item (Join-Path $TestDir 'functional-tests.mjs') (Join-Path $TmpDir 'functional-tests.mjs')

    # ---- 5. Run tests ----------------------------------------------------------
    Write-Host "==> Running functional tests ..."
    $env:TEST_PORT = $HostPort
    & node functional-tests.mjs
    $ExitCode = $LASTEXITCODE
    Remove-Item Env:TEST_PORT -ErrorAction SilentlyContinue

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
