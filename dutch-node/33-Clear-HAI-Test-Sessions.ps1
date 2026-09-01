[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [ValidatePattern('^task_t33_hai_')]
    [string[]]$TaskId
)

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '33-hai-test-cleanup'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
try {
    Write-Host '=== Scoped HAI test cleanup ==='
    Write-Host 'Only the supplied task IDs are considered. Unrelated sessions are not changed.'
    $before = Get-HAISlots
    $result = foreach ($id in $TaskId) {
        [PSCustomObject]@{ TaskId = $id; Removed = (Remove-HAITestSession -TaskId $id -RemoveRecord) }
    }
    $result | Format-Table -AutoSize
    $after = Get-HAISlots
    [PSCustomObject]@{ Slot1Before = $before.Slot1; Slot2Before = $before.Slot2; Slot1After = $after.Slot1; Slot2After = $after.Slot2 } | Format-List
    Save-Json $result (Join-Path $evidence 'cleanup-result.json')
    Write-Host 'RESULT: scoped cleanup completed. Review any Removed=False row before retrying a test.'
}
finally { try { Stop-Transcript } catch {} }
