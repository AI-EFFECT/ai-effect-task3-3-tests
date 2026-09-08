<#
.SYNOPSIS
Repeats the integrated workflow and records duration, output structure, hashes and resource samples.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 5)][int]$Repetitions = 3,
    [ValidateRange(10, 46993)][int]$MaxRows = 1000,
    [ValidateRange(60, 3600)][int]$TimeoutSeconds = 900
)

. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Require-T33PortugalKeys
Assert-T33PortugalBaseline $s
$workspace = Assert-T33Workspace $s Integrated
Wait-T33Container (Get-T33OrchestratorContainer)
foreach ($container in @('tef-data-provision','tef-knowledge-store','tef-synthetic-data')) { Wait-T33Container $container }

$e = New-T33PortugalEvidence $s '23-repeatability-performance-reference'
Start-T33PortugalTranscript $e

# Capture point-in-time container statistics before, during and after each run.
function Add-PortugalResourceSample {
    param([string]$Path, [int]$Iteration, [string]$Phase)
    $timestamp = Get-Date -Format o
    $rows = @(& docker stats --no-stream --format "{{.Name}}`t{{.CPUPerc}}`t{{.MemUsage}}`t{{.MemPerc}}`t{{.PIDs}}" 2>&1)
    foreach ($row in $rows) {
        if ($row -match 'orchestrator|tef-') { Add-Content -Path $Path -Value "$timestamp`t$Iteration`t$Phase`t$row" }
    }
}

# Resolve the final generated-data reference and retain the referenced CSV.
function Get-PortugalFinalCsv {
    param($Tasks, [string]$OutputPath)
    $candidates = @($Tasks.tasks | Where-Object {
        $_.node_key -match 'GenerateData|generator' -and
        $null -ne $_.PSObject.Properties['output_refs'] -and
        @($_.output_refs).Count -gt 0
    } | Select-Object -Last 1)
    if ($candidates.Count -eq 0) { return $null }
    $task = $candidates[0]
    $references = @($task.output_refs)
    if ($references.Count -eq 0) { return $null }
    $reference = $references[0]
    if ($reference.protocol -ne 'http' -or [string]::IsNullOrWhiteSpace([string]$reference.uri)) { return $null }
    $content = (& docker exec tef-synthetic-data curl -fsS $reference.uri 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) { return $null }
    Save-T33Text $OutputPath $content
    return $content
}

