. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Assert-Baseline $settings
$artifact=Get-ChildItem $settings.EvidenceRoot -Recurse -Filter 'synth-artifact.json'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null -eq $artifact){throw 'No synthesizer artifact found. Run 10-Test-Synthesizer.ps1 first.'}
$evidence=New-EvidenceFolder $settings '11-synthesizer-artifact';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $a=Get-Content $artifact.FullName -Raw|ConvertFrom-Json;Copy-Item $artifact.FullName (Join-Path $evidence 'input-artifact.json')
    # Actual GridData schema: graph_data + serialized pandapower split tables.
    # Empty split tables may omit `index`; that is zero rows, not a script error.
    function Get-SplitTableCount($table) {
        if ($null -eq $table) { return 0 }
        $inner = $table.PSObject.Properties['__object']
        if ($null -eq $inner) { $inner = $table.PSObject.Properties['_object'] }
        if ($null -eq $inner -or $null -eq $inner.Value) { return 0 }
        $index = $inner.Value.PSObject.Properties['index']
        if ($null -eq $index -or $null -eq $index.Value) { return 0 }
        return @($index.Value).Count
    }
    $edges=@($a.graph_data.edges).Count
    $networkProperty = $a.pandapower.PSObject.Properties['_object']
    if ($null -eq $networkProperty -or $null -eq $networkProperty.Value) { throw 'The artifact has no serialized pandapower network.' }
    $network = $networkProperty.Value
    $lineProperty = $network.PSObject.Properties['line']
    $trafoProperty = $network.PSObject.Properties['trafo']
    $lines=Get-SplitTableCount $(if ($lineProperty) { $lineProperty.Value } else { $null })
    $transformers=Get-SplitTableCount $(if ($trafoProperty) { $trafoProperty.Value } else { $null })
    [pscustomobject]@{SourceArtifact=$artifact.FullName;GraphEdges=$edges;PandapowerLines=$lines;PandapowerTransformers=$transformers}|Format-List
    if($edges -gt 0 -and ($lines+$transformers)-eq 0){Write-Host 'RESULT: FAIL — graph topology is not preserved in pandapower.'}else{Write-Host 'RESULT: topology check did not reproduce the frozen-baseline defect.'}
} finally {try{Stop-Transcript}catch{}}
