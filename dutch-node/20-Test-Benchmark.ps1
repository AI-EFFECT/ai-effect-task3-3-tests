<#
.SYNOPSIS
Runs the Dutch benchmarking workflow and preserves the benchmark artifact and handoff evidence.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param([int]$TimeoutSeconds=1800)
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Require-Keys $settings;Assert-Baseline $settings;Wait-Container 'benchmark-runner'
$evidence=New-EvidenceFolder $settings '20-benchmark';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $blueprintPath=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-benchmarking\export\blueprint.json';$dockerInfoPath=Join-Path $settings.RepositoryRoot 'use-cases\dutch-node-benchmarking\export\dockerinfo.json'
    if(-not(Test-Path $blueprintPath)-or -not(Test-Path $dockerInfoPath)){throw 'Benchmark blueprint or dockerinfo not found.'}
    $fixture=@{benchmark=@{env_name='l2rpn_case14_sandbox';max_steps=10;time_series_ids=@(0)}}|ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText((Join-Path $evidence 'benchmark-input.json'),$fixture,[Text.UTF8Encoding]::new($false))
    $input=@{protocol='inline';uri=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fixture));format='json'}
    $body=@{blueprint=(Get-Content $blueprintPath -Raw|ConvertFrom-Json);dockerinfo=(Get-Content $dockerInfoPath -Raw|ConvertFrom-Json);inputs=@($input);services_api_key=$settings.ServiceApiKey}|ConvertTo-Json -Depth 100
    $submission=Invoke-RestMethod -Uri "$($settings.OrchestratorUrl)/workflows" -Method Post -Headers (Get-OrchestratorHeaders $settings) -ContentType 'application/json' -Body $body
    $result=Wait-WorkflowComplete $settings $submission.workflow_id $TimeoutSeconds
    Save-Json $result.Workflow (Join-Path $evidence 'workflow.json');Save-Json $result.Tasks (Join-Path $evidence 'tasks.json')
    $task=$result.Tasks.tasks|Where-Object {$_.task_id}|Select-Object -Last 1;if($null -eq $task){throw 'No benchmark task was returned.'}
    docker cp "benchmark-runner:/artifacts/$($task.task_id).payload" (Join-Path $evidence 'benchmark-artifact.json');if($LASTEXITCODE -ne 0){throw 'Benchmark artifact was not found.'}
    docker cp "benchmark-runner:/artifacts/$($task.task_id).meta.json" (Join-Path $evidence 'benchmark-artifact-metadata.json')
    Write-Host "workflow=$($result.Workflow.status); task=$($task.task_id)";Write-Host 'RESULT: recorded. Frozen baseline may fail at common BenchmarkResult handoff after service execution.'
} finally {try{Stop-Transcript}catch{}}
