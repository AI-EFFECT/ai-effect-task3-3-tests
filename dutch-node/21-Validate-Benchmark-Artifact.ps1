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
    $leaves=@(Get-LeafValues $a.kpis 'kpis');$populated=@($leaves|Where-Object {$null -ne $_.Value -and "$($_.Value)" -ne ''})
    [pscustomobject]@{SourceArtifact=$artifact.FullName;EpisodeCount=@($a.episodes).Count;EvaluationBackend=$a.kpis.evaluation_backend;PopulatedKpiLeaves=$populated.Count}|Format-List
    Save-Json @{source_artifact=$artifact.FullName;sha256=(Get-FileHash $artifact.FullName -Algorithm SHA256).Hash;populated_kpi_leaf_count=$populated.Count;kpi_leaves=$leaves} (Join-Path $evidence 'summary.json')
    Write-Host 'RESULT: PASS — benchmark artifact parsed and KPI inventory saved.'
} finally {try{Stop-Transcript}catch{}}
