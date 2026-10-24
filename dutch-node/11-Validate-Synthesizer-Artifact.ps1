<#
.SYNOPSIS
Checks that the synthesizer's pandapower network has a complete topology matching its synthesis metadata.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Assert-Baseline $settings
$artifact=Get-ChildItem $settings.EvidenceRoot -Recurse -Filter 'synth-artifact.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $artifact){throw 'No synthesizer artifact found. Run 10-Test-Synthesizer.ps1 first.'}
$evidence=New-EvidenceFolder $settings '11-synthesizer-artifact';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $a=Get-Content $artifact.FullName -Raw|ConvertFrom-Json;Copy-Item $artifact.FullName (Join-Path $evidence 'input-artifact.json')
    # GridData is one pp.to_json() network. Each element table is a DataFrame
    # whose `_object` is itself a JSON string in pandas split orientation.
    if($a.PSObject.Properties['_class'] -eq $null -or $a._class -ne 'pandapowerNet'){throw 'The artifact is not a serialized pandapowerNet.'}
    $network=$a._object
    function Get-SplitTable([string]$name) {
        $table=$network.PSObject.Properties[$name]
        if ($null -eq $table -or $null -eq $table.Value) { return $null }
        $inner=$table.Value._object;if($inner -is [string]){$inner=$inner|ConvertFrom-Json}
        return $inner
    }
    # Empty split tables may omit `index`; that is zero rows, not a script error.
    function Get-RowCount($table) { if($null -eq $table -or $null -eq $table.PSObject.Properties['index']){return 0};return @($table.index).Count }
    function Get-ColumnValues($table,[string]$column) {
        if($null -eq $table -or (Get-RowCount $table) -eq 0){return @()}
        $position=[array]::IndexOf(@($table.columns),$column);if($position -lt 0){throw "Table has no column $column."}
        return @($table.data|ForEach-Object { $_[$position] })
    }
    $busTable=Get-SplitTable 'bus';$lineTable=Get-SplitTable 'line';$trafoTable=Get-SplitTable 'trafo'
    $buses=Get-RowCount $busTable;$lines=Get-RowCount $lineTable;$transformers=Get-RowCount $trafoTable
    # Every branch must end on a bus that exists, otherwise topology was lost in export.
    $busIds=@{};if($buses -gt 0){foreach($id in @($busTable.index)){$busIds["$id"]=$true}}
    $endpoints=@((Get-ColumnValues $lineTable 'from_bus')+(Get-ColumnValues $lineTable 'to_bus')+(Get-ColumnValues $trafoTable 'hv_bus')+(Get-ColumnValues $trafoTable 'lv_bus'))
    $danglingEndpoints=@($endpoints|Where-Object { -not $busIds.ContainsKey("$_") }).Count
    $metadata=$network.PSObject.Properties['synthesis_metadata'];if($null -eq $metadata){throw 'The artifact carries no synthesis_metadata.'};$metadata=$metadata.Value
    $countsMatch=($metadata.buses -eq $buses -and $metadata.lines -eq $lines -and $metadata.transformers -eq $transformers)
    [pscustomobject]@{SourceArtifact=$artifact.FullName;GridName=$network.name;Buses=$buses;Lines=$lines;Transformers=$transformers;DanglingBranchEndpoints=$danglingEndpoints;MetadataCountsMatch=$countsMatch;PowerFlowConverged=$metadata.power_flow_converged;PandapowerVersion=$metadata.pandapower_version}|Format-List
    if($buses -eq 0 -or ($lines+$transformers) -eq 0 -or $danglingEndpoints -gt 0 -or -not $countsMatch){Write-Host 'RESULT: FAIL — grid topology is incomplete or inconsistent with its synthesis metadata.'}else{Write-Host 'RESULT: PASS — grid topology is present and consistent with its synthesis metadata.'}
    if(-not $metadata.power_flow_converged){Write-Host 'NOTE: the service reports that AC power flow did not converge on this grid.'}
} finally {try{Stop-Transcript}catch{}}
