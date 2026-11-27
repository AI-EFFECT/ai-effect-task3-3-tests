<#
.SYNOPSIS
Records restart policies and the pre-restart state of the core and nodes before a Docker engine restart (RES-06, RES-07 part 1).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Records every running core, vendor and node container
with its restart policy, the file manifest of every node volume, and one completed vendor workflow to look for after
the restart. Writes a pointer file that 25-Verify-After-Engine-Restart.ps1 reads.

After this script: restart Docker Desktop (whale icon > Restart), wait until it is running, then run script 25.
A Docker Desktop restart is the closest safe stand-in for a host reboot; it does not test hardware or OS failure.

.NOTES
Run 20-Prepare-Vendor-Pipeline.ps1 and start every node to be checked first. Preserve the evidence folder.
#>
[CmdletBinding()]
param([string[]]$Nodes = @('Germany','Portugal','Netherlands'))

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '24-before-engine-restart' -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $helper = Ensure-T33HelperImage
    $export = Get-T33VendorExport $s

    $containers = New-Object System.Collections.Generic.List[object]
    function Add-Containers([string]$Scope, [string[]]$Names) {
        foreach ($c in $Names) {
            $state = Get-T33ContainerState $c
            if ($state -notin @('running','healthy','unhealthy','starting')) { continue }
            $policy = (Invoke-T33Docker @('inspect',$c,'--format','{{.HostConfig.RestartPolicy.Name}}')).Output.Trim()
            $containers.Add([pscustomobject][ordered]@{ Scope = $Scope; Container = $c; StateBefore = $state; RestartPolicy = $policy })
        }
    }
    Add-Containers 'Core' (Get-T33CoreContainers)
    Add-Containers 'Vendor' @('t33-vendor-ingest','t33-vendor-model')
    $volumes = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Nodes) {
        $n = Get-T33SupNode $s $name
        Assert-T33SupCommit $n.SourceRoot $n.ExpectedCommit | Out-Null
        Add-Containers $name (Get-T33NodeContainers $n)
        foreach ($v in (Get-T33NodeVolumes $n)) {
            if ((Invoke-T33Docker @('volume','inspect',$v) -AllowFailure).ExitCode -ne 0) { continue }
            $file = Join-Path $e "manifest-before-$v.txt"
            Save-T33Text $file (Get-T33VolumeManifest $v)
            $volumes.Add([pscustomobject]@{ Scope = $name; Volume = $v; Manifest = $file })
        }
    }

    $ref = ConvertTo-T33InlineReference @(@{ step = 1; value = 4 }, @{ step = 2; value = 5 })
    $wf = Start-T33VendorWorkflow $s $export $ref 0 't33-res07-before'
    $status = if ($wf.WorkflowId) { (Wait-T33Workflow $s $wf.WorkflowId 300).Status } else { 'not submitted' }
    if ($status -notin @('complete','completed')) { Stop-T33Blocked "the reference workflow ended as $status; fix the core before the restart test." }

    Save-T33Csv (Join-Path $e 'containers-before.csv') $containers
    Save-T33Csv (Join-Path $e 'volumes-before.csv') $volumes
    $state = [ordered]@{ evidence = $e; recorded_at = (Get-Date).ToString('o'); platform_commit = $commit; helper_image = $helper; nodes = $Nodes; reference_workflow = $wf.WorkflowId }
    Save-T33Json (Join-Path $e 'state.json') $state
    Save-T33Json (Join-Path $s.EvidenceRoot '.t33-engine-restart-pending.json') $state

    $noPolicy = @($containers | Where-Object { $_.RestartPolicy -in @('','no') })
    Write-Host ''
    Write-Host 'NEXT: restart Docker Desktop now (whale icon > Restart), wait until it reports running, then run 25-Verify-After-Engine-Restart.ps1.'
    if ($noPolicy.Count -gt 0) {
        return (New-T33Verdict 'FINDINGS RECORDED' "RES-06: $($noPolicy.Count) running container(s) have no restart policy and will not return after a reboot: $(@($noPolicy | ForEach-Object { $_.Container }) -join ', '). State recorded for script 25.")
    }
    return (New-T33Verdict 'RECORDED' "RES-06: all $($containers.Count) running containers have a restart policy. State recorded for script 25.")
}
