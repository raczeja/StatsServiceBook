# run-tests.ps1 — build the test container, run shell + Playwright tests, stop container.
# Exits 0 on all pass, 1 on any failure.
#
# Run from anywhere (uses $PSScriptRoot):
#   powershell -ExecutionPolicy Bypass -File test\run-tests.ps1
#
# Optional: pass a single spec file name to run just that suite:
#   powershell -ExecutionPolicy Bypass -File test\run-tests.ps1 heatmap.spec.mjs
#
# Requires: Podman (running machine), Node.js >= 18.

param(
    [string]$Spec = ""
)

$ErrorActionPreference = 'Stop'
$TestDir   = $PSScriptRoot
$ScriptDir = Split-Path -Parent $TestDir
$Container = 'stravame-tests'
$ExitCode  = 0
$HostPort  = if ($env:STRAVA_TEST_PORT) { [int]$env:STRAVA_TEST_PORT } else {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); ($listener.LocalEndpoint).Port } finally { $listener.Stop() }
}
$ContainerPort = 8080

# ---- 1. Build images --------------------------------------------------------
Write-Host "==> Building production image 'stravame-prod' ..."
& podman build -t stravame-prod $ScriptDir
if ($LASTEXITCODE -ne 0) { throw "podman build (production) failed" }

Write-Host "==> Building test image 'stravame-test' ..."
& podman build -f (Join-Path $TestDir 'Containerfile') --build-arg BASE=stravame-prod -t stravame-test $ScriptDir
if ($LASTEXITCODE -ne 0) { throw "podman build (test) failed" }

# ---- 2. Start container -----------------------------------------------------
Write-Host "==> Starting container on :$HostPort ..."
& podman rm -f $Container 2>$null
& podman run -d --name $Container -p "${HostPort}:$ContainerPort" stravame-test
if ($LASTEXITCODE -ne 0) { throw "podman run failed" }

# ---- 3. Resolve host IP (Podman runs inside a WSL VM on Windows) ------------
$TestHost = if ($env:TEST_HOST) { $env:TEST_HOST } else { "localhost" }
if (-not $env:TEST_HOST) {
    try {
        $job = Start-Job { & wsl -d podman-machine-default ip addr show eth0 2>$null }
        if (Wait-Job $job -Timeout 5) {
            $podmanIP = (Receive-Job $job | Select-String "inet " | Select-Object -First 1) `
                -replace '.*inet (\d+\.\d+\.\d+\.\d+).*','$1'
            if ("$podmanIP".Trim() -match '^\d+\.\d+\.\d+\.\d+$') { $TestHost = "$podmanIP".Trim() }
        } else { Stop-Job $job }
        Remove-Job $job -ErrorAction SilentlyContinue
    } catch {}
}
Write-Host "==> Using host '$TestHost' for HTTP checks ..."

# ---- 4. Wait for httpd ------------------------------------------------------
Write-Host "==> Waiting for httpd ..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep 1
    try {
        $null = Invoke-WebRequest -Uri "http://${TestHost}:$HostPort/strava/me/index.html" `
                                  -UseBasicParsing -TimeoutSec 2
        $ready = $true; break
    } catch { Write-Host "  [$i] not ready ..." }
}
if (-not $ready) {
    Write-Host "==> Container logs:"; & podman logs $Container
    throw "httpd did not become ready in 30 s"
}
Write-Host "   httpd ready."

# ---- 5. Set up Playwright ---------------------------------------------------
$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "strava-test-run"
New-Item -ItemType Directory -Force $TmpDir | Out-Null
Write-Host "==> Playwright dir: $TmpDir"
Push-Location $TmpDir
try {
    if (-not (Test-Path (Join-Path $TmpDir 'node_modules\.bin\playwright'))) {
        Write-Host "==> Installing @playwright/test ..."
        & npm init -y 2>&1 | Out-Null
        & npm install --save-dev @playwright/test 2>&1 | Where-Object { $_ -match 'added|warn|error' }
        if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
        Write-Host "==> Installing Chromium ..."
        & npx playwright install chromium 2>&1 | Select-Object -Last 5
    }

    Write-Host "==> Copying spec files ..."
    Copy-Item (Join-Path $TestDir '*.spec.mjs')          $TmpDir -Force
    Copy-Item (Join-Path $TestDir 'test-urls.mjs')       $TmpDir -Force
    Copy-Item (Join-Path $TestDir 'playwright.config.mjs') $TmpDir -Force

    # ---- 5a. Shell unit tests -----------------------------------------------
    Write-Host "==> Running shell unit tests ..."
    & podman exec $Container sh /opt/shell-tests.sh
    $ShellExit = $LASTEXITCODE

    # ---- 5b. Playwright functional tests ------------------------------------
    Write-Host "==> Running Playwright tests (host=$TestHost port=$HostPort) ..."
    $env:TEST_PORT = $HostPort
    $env:TEST_HOST = $TestHost
    if ($Spec) {
        & npx playwright test $Spec
    } else {
        & npx playwright test
    }
    $PlaywrightExit = $LASTEXITCODE
    Remove-Item Env:TEST_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:TEST_HOST -ErrorAction SilentlyContinue

    $ExitCode = if ($ShellExit -ne 0 -or $PlaywrightExit -ne 0) { 1 } else { 0 }
    if ($ExitCode -ne 0) {
        Write-Host ""; Write-Host "==> Container logs (on failure):"; & podman logs $Container
    }
} finally {
    Pop-Location
    Write-Host "==> Stopping container ..."
    & podman stop $Container 2>$null | Out-Null
    & podman rm   $Container 2>$null | Out-Null
}

Write-Host ""
if ($ExitCode -eq 0) { Write-Host "All tests passed." } else { Write-Host "Tests FAILED (exit $ExitCode)." }
exit $ExitCode
