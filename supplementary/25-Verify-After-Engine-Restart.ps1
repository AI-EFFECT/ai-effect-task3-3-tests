<#
.SYNOPSIS
Verifies recovery after a Docker engine restart against the state recorded by script 24 (RES-07 part 2).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Waits for every container recorded as running to return,
compares node volume manifests, reads the reference workflow recorded before the restart and runs a new one.

Verdicts: PASS when everything returned, data is unchanged, the earlier workflow is retrievable and a new one
completes; DEFECT CONFIRMED when data changed, workflow state was lost or the core did not recover; FINDINGS RECORDED
when only containers without a restart policy stayed down (as predicted by RES-06).

.NOTES
Run only after 24-Record-Before-Engine-Restart.ps1 and a Docker Desktop restart. Preserve the evidence folder.
#>
[CmdletBinding()]
param([ValidateRange(60, 900)][int]$WaitSeconds = 300)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '25-after-engine-restart' -Body {
    param($e)
    $pointer = Join-Path $s.EvidenceRoot '.t33-engine-restart-pending.json'
    if (-not (Test-Path $pointer)) { Stop-T33Blocked 'no pending state from script 24 was found. Run 24-Record-Before-Engine-Restart.ps1 first.' }
    $state = Get-Content $pointer -Raw | ConvertFrom-Json
    Require-T33SupKeys
    $engine = Invoke-T33Docker @('version','--format','{{.Server.Version}}') -AllowFailure
    if ($engine.ExitCode -ne 0) { Stop-T33Blocked 'Docker Engine is not reachable yet. Wait for Docker Desktop, then rerun.' }
    $engineStarted = (Invoke-T33Docker @('info','--format','{{.SystemTime}}')).Output.Trim()

    $before = Import-Csv (Join-Path $state.evidence 'containers-before.csv')
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($c in $before) {
        $remaining = [int][math]::Max(5, ($deadline - (Get-Date)).TotalSeconds)
        $after = if ($c.RestartPolicy -in @('','no')) { Get-T33ContainerState $c.Container } else { Wait-T33Container $c.Container $remaining }
        $results.Add([pscustomobject][ordered]@{ Scope = $c.Scope; Container = $c.Container; RestartPolicy = $c.RestartPolicy; StateBefore = $c.StateBefore; StateAfter = $after; Returned = ($after -in @('running','healthy')) })
    }
    Save-T33Csv (Join-Path $e 'containers-after.csv') $results

    $volumeRows = New-Object System.Collections.Generic.List[object]
    foreach ($v in (Import-Csv (Join-Path $state.evidence 'volumes-before.csv'))) {
        $now = Get-T33VolumeManifest $v.Volume
        Save-T33Text (Join-Path $e "manifest-after-$($v.Volume).txt") $now
        $volumeRows.Add([pscustomobject]@{ Scope = $v.Scope; Volume = $v.Volume; Identical = ($now -eq [IO.File]::ReadAllText($v.Manifest)) })
    }
    Save-T33Csv (Join-Path $e 'volumes-after.csv') $volumeRows

    $apiOk = Wait-T33HttpOk "$($s.OrchestratorUrl)/health" 120
    $earlier = if ($state.reference_workflow) { Get-T33Workflow $s $state.reference_workflow } else { $null }
    $earlierStatus = if ($earlier) { $earlier.Status } else { 'none recorded' }
    $newStatus = 'not run'
    try {
        $export = Get-T33VendorExport $s
        $ref = ConvertTo-T33InlineReference @(@{ step = 1; value = 6 }, @{ step = 2; value = 7 })
        $wf = Start-T33VendorWorkflow $s $export $ref 0 't33-res07-after'
        $newStatus = if ($wf.WorkflowId) { (Wait-T33Workflow $s $wf.WorkflowId 300).Status } else { "submission HTTP $($wf.StatusCode)" }
    } catch { $newStatus = "error: $($_.Exception.Message)" }

    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{
        before_evidence = $state.evidence; engine_time_at_check = $engineStarted; api_health = $apiOk
        containers = $results.Count; returned = @($results | Where-Object Returned).Count
        reference_workflow = $state.reference_workflow; reference_workflow_after = $earlierStatus; new_workflow = $newStatus
        volumes_identical = @($volumeRows | Where-Object Identical).Count; volumes = $volumeRows.Count
    })
    Remove-Item -LiteralPath $pointer -Force

    $missingWithPolicy = @($results | Where-Object { -not $_.Returned -and $_.RestartPolicy -notin @('','no') })
    $missingNoPolicy = @($results | Where-Object { -not $_.Returned -and $_.RestartPolicy -in @('','no') })
    $changed = @($volumeRows | Where-Object { -not $_.Identical })
    $problems = New-Object System.Collections.Generic.List[string]
    if ($changed.Count -gt 0) { $problems.Add("volume content changed: $(@($changed | ForEach-Object Volume) -join ', ')") }
    if ($earlierStatus -notin @('complete','completed','none recorded')) { $problems.Add("earlier workflow now $earlierStatus") }
    if ($newStatus -notin @('complete','completed')) { $problems.Add("new workflow $newStatus") }
    if ($missingWithPolicy.Count -gt 0) { $problems.Add("did not return despite a restart policy: $(@($missingWithPolicy | ForEach-Object Container) -join ', ')") }
    if ($problems.Count -gt 0) { return (New-T33Verdict 'DEFECT CONFIRMED' "recovery after the engine restart was incomplete: $($problems -join '; ').") }
    if ($missingNoPolicy.Count -gt 0) { return (New-T33Verdict 'FINDINGS RECORDED' "core and data recovered, but containers without a restart policy stayed down: $(@($missingNoPolicy | ForEach-Object Container) -join ', ').") }
    return (New-T33Verdict 'PASS' "all $($results.Count) containers returned, $($volumeRows.Count) volume manifest(s) unchanged, the earlier workflow is retrievable and a new workflow completed.")
}
