<#
.SYNOPSIS
Runs overlapping vendor workflows to check whether the platform's concurrent template keeps outputs apart (EXT-03).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. The vendor model service uses the platform's concurrent
template unchanged, so this is a template-level regression test for the Danish finding DK-REL-02 (task IDs derived
from the node key only, and task state keyed by task ID alone).

Each round submits -Parallel workflows at once, each with its own marker and its own input values. Every workflow
is classified:
  ok        - completed, and its model output is in its own folder and carries its own marker and workflow ID;
  exchanged - completed, but its output reference or content belongs to another workflow;
  failed    - did not complete (including 'Task not complete' errors), or produced no output.
A missing output is never counted as an exchange.

.NOTES
Run 20-Prepare-Vendor-Pipeline.ps1 first. This is a bounded concurrency check, not a capacity limit.
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 5)][int]$Parallel = 2,
    [ValidateRange(1, 10)][int]$Rounds = 3,
    [ValidateRange(0, 60)][int]$DelaySeconds = 5,
    [ValidateRange(60, 1800)][int]$TimeoutSeconds = 600
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '31-template-concurrency' -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $export = Get-T33VendorExport $s
    $rows = New-Object System.Collections.Generic.List[object]

    for ($round = 1; $round -le $Rounds; $round++) {
        Write-Host "=== Round $round of ${Rounds}: $Parallel overlapping workflows"
        $items = @()
        for ($k = 1; $k -le $Parallel; $k++) {
            $marker = "t33-conc-r$round-w$k"
            $ref = ConvertTo-T33InlineReference @(@{ step = 1; value = (100 * $k) }, @{ step = 2; value = (100 * $k + 1) }, @{ step = 3; value = (100 * $k + 2) })
            $submit = Start-T33VendorWorkflow $s $export $ref $DelaySeconds $marker
            $items += [pscustomobject]@{ Index = $k; Marker = $marker; WorkflowId = $submit.WorkflowId; Submit = $submit.StatusCode }
        }
        foreach ($it in $items) {
            if (-not $it.WorkflowId) {
                $rows.Add([pscustomobject][ordered]@{ Round = $round; Index = $it.Index; WorkflowId = ''; Status = "submission HTTP $($it.Submit)"; Class = 'failed'; Detail = 'not submitted'; TaskIds = '' })
                continue
            }
            $wf = Wait-T33Workflow $s $it.WorkflowId $TimeoutSeconds
            Save-T33Text (Join-Path $e "round-$round-workflow-$($it.Index)-tasks.json") $wf.TasksText
            $taskIds = if ($wf.Tasks) { (@($wf.Tasks.tasks | ForEach-Object { [string]$_.task_id }) | Sort-Object) -join ' ' } else { '' }
            $modelTask = Get-T33TaskByContainer $wf.Tasks 'vendor_model'
            $uri = if ($modelTask -and $modelTask.output_refs) { [string]@($modelTask.output_refs)[0].uri } else { '' }
            $doc = $null
            if ($uri) { $text = Read-T33VendorFile $uri; if ($text) { $doc = $text | ConvertFrom-Json } }
            $class = 'failed'; $detail = "status $($wf.Status)"
            if ($wf.Status -in @('complete','completed') -and $uri -and $doc) {
                $ownPath = $uri.StartsWith("/vendor-data/$($it.WorkflowId)/")
                $ownContent = ($doc.workflow_id -eq $it.WorkflowId) -and ($doc.marker -eq $it.Marker)
                if ($ownPath -and $ownContent) { $class = 'ok'; $detail = 'own output' }
                else { $class = 'exchanged'; $detail = "output $uri carries marker '$($doc.marker)' from workflow $($doc.workflow_id)" }
            } elseif ($wf.Status -in @('complete','completed')) { $detail = 'completed but no readable model output' }
            else {
                $err = ''
                try { $err = [string]($wf.WorkflowText | ConvertFrom-Json).error } catch { }
                if ($err) { $detail = "failed: $err" }
            }
            $rows.Add([pscustomobject][ordered]@{ Round = $round; Index = $it.Index; WorkflowId = $it.WorkflowId; Status = $wf.Status; Class = $class; Detail = $detail; TaskIds = $taskIds })
            Write-Host "round $round workflow $($it.Index): $class ($detail)"
        }
    }

    Save-T33Csv (Join-Path $e 'concurrency-results.csv') $rows
    $completedIds = @($rows | Where-Object { $_.TaskIds } | ForEach-Object TaskIds | Sort-Object -Unique)
    $sharedIds = ($completedIds.Count -eq 1) -and ($rows.Count -gt 1)
    $counts = [ordered]@{ ok = @($rows | Where-Object Class -eq 'ok').Count; exchanged = @($rows | Where-Object Class -eq 'exchanged').Count; failed = @($rows | Where-Object Class -eq 'failed').Count }
    $roundsExchanged = @($rows | Where-Object Class -eq 'exchanged' | ForEach-Object Round | Sort-Object -Unique)
    $roundsFailed = @($rows | Where-Object Class -eq 'failed' | ForEach-Object Round | Sort-Object -Unique)
    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{
        platform_commit = $commit; parallel = $Parallel; rounds = $Rounds; delay_seconds = $DelaySeconds
        same_task_ids_across_workflows = $sharedIds; counts = $counts; rounds_with_exchange = $roundsExchanged; rounds_with_failure = $roundsFailed
    })

    $note = if ($sharedIds) { ' All workflows used the same task IDs.' } else { '' }
    if ($counts.exchanged -gt 0 -or $counts.failed -gt 0) {
        return (New-T33Verdict 'DEFECT CONFIRMED' "$($counts.exchanged) workflow(s) received another workflow's output (rounds $($roundsExchanged -join ',')) and $($counts.failed) failed (rounds $($roundsFailed -join ',')) out of $($rows.Count).$note")
    }
    return (New-T33Verdict 'PASS' "all $($rows.Count) overlapping workflows over $Rounds round(s) produced their own outputs.$note")
}
