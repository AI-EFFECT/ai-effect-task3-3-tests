<#
.SYNOPSIS
Saves the baselines, runtime inventory with image digests and an index of all supplementary evidence folders.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Run last. Nothing is changed.

.NOTES
Preserve the evidence folder. Archive the whole EvidenceRoot for the project record.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '99-closeout' -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    $baselines = [ordered]@{ platform = $commit }
    foreach ($name in $s.Nodes.Keys) {
        $n = Get-T33SupNode $s $name
        $actual = (& git -C $n.SourceRoot rev-parse HEAD 2>$null)
        $baselines[$name] = if ($actual) { $actual.Trim() } else { 'not available' }
    }
    $vendorMarker = Join-Path $s.VendorWorkspace '.t33-vendor-workspace.json'
    if (Test-Path $vendorMarker) { Copy-Item $vendorMarker (Join-Path $e 'vendor-workspace.json') }
    Save-T33Json (Join-Path $e 'baselines.json') $baselines
    Save-T33Text (Join-Path $e 'docker-version.txt') (Invoke-T33Docker @('version') -AllowFailure).Output
    Save-T33Text (Join-Path $e 'docker-ps.txt') (Invoke-T33Docker @('ps','-a','--format','table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}')).Output
    Save-T33Text (Join-Path $e 'docker-images.txt') (Invoke-T33Docker @('images','--digests','--format','table {{.Repository}}:{{.Tag}}\t{{.Digest}}\t{{.ID}}\t{{.Size}}')).Output

    $index = foreach ($folder in (Get-ChildItem $s.EvidenceRoot -Directory | Where-Object { $_.FullName -ne $e -and $_.Name -ne 'ux' } | Sort-Object Name)) {
        $run = Join-Path $folder.FullName 'run.txt'
        $result = if (Test-Path $run) { @(Select-String -LiteralPath $run -Pattern '^RESULT:' | Select-Object -Last 1 | ForEach-Object { $_.Line }) -join '' } else { '' }
        # A run later found invalid keeps its folder and RESULT line for the record but must not be read as a verdict.
        if (Test-Path (Join-Path $folder.FullName 'INVALID-RUN.txt')) { $result = "INVALID RUN (see INVALID-RUN.txt) - superseded: $result" }
        [pscustomobject]@{ EvidenceFolder = $folder.Name; Result = $result }
    }
    Save-T33Csv (Join-Path $e 'evidence-index.csv') $index
    foreach ($row in $index) { Write-Host "$($row.EvidenceFolder): $($row.Result)" }
    return (New-T33Verdict 'PASS' "close-out saved baselines, runtime inventory with digests and an index of $(@($index).Count) evidence folders.")
}
