<#
.SYNOPSIS
Restarts one orchestrator component while a vendor task is running and checks the workflow outcome (RES-01 to RES-03).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Submits a vendor workflow whose model step runs for
-DelaySeconds, waits until that step is running, restarts the chosen component (all workers, the API, or Redis with
'docker restart', never recreate), then follows the workflow to the end.

Verdicts: PASS when the workflow completes with its own valid output; FINDINGS RECORDED when it fails explicitly
(work lost but reported); DEFECT CONFIRMED when the workflow disappears or hangs past the timeout.

.NOTES
Run 20-Prepare-Vendor-Pipeline.ps1 first. This restarts shared orchestrator containers: do not run while other
workflows matter. Preserve the evidence folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Worker','Api','Redis')][string]$Component,
    [ValidateRange(20, 300)][int]$DelaySeconds = 60,
    [ValidateRange(120, 1800)][int]$TimeoutSeconds = 600
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label "21-restart-midrun-$($Component.ToLower())" -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $export = Get-T33VendorExport $s
    $pattern = switch ($Component) { 'Worker' { '^orchestrator-worker' } 'Api' { '^orchestrator-api' } 'Redis' { '^orchestrator-redis' } }
    $targets = @(Get-T33CoreContainers | Where-Object { $_ -match $pattern })
    if ($targets.Count -eq 0) { Stop-T33Blocked "no $Component container is running." }

    $marker = "t33-res-$($Component.ToLower())-$(Get-Date -Format 'HHmmss')"
    $ref = ConvertTo-T33InlineReference @(@{ step = 1; value = 1.5 }, @{ step = 2; value = 2.5 }, @{ step = 3; value = 3.5 })
    $submit = Start-T33VendorWorkflow $s $export $ref $DelaySeconds $marker
    Save-T33Text (Join-Path $e 'submit.json') $submit.Content
    if (-not $submit.WorkflowId) { return (New-T33Verdict 'FAIL' "submission returned HTTP $($submit.StatusCode) without a workflow_id.") }
    $id = $submit.WorkflowId

    # Wait until the model task is running, so the restart lands mid-task.
    $deadline = (Get-Date).AddSeconds(120); $running = $false
    do {
        Start-Sleep -Seconds 2
        $state = Get-T33Workflow $s $id
        $task = Get-T33TaskByContainer $state.Tasks 'vendor_model'
        if ($task -and [string]$task.status -eq 'running') { $running = $true }
    } while (-not $running -and (Get-Date) -lt $deadline)
    Save-T33Text (Join-Path $e 'tasks-before-restart.json') $state.TasksText
    if (-not $running) { Stop-T33Blocked 'the vendor model task never reached running within 120 s, so the restart could not be placed mid-task.' }

    $restartAt = Get-Date
    Write-Host "Restarting $($targets -join ', ') at $($restartAt.ToString('o'))"
    $restart = Invoke-T33Docker (@('restart') + $targets) -AllowFailure
    if ($restart.ExitCode -ne 0) { return (New-T33Verdict 'FAIL' "docker restart failed for $($targets -join ', ').") }
    foreach ($t in $targets) { Wait-T33Container $t 180 | Out-Null }
    $apiBack = Wait-T33HttpOk "$($s.OrchestratorUrl)/health" 180
    $readyAt = Get-Date

    $final = Wait-T33Workflow $s $id $TimeoutSeconds
    Save-T33Text (Join-Path $e 'workflow-after.json') $final.WorkflowText
    Save-T33Text (Join-Path $e 'tasks-after.json') $final.TasksText
    $modelTask = Get-T33TaskByContainer $final.Tasks 'vendor_model'
    $uri = if ($modelTask -and $modelTask.output_refs) { [string]@($modelTask.output_refs)[0].uri } else { '' }
    $doc = $null
    if ($uri) { $text = Read-T33VendorFile $uri; if ($text) { Save-T33Text (Join-Path $e 'model-output.json') $text; $doc = $text | ConvertFrom-Json } }
    $ownOutput = $doc -and ($doc.workflow_id -eq $id) -and ($doc.marker -eq $marker) -and $uri.StartsWith("/vendor-data/$id/")

    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{
        platform_commit = $commit; component = $Component; restarted = $targets; workflow_id = $id; delay_seconds = $DelaySeconds
        restart_started = $restartAt.ToString('o'); ready_after_seconds = [math]::Round(($readyAt - $restartAt).TotalSeconds, 3)
        api_health_after_restart = $apiBack; final_status = $final.Status; workflow_http_status = $final.HttpStatus; own_valid_output = [bool]$ownOutput
    })

    if ($final.Status -in @('complete','completed') -and $ownOutput) {
        return (New-T33Verdict 'PASS' "the workflow completed with its own valid output after the $Component restart (ready in $([math]::Round(($readyAt - $restartAt).TotalSeconds,1)) s).")
    }
    if ($final.Status -eq 'missing') { return (New-T33Verdict 'DEFECT CONFIRMED' "the workflow record was lost after the $Component restart (HTTP 404).") }
    if ($final.Status -like 'timeout*') { return (New-T33Verdict 'DEFECT CONFIRMED' "the workflow did not finish within $TimeoutSeconds s after the $Component restart; it remained $($final.Status).") }
    if ($final.Status -eq 'failed') { return (New-T33Verdict 'FINDINGS RECORDED' "the workflow failed explicitly after the $Component restart; the running work was lost but reported. See workflow-after.json.") }
    return (New-T33Verdict 'DEFECT CONFIRMED' "the workflow ended as $($final.Status) without its own valid output after the $Component restart.")
}
