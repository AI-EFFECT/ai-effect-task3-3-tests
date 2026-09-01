. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Assert-Baseline $settings
$evidence=New-EvidenceFolder $settings '40-studio-manifest';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $blueprint=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-data-synthesizer\export\blueprint.json';if(-not(Test-Path $blueprint)){throw 'Synthesizer blueprint not found.'}
    $manifest=Get-Content $blueprint -Raw|ConvertFrom-Json;Save-Json $manifest (Join-Path $evidence 'supplied-blueprint.json')
    $isService=($manifest.PSObject.Properties.Name -contains 'service') -or ($manifest.PSObject.Properties.Name -contains 'service_name')
    [pscustomobject]@{Name=$manifest.name;PipelineId=$manifest.pipeline_id;HasServiceDeclarationShape=$isService}|Format-List
    if(-not $isService){Write-Host 'RESULT: FAIL AS SUPPLIED — exact blueprint is a pipeline topology, not a service declaration. Do not fabricate/import a replacement.'}else{Write-Host 'RESULT: service shape found; run owner-approved Studio onboarding as new evidence.'}
} finally {try{Stop-Transcript}catch{}}
