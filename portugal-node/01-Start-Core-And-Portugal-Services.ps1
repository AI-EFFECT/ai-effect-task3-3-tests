<#
.SYNOPSIS
Starts the orchestrator and integrated Portuguese services and waits for readiness.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Require-T33PortugalKeys;Assert-T33PortugalBaseline $s;$workspace=Assert-T33Workspace $s Integrated
$e=New-T33PortugalEvidence $s '01-start-integrated';Start-T33PortugalTranscript $e
try {
    Ensure-T33SharedNetwork
    $core=@(& docker compose -f $s.OrchestratorCompose up -d 2>&1);$core|ForEach-Object{Write-Host $_};if($LASTEXITCODE -ne 0){throw 'Core orchestrator start failed.'}
    $compose=Join-Path $workspace 'docker-compose.yml';$networkOverride=Get-T33SharedNetworkOverride $workspace
    $started=@(& docker compose -f $compose -f $networkOverride up -d --build 2>&1);$started|ForEach-Object{Write-Host $_};if($LASTEXITCODE -ne 0){throw 'Integrated Portugal service start failed. Preserve this transcript; do not change the source or workspace.'}
    Wait-T33Container (Get-T33OrchestratorContainer);foreach($container in @('tef-clickhouse','tef-data-provision','tef-knowledge-store','tef-synthetic-data')){Wait-T33Container $container}
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    Write-Host 'RESULT: PASS - core services and the integrated Portugal TEF pipeline are ready.'
} finally {Stop-T33PortugalTranscript}
