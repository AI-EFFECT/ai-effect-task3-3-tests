<#
.SYNOPSIS
Parses the benchmark artifact and inventories its scenarios, episodes and populated KPI fields.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Assert-Baseline $settings
$artifact=Get-ChildItem $settings.EvidenceRoot -Recurse -Filter 'benchmark-artifact.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $artifact){throw 'No benchmark artifact found. Run 20-Test-Benchmark.ps1 first.'}
function Get-LeafValues { param($Value,[string]$Path)
    if($null -eq $Value){[pscustomobject]@{Path=$Path;Value=$null};return}
    if($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]){$index=0;foreach($item in $Value){Get-LeafValues $item "$Path[$index]";$index++};return}
    $props=@($Value.PSObject.Properties);if($props.Count -eq 0){[pscustomobject]@{Path=$Path;Value=$Value};return}
    foreach($property in $props){Get-LeafValues $property.Value "$Path.$($property.Name)"}
}
$evidence=New-EvidenceFolder $settings '21-benchmark-artifact';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $a=Get-Content $artifact.FullName -Raw|ConvertFrom-Json;Copy-Item $artifact.FullName (Join-Path $evidence 'input-artifact.json')
    # BenchmarkResult is grid2benchmark's result: scenarios[] (each with
    # episodes and kpis), a cross-scenario summary, and service metadata.
    foreach($field in 'scenarios','summary','metadata'){if($null -eq $a.PSObject.Properties[$field]){throw "Benchmark artifact has no '$field' field."}}
    $scenarios=@($a.scenarios);$leaves=@();$index=0
    foreach($scenario in $scenarios){$leaves+=@(Get-LeafValues $scenario.kpis "scenarios[$index].kpis");$index++}
    $leaves+=@(Get-LeafValues $a.summary 'summary')
    $populated=@($leaves|Where-Object {$null -ne $_.Value -and "$($_.Value)" -ne ''})
    $episodeCount=($scenarios|ForEach-Object { @($_.episodes).Count }|Measure-Object -Sum).Sum
    $warnings=@($a.metadata.warnings)
    [pscustomobject]@{SourceArtifact=$artifact.FullName;Algorithm=$a.metadata.algorithm;Grid2BenchmarkVersion=$a.metadata.grid2benchmark_version;Grid2OpVersion=$a.metadata.grid2op_version;ScenarioCount=$scenarios.Count;Environments=(@($scenarios|ForEach-Object { $_.environment })-join ', ');EpisodeCount=$episodeCount;PopulatedKpiLeaves=$populated.Count;Warnings=$warnings.Count}|Format-List
    Save-Json @{source_artifact=$artifact.FullName;sha256=(Get-FileHash $artifact.FullName -Algorithm SHA256).Hash;scenario_count=$scenarios.Count;episode_count=$episodeCount;populated_kpi_leaf_count=$populated.Count;warnings=$warnings;kpi_leaves=$leaves} (Join-Path $evidence 'summary.json')
    if($scenarios.Count -eq 0 -or $episodeCount -eq 0 -or $populated.Count -eq 0){Write-Host 'RESULT: FAIL — benchmark artifact has no scenarios, episodes or KPI values.'}else{Write-Host 'RESULT: PASS — benchmark artifact parsed and KPI inventory saved.'}
    foreach($warning in $warnings){Write-Host "NOTE: $warning"}
} finally {try{Stop-Transcript}catch{}}
