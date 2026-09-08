<#
.SYNOPSIS
Runs a small number of overlapping Portuguese workflows as a bounded concurrency smoke test.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 2)][int]$ParallelWorkflows = 2,
    [ValidateRange(10, 46993)][int]$MaxRows = 1000,
    [ValidateRange(60, 3600)][int]$TimeoutSeconds = 1200
)

. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Require-T33PortugalKeys
Assert-T33PortugalBaseline $s
$workspace = Assert-T33Workspace $s Integrated
foreach ($container in @((Get-T33OrchestratorContainer),'tef-data-provision','tef-knowledge-store','tef-synthetic-data')) { Wait-T33Container $container }
$e = New-T33PortugalEvidence $s '25-bounded-concurrency'
Start-T33PortugalTranscript $e

# Retain each workflow's final generated CSV and return its data-row count.
function Save-ConcurrentFinalCsv {
    param([int]$Index, [string]$TaskEvidencePath)
    if (-not (Test-Path -LiteralPath $TaskEvidencePath)) { return 0 }
    $taskData = Get-Content -LiteralPath $TaskEvidencePath -Raw | ConvertFrom-Json
    $candidates = @($taskData.tasks | Where-Object {
        $_.node_key -match 'GenerateData|generator' -and
        $null -ne $_.PSObject.Properties['output_refs'] -and
        @($_.output_refs).Count -gt 0
    } | Select-Object -Last 1)
    if ($candidates.Count -eq 0) { return 0 }
    $reference = @($candidates[0].output_refs)[0]
    if ($reference.protocol -ne 'http' -or [string]::IsNullOrWhiteSpace([string]$reference.uri)) { return 0 }
    $content = (& docker exec tef-synthetic-data curl -fsS $reference.uri 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) { return 0 }
    Save-T33Text (Join-Path $e "workflow-$Index-generated-data.csv") $content
    return (@($content -split "`r?`n" | Where-Object { $_ -ne '' }).Count - 1)
}

try {
    if ($ParallelWorkflows -ne 2) { throw 'T3.3 closure is intentionally limited to exactly two overlapping workflows.' }
    $blueprintPath = Join-Path $workspace 'export\blueprint.json'
    $dockerInfoPath = Join-Path $workspace 'export\dockerinfo.json'
    # Submit exactly two workflows before polling either one, creating overlap.
    $submitted = @()
    for ($index = 1; $index -le $ParallelWorkflows; $index++) {
        $request = @{
            blueprint=(Get-Content $blueprintPath -Raw | ConvertFrom-Json)
            dockerinfo=(Get-Content $dockerInfoPath -Raw | ConvertFrom-Json)
            inputs=@(ConvertTo-T33InlineReference @{file_path='/app/real_data.csv';max_rows=$MaxRows;rename_columns=@{datetime='timestamp'}})
            services_api_key=$env:SERVICE_API_KEY
        } | ConvertTo-Json -Depth 100 -Compress
        $started = Get-Date
        $response = Invoke-T33PortugalWebRequest -Method Post -Uri "$($s.OrchestratorUrl)/workflows" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY) -Body $request
        Save-T33Text (Join-Path $e "workflow-$index-submit.json") $response.Content
        if ($response.StatusCode -notin @(200,201,202)) { throw "Workflow $index submission returned HTTP $($response.StatusCode)." }
        $id = ($response.Content | ConvertFrom-Json).workflow_id
        if ([string]::IsNullOrWhiteSpace($id)) { throw "Workflow $index did not return an ID." }
        $submitted += [pscustomobject]@{Index=$index;WorkflowId=$id;StartedAt=$started;Status='submitted';FinishedAt=$null}
    }

    # Poll both workflows together and sample shared container resources.
    $statsPath = Join-Path $e 'resource-samples.tsv'
    "timestamp`tcontainer`tCPU`tMemoryUsage`tMemoryPercent`tPIDs" | Set-Content -Path $statsPath -Encoding utf8
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 5
        foreach ($item in @($submitted | Where-Object Status -notin @('complete','completed','failed','timeout'))) {
            $workflowResponse = Invoke-T33PortugalWebRequest -Method Get -Uri "$($s.OrchestratorUrl)/workflows/$($item.WorkflowId)" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY)
            $taskResponse = Invoke-T33PortugalWebRequest -Method Get -Uri "$($s.OrchestratorUrl)/workflows/$($item.WorkflowId)/tasks" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY)
            $state = $workflowResponse.Content | ConvertFrom-Json
            $item.Status = [string]$state.status
            Save-T33Text (Join-Path $e "workflow-$($item.Index)-workflow.json") $workflowResponse.Content
            Save-T33Text (Join-Path $e "workflow-$($item.Index)-tasks.json") $taskResponse.Content
            if ($item.Status -in @('complete','completed','failed')) { $item.FinishedAt = Get-Date }
            Write-Host "$(Get-Date -Format o) workflow=$($item.Index) id=$($item.WorkflowId) status=$($item.Status)"
        }
        $timestamp = Get-Date -Format o
        foreach ($row in @(& docker stats --no-stream --format "{{.Name}}`t{{.CPUPerc}}`t{{.MemUsage}}`t{{.MemPerc}}`t{{.PIDs}}" 2>&1)) {
            if ($row -match 'orchestrator|tef-') { Add-Content -Path $statsPath -Value "$timestamp`t$row" }
        }
    } while (@($submitted | Where-Object Status -notin @('complete','completed','failed')).Count -gt 0 -and (Get-Date) -lt $deadline)

    # Convert the retained per-workflow evidence into one reviewable result table.
    foreach ($item in $submitted) {
        if ($item.Status -notin @('complete','completed','failed')) { $item.Status='timeout';$item.FinishedAt=Get-Date }
    }
    $results = $submitted | ForEach-Object {
        $taskEvidencePath = Join-Path $e "workflow-$($_.Index)-tasks.json"
        $taskData = if (Test-Path -LiteralPath $taskEvidencePath) { Get-Content -LiteralPath $taskEvidencePath -Raw | ConvertFrom-Json } else { $null }
        $notCompleted = if ($null -ne $taskData) { @($taskData.tasks | Where-Object status -notin @('complete','completed')).Count } else { -1 }
        $outputRows = Save-ConcurrentFinalCsv -Index $_.Index -TaskEvidencePath $taskEvidencePath
        [pscustomobject][ordered]@{
            Index=$_.Index;WorkflowId=$_.WorkflowId;Status=$_.Status
            StartedAt=$_.StartedAt.ToString('o');FinishedAt=$_.FinishedAt.ToString('o')
            DurationSeconds=[math]::Round(($_.FinishedAt-$_.StartedAt).TotalSeconds,3)
            NonCompletedTasks=$notCompleted;OutputRows=$outputRows
        }
    }
    $results | Export-Csv -Path (Join-Path $e 'concurrency-results.csv') -NoTypeInformation -Encoding utf8
    $results | ConvertTo-Json | Set-Content -Path (Join-Path $e 'concurrency-results.json') -Encoding utf8

    if (@($results | Where-Object { $_.Status -in @('complete','completed') -and $_.NonCompletedTasks -eq 0 -and $_.OutputRows -gt 0 }).Count -eq $ParallelWorkflows) {
        Write-Host 'RESULT: PASS - two overlapping Portugal workflows completed. This is a bounded concurrency smoke test, not a capacity limit.'
    }
    else {
        Write-Host 'RESULT: FINDING RECORDED - one or both overlapping workflows failed or timed out. Do not increase concurrency; preserve the evidence.'
    }
}
finally { Stop-T33PortugalTranscript }
