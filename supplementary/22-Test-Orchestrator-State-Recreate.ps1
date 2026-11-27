<#
.SYNOPSIS
Checks whether completed workflow records survive recreation of the orchestrator's Redis container (RES-04).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Completes a short vendor workflow, confirms it can be
read, recreates only the Redis service ('docker compose up -d --force-recreate --no-deps redis', as an upgrade or
host rebuild would), then reads the same workflow again and runs a new one.

The supplied orchestrator Compose file defines no volume for Redis, so loss of state is the expected risk.

.NOTES
Run 20-Prepare-Vendor-Pipeline.ps1 first. This deletes all orchestrator state held only in the Redis container.
Do not run while other workflows matter. Preserve the evidence folder.
#>
[CmdletBinding()]
param([ValidateRange(60, 1200)][int]$TimeoutSeconds = 300)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '22-redis-recreate' -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $export = Get-T33VendorExport $s
    $ref = ConvertTo-T33InlineReference @(@{ step = 1; value = 10 }, @{ step = 2; value = 12 })

    $first = Start-T33VendorWorkflow $s $export $ref 0 't33-res04-before'
    if (-not $first.WorkflowId) { return (New-T33Verdict 'FAIL' "submission returned HTTP $($first.StatusCode).") }
    $done = Wait-T33Workflow $s $first.WorkflowId $TimeoutSeconds
    if ($done.Status -notin @('complete','completed')) { Stop-T33Blocked "the workflow before the recreate ended as $($done.Status), so retention cannot be judged." }
    Save-T33Text (Join-Path $e 'before-workflow.json') $done.WorkflowText

    $model = Get-T33ComposeModel $s.OrchestratorCompose
    $redisDef = $model.services.redis
    $hasVolume = ($redisDef.PSObject.Properties.Name -contains 'volumes') -and (@($redisDef.volumes).Count -gt 0)
    $keysBefore = $null
    $redisName = @(Get-T33CoreContainers | Where-Object { $_ -match '^orchestrator-redis' }) | Select-Object -First 1
    if ($redisName) { $keysBefore = (Invoke-T33Docker @('exec',$redisName,'redis-cli','DBSIZE')).Output.Trim() }

    $at = Get-Date
    $recreate = Invoke-T33Docker @('compose','-f',$s.OrchestratorCompose,'up','-d','--force-recreate','--no-deps','redis') -AllowFailure
    Save-T33Text (Join-Path $e 'recreate.txt') $recreate.Output
    if ($recreate.ExitCode -ne 0) { return (New-T33Verdict 'FAIL' 'docker compose could not recreate the Redis service. See recreate.txt.') }
    $redisName = @(Get-T33CoreContainers | Where-Object { $_ -match '^orchestrator-redis' }) | Select-Object -First 1
    Wait-T33Container $redisName 120 | Out-Null
    $apiOk = Wait-T33HttpOk "$($s.OrchestratorUrl)/health" 120
    $keysAfter = (Invoke-T33Docker @('exec',$redisName,'redis-cli','DBSIZE')).Output.Trim()

    $again = Get-T33Workflow $s $first.WorkflowId
    Save-T33Text (Join-Path $e 'after-workflow.txt') "HTTP $($again.HttpStatus)`n$($again.WorkflowText)"

    $second = Start-T33VendorWorkflow $s $export $ref 0 't33-res04-after'
    $secondStatus = 'not submitted'
    if ($second.WorkflowId) { $secondStatus = (Wait-T33Workflow $s $second.WorkflowId $TimeoutSeconds).Status }

    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{
        platform_commit = $commit; redis_volume_defined = $hasVolume; redis_keys_before = $keysBefore; redis_keys_after = $keysAfter
        recreated_at = $at.ToString('o'); api_health_after = $apiOk
        earlier_workflow = $first.WorkflowId; earlier_workflow_after_recreate = $again.Status; new_workflow_status = $secondStatus
    })

    $retained = $again.Status -in @('complete','completed')
    $newOk = $secondStatus -in @('complete','completed')
    if (-not $retained) { return (New-T33Verdict 'DEFECT CONFIRMED' "the completed workflow was no longer retrievable after Redis was recreated (status $($again.Status); Redis keys $keysBefore before, $keysAfter after; Redis volume defined: $hasVolume). New workflow: $secondStatus.") }
    if (-not $newOk) { return (New-T33Verdict 'FINDINGS RECORDED' "workflow state was retained, but a new workflow ended as $secondStatus after the recreate.") }
    return (New-T33Verdict 'PASS' 'completed workflow state survived recreation of Redis and a new workflow completed.')
}
