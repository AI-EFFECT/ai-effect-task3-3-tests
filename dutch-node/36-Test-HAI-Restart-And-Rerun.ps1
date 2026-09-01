[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '36-hai-restart-rerun'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
$active = $null
$rerun = $null
try {
    $key = Get-HAIServiceKey
    Write-Host '=== Start one active session ==='
    $active = Start-HAITestSession -ServiceKey $key -Label 'restart' -TimeoutSeconds 300
    if ($active.Response.status -ne 'pending' -or $null -eq $active.Links) { throw 'The active restart-test session did not start.' }
    Write-Host '=== Restart only the HAI control service ==='
    docker restart hai-testing-service | Out-Null
    if (-not (Wait-HAIHealthy)) { throw 'hai-testing-service did not become healthy after restart.' }
    $status = Get-HAIStatus -ServiceKey $key -TaskId $active.TaskId
    $cookies = Join-Path $evidence 'signed-link-after-restart-cookies.txt'
    $linkCode = (& curl.exe -sS -L --max-time 30 -c $cookies -b $cookies -o (Join-Path $evidence 'signed-link-after-restart.html') -w '%{http_code}' $active.Links.gui_url).Trim()
    $slots = Get-HAISlots
    Save-Json $status (Join-Path $evidence 'original-status-after-restart.json')

    Write-Host '=== Controlled cleanup of the active restart test ==='
    [void](Remove-HAITestSession -TaskId $active.TaskId -RemoveRecord)
    Write-Host '=== Start one fresh rerun session ==='
    $rerun = Start-HAITestSession -ServiceKey $key -Label 'rerun' -TimeoutSeconds 120
    Save-Json $rerun.Response (Join-Path $evidence 'fresh-rerun-response.json')

    [PSCustomObject]@{
        HAIServiceHealthyAfterRestart = $true
        OriginalSessionStatusAfterRestart = $status.status
        OriginalSessionProgressAfterRestart = $status.progress
        OriginalSessionStillReserved = ($slots.Slot1 -eq $active.TaskId -or $slots.Slot2 -eq $active.TaskId)
        SignedGuiLinkAfterRestartHttpStatus = $linkCode
        FreshRerunSessionStarted = ($rerun.Response.status -eq 'pending' -and $null -ne $rerun.Links)
    } | Format-List
    if ($status.status -ne 'running' -or $linkCode -ne '200' -or $rerun.Response.status -ne 'pending') { throw 'Restart persistence or isolated rerun did not match the expected result.' }
    Write-Host 'RESULT: PASS - restart persistence and isolated rerun test completed.'
}
finally {
    if ($active) { [void](Remove-HAITestSession -TaskId $active.TaskId -RemoveRecord) }
    if ($rerun) { [void](Remove-HAITestSession -TaskId $rerun.TaskId -RemoveRecord) }
    try { Stop-Transcript } catch {}
}
