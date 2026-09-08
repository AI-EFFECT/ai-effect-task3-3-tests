[CmdletBinding()]
param([ValidateRange(60, 600)][int]$ReadyTimeoutSeconds = 300)

. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Require-T33PortugalKeys
Assert-T33PortugalBaseline $s
Assert-T33Workspace $s Integrated | Out-Null
$e = New-T33PortugalEvidence $s '24-restart-rerun'
Start-T33PortugalTranscript $e

try {
    $containers = @('tef-clickhouse','tef-data-provision','tef-knowledge-store','tef-synthetic-data')
    foreach ($container in $containers) { Wait-T33Container $container }
    docker inspect $containers | Set-Content -Path (Join-Path $e 'containers-before.json') -Encoding utf8
    foreach ($volume in (Get-T33TestVolumeNames Integrated)) {
        & docker volume inspect $volume 2>&1 | Set-Content -Path (Join-Path $e ("volume-before-$volume.json")) -Encoding utf8
    }

    $restartStarted = Get-Date
    & docker restart $containers | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'One or more Portugal containers could not be restarted.' }
    foreach ($container in $containers) { Wait-T33Container $container $ReadyTimeoutSeconds }
    $readyAt = Get-Date
    docker inspect $containers | Set-Content -Path (Join-Path $e 'containers-after.json') -Encoding utf8
    foreach ($volume in (Get-T33TestVolumeNames Integrated)) {
        & docker volume inspect $volume 2>&1 | Set-Content -Path (Join-Path $e ("volume-after-$volume.json")) -Encoding utf8
    }

    $childStarted = Get-Date
    $workflowScript = Join-Path $PSScriptRoot '20-Test-Portugal-Workflow.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workflowScript
    $childExit = $LASTEXITCODE
    $candidate = Get-ChildItem -Path $s.EvidenceRoot -Directory |
        Where-Object { $_.Name -like '*-20-integrated-workflow' -and $_.LastWriteTime -ge $childStarted.AddSeconds(-2) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $candidate) { throw 'The post-restart workflow evidence folder could not be identified.' }
    Copy-Item -LiteralPath (Join-Path $candidate.FullName 'workflow.json') -Destination (Join-Path $e 'post-restart-workflow.json') -Force
    Copy-Item -LiteralPath (Join-Path $candidate.FullName 'tasks.json') -Destination (Join-Path $e 'post-restart-tasks.json') -Force
    $status = (Get-Content (Join-Path $e 'post-restart-workflow.json') -Raw | ConvertFrom-Json).status
    [pscustomobject][ordered]@{
        RestartStartedAt=$restartStarted.ToString('o')
        AllContainersReadyAt=$readyAt.ToString('o')
        RecoverySeconds=[math]::Round(($readyAt-$restartStarted).TotalSeconds,3)
        PostRestartWorkflowStatus=$status
        ChildExitCode=$childExit
        ChildEvidenceFolder=$candidate.FullName
    } | ConvertTo-Json | Set-Content -Path (Join-Path $e 'restart-summary.json') -Encoding utf8

    if ($childExit -eq 0 -and $status -in @('complete','completed')) {
        Write-Host 'RESULT: PASS - the isolated Portugal service stack restarted and a new integrated workflow completed. Named volumes were retained.'
    }
    else {
        Write-Host 'RESULT: FINDING RECORDED - services restarted, but the post-restart workflow did not complete normally. Preserve all evidence.'
    }
}
finally { Stop-T33PortugalTranscript }

