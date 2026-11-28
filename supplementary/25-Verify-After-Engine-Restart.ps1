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

    # Proof of restart: an engine restart stops every container, so none recorded as running may have run
    # continuously since before script 24. Docker prints nanoseconds; .NET parses at most seven digits.
    function ConvertTo-T33Utc([string]$Text) { [datetimeoffset]::Parse(($Text -replace '(\.\d{7})\d+', '$1'), [Globalization.CultureInfo]::InvariantCulture).UtcDateTime }
    $recordedAt = ConvertTo-T33Utc ([string]$state.recorded_at)
    $continuous = @(foreach ($c in $before) {
        $now = Invoke-T33Docker @('inspect',$c.Container,'--format','{{.State.Running}} {{.State.StartedAt}}') -AllowFailure
        if ($now.ExitCode -ne 0) { continue }
        $parts = $now.Output.Trim() -split ' ', 2
        if ($parts[0] -eq 'true' -and (ConvertTo-T33Utc $parts[1]) -lt $recordedAt) { $c.Container }
    })
    if ($continuous.Count -gt 0) {
        Stop-T33Blocked "the Docker engine was not restarted after script 24: $($continuous.Count) container(s) have run continuously since before $($state.recorded_at) (for example $($continuous[0])). Restart Docker Desktop (whale icon > Restart), confirm the containers restarted, then rerun this script; the state from script 24 is kept."
    }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($c in $before) {
        $remaining = [int][math]::Max(5, ($deadline - (Get-Date)).TotalSeconds)
        $after = if ($c.RestartPolicy -in @('','no')) { Get-T33ContainerState $c.Container } else { Wait-T33Container $c.Container $remaining }
        $results.Add([pscustomobject][ordered]@{ Scope = $c.Scope; Container = $c.Container; RestartPolicy = $c.RestartPolicy; StateBefore = $c.StateBefore; StateAfter = $after; Returned = ($after -in @('running','healthy')) })
    }
    Save-T33Csv (Join-Path $e 'containers-after.csv') $results

    # A volume written by a container that was running before the restart (a database, for example) changes on its
    # own, so byte identity is not expected; for those, record how many pre-restart files survived unchanged. Volumes
    # that no running container writes must be identical.
    $runningBefore = @($before | ForEach-Object Container)
    $volumeRows = New-Object System.Collections.Generic.List[object]
    foreach ($v in (Import-Csv (Join-Path $state.evidence 'volumes-before.csv'))) {
        $now = Get-T33VolumeManifest $v.Volume
        Save-T33Text (Join-Path $e "manifest-after-$($v.Volume).txt") $now
        $was = [IO.File]::ReadAllText($v.Manifest)
        $users = @((Invoke-T33Docker @('ps','-a','--filter',"volume=$($v.Volume)",'--format','{{.Names}}') -AllowFailure).Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $writers = @($users | Where-Object { $_ -in $runningBefore })
        $beforeLines = @($was -split "`n" | Where-Object { $_.Trim() }); $afterSet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($line in ($now -split "`n")) { if ($line.Trim()) { [void]$afterSet.Add($line) } }
        $kept = @($beforeLines | Where-Object { $afterSet.Contains($_) }).Count
        $volumeRows.Add([pscustomobject][ordered]@{
            Scope = $v.Scope; Volume = $v.Volume; Live = ($writers.Count -gt 0); Writers = ($writers -join ' ')
            Identical = ($now -eq $was); FilesBefore = $beforeLines.Count; FilesAfter = $afterSet.Count; BeforeFilesUnchanged = $kept
        })
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
    $changed = @($volumeRows | Where-Object { -not $_.Identical -and -not $_.Live })
    $emptied = @($volumeRows | Where-Object { $_.Live -and $_.FilesBefore -gt 0 -and $_.FilesAfter -eq 0 })
    foreach ($lv in @($volumeRows | Where-Object Live)) { Write-Host "Live volume $($lv.Volume) (written by $($lv.Writers)): $($lv.BeforeFilesUnchanged) of $($lv.FilesBefore) pre-restart files unchanged; $($lv.FilesAfter) files now." }
    $problems = New-Object System.Collections.Generic.List[string]
    if ($changed.Count -gt 0) { $problems.Add("content changed in volume(s) no running container writes: $(@($changed | ForEach-Object Volume) -join ', ')") }
    if ($emptied.Count -gt 0) { $problems.Add("live volume(s) emptied: $(@($emptied | ForEach-Object Volume) -join ', ')") }
    if ($earlierStatus -notin @('complete','completed','none recorded')) { $problems.Add("earlier workflow now $earlierStatus") }
    if ($newStatus -notin @('complete','completed')) { $problems.Add("new workflow $newStatus") }
    if ($missingWithPolicy.Count -gt 0) { $problems.Add("did not return despite a restart policy: $(@($missingWithPolicy | ForEach-Object Container) -join ', ')") }
    if ($problems.Count -gt 0) { return (New-T33Verdict 'DEFECT CONFIRMED' "recovery after the engine restart was incomplete: $($problems -join '; ').") }
    if ($missingNoPolicy.Count -gt 0) { return (New-T33Verdict 'FINDINGS RECORDED' "core and data recovered, but containers without a restart policy stayed down: $(@($missingNoPolicy | ForEach-Object Container) -join ', ').") }
    $liveCount = @($volumeRows | Where-Object Live).Count
    return (New-T33Verdict 'PASS' "all $($results.Count) containers returned, $($volumeRows.Count - $liveCount) idle volume manifest(s) unchanged and $liveCount live volume(s) recorded, the earlier workflow is retrievable and a new workflow completed.")
}
