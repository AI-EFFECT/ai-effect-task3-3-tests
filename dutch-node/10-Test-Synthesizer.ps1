[CmdletBinding()]
param([int]$TimeoutSeconds=1800)
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Require-Keys $settings;Assert-Baseline $settings;Wait-Container 'synthetic-data'
$evidence=New-EvidenceFolder $settings '10-synthesizer';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $blueprintPath=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-data-synthesizer\export\blueprint.json'
    $dockerInfoPath=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-data-synthesizer\export\dockerinfo.json'
    if(-not(Test-Path $blueprintPath)-or -not(Test-Path $dockerInfoPath)){throw 'Synthesizer blueprint or dockerinfo not found.'}
    $body=@{blueprint=(Get-Content $blueprintPath -Raw|ConvertFrom-Json);dockerinfo=(Get-Content $dockerInfoPath -Raw|ConvertFrom-Json);inputs=@();services_api_key=$settings.ServiceApiKey}|ConvertTo-Json -Depth 100
    $submission=Invoke-RestMethod -Uri "$($settings.OrchestratorUrl)/workflows" -Method Post -Headers (Get-OrchestratorHeaders $settings) -ContentType 'application/json' -Body $body
    $result=Wait-WorkflowComplete $settings $submission.workflow_id $TimeoutSeconds
    Save-Json $result.Workflow (Join-Path $evidence 'workflow.json');Save-Json $result.Tasks (Join-Path $evidence 'tasks.json')
    # The frozen baseline rejects the service's logical GridData format at the
    # shared orchestrator boundary.  It therefore publishes no output_refs even
    # though the Dutch service has completed and retained its own artifact.
    $task=$result.Tasks.tasks|Where-Object {$_.node_key -match 'ConfigureAndSynthesize'}|Select-Object -First 1
    if($null -eq $task){throw 'Synthesizer task was not found in workflow task inventory.'}
    if($task.output_refs){Save-Json $task.output_refs[0] (Join-Path $evidence 'output-reference.json')}
    docker cp "synthetic-data:/artifacts/$($task.task_id).payload" (Join-Path $evidence 'synth-artifact.json')
    if($LASTEXITCODE -ne 0){throw 'Synthesizer artifact was not found in the service container.'}
    docker cp "synthetic-data:/artifacts/$($task.task_id).meta.json" (Join-Path $evidence 'synth-artifact-metadata.json')
    Write-Host "workflow=$($result.Workflow.status); task=$($task.task_id)"
    Write-Host 'RESULT: service artifact retained. Workflow failure at the common DataReference boundary is recorded separately.'
} finally {try{Stop-Transcript}catch{}}