try {
    $statsPath = Join-Path $e 'resource-samples.tsv'
    "timestamp`titeration`tphase`tcontainer`tCPU`tMemoryUsage`tMemoryPercent`tPIDs" | Set-Content -Path $statsPath -Encoding utf8
    $blueprintPath = Join-Path $workspace 'export\blueprint.json'
    $dockerInfoPath = Join-Path $workspace 'export\dockerinfo.json'
    if (-not (Test-Path $blueprintPath) -or -not (Test-Path $dockerInfoPath)) { throw 'Exported integrated workflow definition is missing.' }

    # Run the same bounded workload repeatedly under the same frozen baseline.
    $measurements = @()
    for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
        Write-Host "=== Portugal repeatability run $iteration of $Repetitions; MaxRows=$MaxRows ==="
        Add-PortugalResourceSample -Path $statsPath -Iteration $iteration -Phase 'before'
        $input = ConvertTo-T33InlineReference @{ file_path='/app/real_data.csv'; max_rows=$MaxRows; rename_columns=@{datetime='timestamp'} }
        $request = @{
            blueprint=(Get-Content $blueprintPath -Raw | ConvertFrom-Json)
            dockerinfo=(Get-Content $dockerInfoPath -Raw | ConvertFrom-Json)
            inputs=@($input)
            services_api_key=$env:SERVICE_API_KEY
        } | ConvertTo-Json -Depth 100 -Compress

        $started = Get-Date
        $submitted = Invoke-T33PortugalWebRequest -Method Post -Uri "$($s.OrchestratorUrl)/workflows" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY) -Body $request
        Save-T33Text (Join-Path $e "run-$iteration-submit.json") $submitted.Content
        if ($submitted.StatusCode -notin @(200,201,202)) { throw "Run $iteration submission returned HTTP $($submitted.StatusCode)." }
        $workflowId = ($submitted.Content | ConvertFrom-Json).workflow_id
        if ([string]::IsNullOrWhiteSpace($workflowId)) { throw "Run $iteration did not return workflow_id." }

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 5
            $workflowResponse = Invoke-T33PortugalWebRequest -Method Get -Uri "$($s.OrchestratorUrl)/workflows/$workflowId" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY)
            $taskResponse = Invoke-T33PortugalWebRequest -Method Get -Uri "$($s.OrchestratorUrl)/workflows/$workflowId/tasks" -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY)
            $workflow = $workflowResponse.Content | ConvertFrom-Json
            $tasks = $taskResponse.Content | ConvertFrom-Json
            Add-PortugalResourceSample -Path $statsPath -Iteration $iteration -Phase 'running'
            Write-Host "$(Get-Date -Format o) run=$iteration workflow=$($workflow.status)"
        } while ($workflow.status -notin @('complete','completed','failed') -and (Get-Date) -lt $deadline)

        Save-T33Text (Join-Path $e "run-$iteration-workflow.json") $workflowResponse.Content
        Save-T33Text (Join-Path $e "run-$iteration-tasks.json") $taskResponse.Content
        Add-PortugalResourceSample -Path $statsPath -Iteration $iteration -Phase 'after'
        # Reduce each run to comparable timing and output-structure measures.
        $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
        $csvPath = Join-Path $e "run-$iteration-generated-data.csv"
        $content = Get-PortugalFinalCsv -Tasks $tasks -OutputPath $csvPath
        $lines = if ($content) { @($content -split "`r?`n" | Where-Object { $_ -ne '' }) } else { @() }
        $header = if ($lines.Count) { $lines[0] } else { '' }
        $columns = if ($header) { @($header -split ',').Count } else { 0 }
        $rows = if ($lines.Count) { $lines.Count - 1 } else { 0 }
        $hash = if (Test-Path $csvPath) { (Get-FileHash -Algorithm SHA256 $csvPath).Hash } else { '' }

        $measurements += [pscustomobject][ordered]@{
            Iteration=$iteration; WorkflowId=$workflowId; Status=$workflow.status
            DurationSeconds=$duration; RequestedRows=$MaxRows; OutputRows=$rows
            OutputColumns=$columns; Header=$header; OutputSha256=$hash
        }
    }

    # Aggregate only the T3.3 repeatability reference; this is not load testing.
    $measurements | Export-Csv -Path (Join-Path $e 'measurements.csv') -NoTypeInformation -Encoding utf8
    $measurements | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $e 'measurements.json') -Encoding utf8
    $completed = @($measurements | Where-Object Status -in @('complete','completed'))
    $structureKeys = @($completed | ForEach-Object { "$($_.OutputRows)|$($_.OutputColumns)|$($_.Header)" } | Sort-Object -Unique)
    $durations = @($measurements.DurationSeconds)
    [pscustomobject]@{
        Runs=$measurements.Count; Completed=$completed.Count
        MinimumSeconds=[math]::Round(($durations|Measure-Object -Minimum).Minimum,3)
        MeanSeconds=[math]::Round(($durations|Measure-Object -Average).Average,3)
        MaximumSeconds=[math]::Round(($durations|Measure-Object -Maximum).Maximum,3)
        StableOutputStructure=($structureKeys.Count -eq 1 -and $completed.Count -eq $measurements.Count)
    } | ConvertTo-Json | Set-Content -Path (Join-Path $e 'summary.json') -Encoding utf8

    if ($completed.Count -eq $measurements.Count -and $structureKeys.Count -eq 1 -and $completed.OutputRows -notcontains 0) {
        Write-Host 'RESULT: PASS - repeated workflows completed with a stable output structure. Timing and resource evidence is an initial technical reference only.'
    }
    else {
        Write-Host 'RESULT: FINDING RECORDED - completion or output structure differed across repeated runs. Preserve all evidence.'
    }
}
finally { Stop-T33PortugalTranscript }
