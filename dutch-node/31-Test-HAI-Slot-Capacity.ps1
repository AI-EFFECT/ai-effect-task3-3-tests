<#
.SYNOPSIS
Confirms the configured two-session HAI capacity and safe refusal of a third request.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '31-hai-slot-capacity'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force

$first = $null
$second = $null
try {
    $key = Get-HAIServiceKey
    Write-Host '=== HAI two-slot capacity test ==='
    Write-Host 'Two sessions use the default Dutch-node configuration. A third request must be refused.'

    $first = Start-HAITestSession -ServiceKey $key -Label 'capacity1' -TimeoutSeconds 120
    $second = Start-HAITestSession -ServiceKey $key -Label 'capacity2' -TimeoutSeconds 120
    $third = Start-HAITestSession -ServiceKey $key -Label 'capacity3' -TimeoutSeconds 120

    $first, $second, $third | ForEach-Object {
        [PSCustomObject]@{
            TaskId = $_.TaskId
            ServiceStatus = $_.Response.status
            HasInlineLinks = ($null -ne $_.Links)
            Error = $_.Response.error
        }
    } | Format-Table -AutoSize

    Save-Json $first.Response (Join-Path $evidence 'first-response.json')
    Save-Json $second.Response (Join-Path $evidence 'second-response.json')
    Save-Json $third.Response (Join-Path $evidence 'third-response.json')

    $firstOk = $first.Response.status -eq 'pending' -and $null -ne $first.Links
    $secondOk = $second.Response.status -eq 'pending' -and $null -ne $second.Links
    $thirdRefused = $third.Response.status -eq 'failed' -and $third.Response.error -match 'All 2 session slots are in use'

    [PSCustomObject]@{
        FirstSessionReady = $firstOk
        SecondSessionReady = $secondOk
        ThirdSessionSafelyRefused = $thirdRefused
    } | Format-List

    if (-not ($firstOk -and $secondOk -and $thirdRefused)) {
        throw 'Unexpected capacity-test result. Inspect the three saved response files.'
    }
    Write-Host 'RESULT: PASS - two sessions were admitted and the third was safely refused.'
}
finally {
    if ($first) { [void](Remove-HAITestSession -TaskId $first.TaskId -RemoveRecord) }
    if ($second) { [void](Remove-HAITestSession -TaskId $second.TaskId -RemoveRecord) }
    try { Stop-Transcript } catch {}
}
