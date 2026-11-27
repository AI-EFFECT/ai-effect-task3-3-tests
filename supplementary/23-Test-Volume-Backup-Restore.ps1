<#
.SYNOPSIS
Backs up each node data volume, restores it into a new test-owned volume and compares file manifests (RES-05).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. For every existing named volume of the node's Compose
projects: record a SHA-256 manifest, archive it with tar, restore the archive into a new volume labelled
t33.restore=1, record the restored manifest and compare. The original volume is mounted read-only and never changed.

By default the node's containers are stopped during the backup so the copy is consistent, and restarted afterwards;
the downtime is recorded. Use -Live to back up without stopping (the manifest may then differ if data is written).

.NOTES
Archives are written under -BackupRoot (default: a 'backups' folder in the evidence folder) and can be large.
Restored volumes are removed afterwards unless -KeepRestored is given. Preserve the evidence folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Germany','Portugal','Netherlands')][string]$Node,
    [string]$BackupRoot,
    [switch]$Live,
    [switch]$KeepRestored
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label "23-volume-restore-$($Node.ToLower())" -Body {
    param($e)
    $n = Get-T33SupNode $s $Node
    $commit = Assert-T33SupCommit $n.SourceRoot $n.ExpectedCommit
    $helper = Ensure-T33HelperImage
    $backupDir = if ($BackupRoot) { Join-Path $BackupRoot ((Split-Path $e -Leaf)) } else { Join-Path $e 'backups' }
    New-Item -ItemType Directory -Force $backupDir | Out-Null

    $volumes = @(Get-T33NodeVolumes $n | Where-Object { (Invoke-T33Docker @('volume','inspect',$_) -AllowFailure).ExitCode -eq 0 })
    if ($volumes.Count -eq 0) { Stop-T33Blocked "no existing named volumes were found for $Node. Start the node and run its workflow first so the volumes hold data." }

    $downtime = $null
    if (-not $Live) {
        $stopAt = Get-Date
        foreach ($set in $n.ComposeSets) { Invoke-T33Docker (@('compose') + (Get-T33ComposeArgs $set) + @('stop')) | Out-Null }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($v in $volumes) {
            Write-Host "=== Volume $v"
            $before = Get-T33VolumeManifest $v
            Save-T33Text (Join-Path $e "manifest-before-$v.txt") $before
            $archive = "$v.tar.gz"
            $t0 = Get-Date
            Invoke-T33Docker @('run','--rm','-v',"${v}:/v:ro",'-v',"${backupDir}:/backup",$script:T33HelperImage,'tar','-C','/v','-czf',"/backup/$archive",'.') | Out-Null
            $backupSeconds = [math]::Round(((Get-Date) - $t0).TotalSeconds, 3)
            $restored = "t33r-$v"
            Invoke-T33Docker @('volume','rm',$restored) -AllowFailure | Out-Null
            Invoke-T33Docker @('volume','create','--label','t33.restore=1',$restored) | Out-Null
            $t1 = Get-Date
            Invoke-T33Docker @('run','--rm','-v',"${restored}:/v",'-v',"${backupDir}:/backup:ro",$script:T33HelperImage,'tar','-C','/v','-xzf',"/backup/$archive") | Out-Null
            $restoreSeconds = [math]::Round(((Get-Date) - $t1).TotalSeconds, 3)
            $after = Get-T33VolumeManifest $restored
            Save-T33Text (Join-Path $e "manifest-restored-$v.txt") $after
            $files = @($before -split "`n" | Where-Object { $_.Trim() }).Count
            $archiveBytes = (Get-Item (Join-Path $backupDir $archive)).Length
            $rows.Add([pscustomobject][ordered]@{
                Volume = $v; Files = $files; ArchiveBytes = $archiveBytes; BackupSeconds = $backupSeconds; RestoreSeconds = $restoreSeconds
                ManifestIdentical = ($before -eq $after)
            })
            Write-Host "files=$files identical=$($before -eq $after) backup=${backupSeconds}s restore=${restoreSeconds}s"
            if (-not $KeepRestored) { Invoke-T33Docker @('volume','rm',$restored) -AllowFailure | Out-Null }
        }
    }
    finally {
        if (-not $Live) {
            foreach ($set in $n.ComposeSets) { Invoke-T33Docker (@('compose') + (Get-T33ComposeArgs $set) + @('start')) -AllowFailure | Out-Null }
            $downtime = [math]::Round(((Get-Date) - $stopAt).TotalSeconds, 3)
        }
    }

    Save-T33Csv (Join-Path $e 'volume-restore.csv') $rows
    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{ node = $Node; source_commit = $commit; helper_image = $helper; live = [bool]$Live; node_downtime_seconds = $downtime; backup_dir = $backupDir; volumes = $rows })

    $different = @($rows | Where-Object { -not $_.ManifestIdentical } | ForEach-Object { $_.Volume })
    if ($different.Count -gt 0) {
        $why = if ($Live) { ' The backup was live, so rerun without -Live before treating this as a defect.' } else { '' }
        return (New-T33Verdict 'FAIL' "restored content differed for: $($different -join ', ').$why")
    }
    $mode = if ($Live) { 'live backup' } else { "consistent backup with $downtime s node downtime" }
    return (New-T33Verdict 'PASS' "$($rows.Count) volume(s) backed up and restored with identical file manifests ($mode).")
}
