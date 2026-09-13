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
$HostPort   = if ($env:STRAVA_TEST_PORT) { [int]$env:STRAVA_TEST_PORT } else {
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

# ---- 3. Resolve the host to use for HTTP access --------------------------------
# On Windows + WSL2-backed Podman, localhost port-forwarding can be blocked by
# the host firewall. Detect the Podman machine's WSL2 IP and use that instead.
$TestHost = "localhost"
try {
    # Use cmd /c to avoid a hang when PowerShell is run from a UNC path (\\wsl.localhost\...)
    $podmanIP = (& cmd /c "wsl -d podman-machine-default ip addr show eth0 2>nul" 2>$null |
        Select-String "inet " | Select-Object -First 1) -replace '.*inet (\d+\.\d+\.\d+\.\d+).*','$1'
    if ("$podmanIP".Trim() -match '^\d+\.\d+\.\d+\.\d+$') { $TestHost = "$podmanIP".Trim() }
} catch {}
Write-Host "==> Using host '$TestHost' for HTTP checks ..."

# ---- 4. Wait for httpd to become ready ------------------------------------------
Write-Host "==> Waiting for httpd to become ready ..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    try {
        $null = Invoke-WebRequest -Uri "http://${TestHost}:$HostPort/strava/me/index.html" `
                                  -UseBasicParsing -TimeoutSec 2
        $ready = $true; break
    } catch { Write-Host "  [$i] not yet ready ..."; }
}
if (-not $ready) {
    Write-Host "==> Container logs:"
    & podman logs $Container
    throw "httpd did not become ready in 30 s"
}
Write-Host "   httpd is ready."

# ---- 4. Set up a temp npm project with puppeteer -----------------------------
# Copy screenshot.mjs into the temp dir so Node ESM resolves bare imports
# from co-located node_modules.
$TmpRoot = [System.IO.Path]::GetTempPath()
$TmpDir  = Join-Path $TmpRoot "strava-screenshots-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Force $TmpDir | Out-Null
Write-Host "==> Installing puppeteer into $TmpDir ..."
Push-Location $TmpDir
try {
    & npm init -y 2>&1 | Out-Null
    & npm install --save puppeteer 2>&1 | Where-Object { $_ -match 'added|warn|error' }
    if ($LASTEXITCODE -ne 0) { throw "npm install puppeteer failed" }
    Copy-Item (Join-Path $TestDir 'screenshot.mjs') (Join-Path $TmpDir 'screenshot.mjs')

    # ---- 5. Take screenshots --------------------------------------------------
    Write-Host "==> Taking screenshots ..."
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $env:TEST_PORT = $HostPort
    $env:TEST_HOST = $TestHost
    & node screenshot.mjs $OutDir
    $LastExit = $LASTEXITCODE
    Remove-Item Env:TEST_PORT -ErrorAction SilentlyContinue
    if ($LastExit -ne 0) { throw "screenshot.mjs failed - check Edge path and container logs" }
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
