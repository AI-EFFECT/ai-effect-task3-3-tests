<#
.SYNOPSIS
Starts the common orchestrator and the exact supplied German services, recording dependency blockers.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()] param([switch]$Build)
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Require-Keys $s;Assert-Baseline $s;$e=New-EvidenceFolder $s '01-start-services';Start-EvidenceTranscript $e
try {
    $core=Join-Path $s.RepositoryRoot 'orchestrator\docker-compose.yml';if(-not(Test-Path $core)){throw "Core Compose file missing: $core"};if($Build){docker compose -f $core up -d --build}else{docker compose -f $core up -d};if($LASTEXITCODE){throw 'Core service start failed.'}
    $coreApi=@(docker ps --filter 'name=orchestrator-api' --format '{{.Names}}'|Where-Object{$_}|Select-Object -First 1);if(-not $coreApi){throw 'Orchestrator API container was not found after startup.'};Wait-Container $coreApi[0]
    $g=Get-GermanyCompose $s;if($Build){docker compose -f $g up -d --build}else{docker compose -f $g up -d};$exit=$LASTEXITCODE;docker compose -f $g ps|Set-Content (Join-Path $e 'germany-compose-ps.txt');docker compose -f $g config --images|Set-Content (Join-Path $e 'configured-compose-images.txt')
    if($exit){Write-Host 'RESULT: BLOCKED - the supplied Germany/VILLAS dependency could not be started. Preserve this transcript and configured image list; do not substitute an image for an official baseline result.';return}
    Write-Host 'RESULT: RECORDED - Germany services started. This release contains no VILLAS-dependent functional scripts.'
} finally {Stop-EvidenceTranscript}
