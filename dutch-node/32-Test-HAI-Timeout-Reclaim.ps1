<#
.SYNOPSIS
Checks whether expired HAI sessions automatically release their reserved slots.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param(
    [ValidateRange(15, 600)][int]$SessionTimeoutSeconds = 30,
    [ValidateRange(20, 900)][int]$WaitSeconds = 50
)

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '32-hai-timeout-reclaim'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force

$first = $null
$second = $null
try {
    $key = Get-HAIServiceKey
    Write-Host '=== HAI timeout and slot-reclaim test ==='
    Write-Host "Two sessions have a $SessionTimeoutSeconds-second budget. The script waits $WaitSeconds seconds before requesting a replacement."

    $first = Start-HAITestSession -ServiceKey $key -Label 'timeout1' -TimeoutSeconds $SessionTimeoutSeconds
    $second = Start-HAITestSession -ServiceKey $key -Label 'timeout2' -TimeoutSeconds $SessionTimeoutSeconds
    if ($first.Response.status -ne 'pending' -or $second.Response.status -ne 'pending') {
        throw 'The two initial sessions did not start. Inspect the saved responses; timeout behaviour was not tested.'
    }

    Start-Sleep -Seconds $WaitSeconds
    $firstStatus = Get-HAIStatus -ServiceKey $key -TaskId $first.TaskId
    $secondStatus = Get-HAIStatus -ServiceKey $key -TaskId $second.TaskId
    $replacement = Start-HAITestSession -ServiceKey $key -Label 'timeout-replacement' -TimeoutSeconds $SessionTimeoutSeconds

    Save-Json $firstStatus (Join-Path $evidence 'first-status-after-wait.json')
    Save-Json $secondStatus (Join-Path $evidence 'second-status-after-wait.json')
    Save-Json $replacement.Response (Join-Path $evidence 'replacement-response.json')

    [PSCustomObject]@{
        FirstStatusAfterBudget = $firstStatus.status
        SecondStatusAfterBudget = $secondStatus.status
        ReplacementStatus = $replacement.Response.status
        ReplacementError = $replacement.Response.error
    } | Format-List

    $defectConfirmed = (
        $firstStatus.status -eq 'running' -and
        $secondStatus.status -eq 'running' -and
        $replacement.Response.status -eq 'failed' -and
        $replacement.Response.error -match 'All 2 session slots are in use'
    )
    if ($defectConfirmed) {
        Write-Host 'RESULT: DEFECT CONFIRMED - timed-out sessions still occupy both slots; timeout reclaim is not active in this deployment.'
    }
    else {
        Write-Host 'RESULT: RECORDED - timeout behaviour differs from the recorded baseline. Inspect the saved responses before classifying it.'
    }
}
finally {
    if ($first) { [void](Remove-HAITestSession -TaskId $first.TaskId -RemoveRecord) }
    if ($second) { [void](Remove-HAITestSession -TaskId $second.TaskId -RemoveRecord) }
    try { Stop-Transcript } catch {}
}
