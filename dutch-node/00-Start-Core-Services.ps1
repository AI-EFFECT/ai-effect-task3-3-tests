<#
.SYNOPSIS
Verifies the frozen Dutch baseline and starts the orchestrator, synthesizer and benchmark services.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param([switch]$BuildImages)
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings; Require-Keys $settings; Assert-Baseline $settings
$evidence=New-EvidenceFolder $settings '00-core-services'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
try {
    Push-Location $settings.RepositoryRoot
    try { Write-Host '=== Baseline ==='; git rev-parse HEAD; git submodule status --recursive } finally { Pop-Location }
    docker network inspect ai-effect-services *> $null
    if ($LASTEXITCODE -ne 0) { docker network create ai-effect-services | Out-Null }
    $env:NODE_PUBLIC_BASE_URL=$settings.NodePublicBaseUrl
    $orchestrator=Join-Path $settings.RepositoryRoot 'orchestrator\docker-compose.yml'
    $synthesizer=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-data-synthesizer\docker-compose.yml'
    $benchmark=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-benchmarking\docker-compose.yml'
    foreach($compose in @($orchestrator,$synthesizer,$benchmark)) { if(-not(Test-Path $compose)){throw "Compose file missing: $compose"} }
    if($BuildImages) { docker compose -f $orchestrator up -d --build; docker compose -f $synthesizer up -d --build; docker compose -f $benchmark up -d --build }
    else { docker compose -f $orchestrator up -d; docker compose -f $synthesizer up -d; docker compose -f $benchmark up -d }
    Wait-Container 'orchestrator-api'; Wait-Container 'synthetic-data'; Wait-Container 'benchmark-runner'
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    Write-Host 'RESULT: PASS — core services are ready.'
} finally { try { Stop-Transcript } catch {} }
