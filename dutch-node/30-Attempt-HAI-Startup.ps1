[CmdletBinding()]
param([switch]$BuildImages)
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Require-Keys $settings;Assert-Baseline $settings
$evidence=New-EvidenceFolder $settings '30-hai-startup';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $compose=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-hai-testing\docker-compose.yml';if(-not(Test-Path $compose)){throw "HAI Compose file missing: $compose"}
    $simulatorImage = if ([string]::IsNullOrWhiteSpace($env:HAI_SIMULATOR_IMAGE)) {'powergrid-simulator-app:latest'} else {$env:HAI_SIMULATOR_IMAGE}
    docker image inspect $simulatorImage *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Required local HAI simulator image is unavailable: $simulatorImage. Run .\29-Prepare-HAI-Simulator.ps1 first, then retry this script."
    }
    $env:NODE_PUBLIC_BASE_URL=$settings.NodePublicBaseUrl
    if($BuildImages){docker compose -f $compose up -d --build}else{docker compose -f $compose up -d}
    $exitCode=$LASTEXITCODE;docker compose -f $compose ps;docker compose -f $compose logs --no-color|Set-Content (Join-Path $evidence 'hai-compose.log')
    $port=Get-NetTCPConnection -State Listen -LocalPort 8443 -ErrorAction SilentlyContinue
    if($exitCode -ne 0){Write-Host 'RESULT: BLOCKED AS SUPPLIED — preserve the log; do not edit dependency locks.'}elseif($port){Write-Host 'RESULT: HAI reached a new runtime state; record a separate regression baseline.'}else{Write-Host 'RESULT: no listener on port 8443; inspect the saved log.'}
} finally {try{Stop-Transcript}catch{}}
