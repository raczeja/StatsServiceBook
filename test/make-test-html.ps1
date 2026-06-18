# Generates test.html (dashboard preview) from strava-my-html-dashboard.sh + activities.json.
# Run from anywhere. Open the resulting test/test.html directly in a browser.

$testDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$openwrtDir = Split-Path -Parent $testDir
$shFile     = Join-Path $openwrtDir "strava-my-html-dashboard.sh"
$jsonFile   = Join-Path $testDir    "activities.json"
$outFile    = Join-Path $testDir    "test.html"

if (-not (Test-Path $shFile))   { Write-Error "Not found: $shFile";   exit 1 }
if (-not (Test-Path $jsonFile)) { Write-Error "Not found: $jsonFile"; exit 1 }

# Extract the heredoc block between the <<'HTML' line and the closing HTML line.
$lines    = Get-Content $shFile -Encoding UTF8
$inBlock  = $false
$htmlLines = [System.Collections.Generic.List[string]]::new()

foreach ($line in $lines) {
    if (-not $inBlock) {
        if ($line -match "<<'HTML'") { $inBlock = $true }
        continue
    }
    if ($line -eq 'HTML') { break }
    $htmlLines.Add($line)
}

if ($htmlLines.Count -eq 0) {
    Write-Error "Could not find HTML heredoc in $shFile"
    exit 1
}

$html = $htmlLines -join "`n"

# Embed activities.json as an inline JS variable instead of a fetch() call.
$json = Get-Content $jsonFile -Raw -Encoding UTF8

$fetchBlock = @'
fetch("activities.json", { cache:"no-store" })
  .then(function(r){ if (!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
  .then(function(d){ DATA=d; init(); })
  .catch(function(err){
    metaEl.textContent = "Failed to load activities.json ("+err.message+
      "). Open this page via the router's web server, not from a file.";
  });
'@

$inlineBlock = "DATA = $json;`ninit();"

$html = $html.Replace($fetchBlock, $inlineBlock)

[System.IO.File]::WriteAllText($outFile, $html, [System.Text.Encoding]::UTF8)
Write-Host "Written: $outFile"
Write-Host "Open test/test.html in your browser to preview the dashboard."
