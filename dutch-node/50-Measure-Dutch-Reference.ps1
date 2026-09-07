[CmdletBinding()]
param(
    [ValidateRange(1, 5)][int]$Repetitions = 3,
    [ValidateSet('Benchmark', 'Synthesizer', 'Both')][string]$Workload = 'Both',
    [ValidateRange(60, 3600)][int]$TimeoutSeconds = 1800
)

. (Join-Path $PSScriptRoot '_Support.ps1')

$settings = Read-Settings
Require-Keys $settings
Assert-Baseline $settings

$evidence = New-EvidenceFolder $settings '50-initial-performance-reference'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force

function Save-DutchResourceSnapshot {
    param([string]$Path, [string]$Phase, [string]$TestName, [int]$Iteration)

    $timestamp = Get-Date -Format o
    $rows = @(& docker stats --no-stream --format "{{.Name}}`t{{.CPUPerc}}`t{{.MemUsage}}`t{{.MemPerc}}`t{{.NetIO}}`t{{.BlockIO}}`t{{.PIDs}}" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-Content -Path $Path -Value "$timestamp`t$Phase`t$TestName`t$Iteration`tDOCKER_STATS_FAILED"
        return
    }

    foreach ($row in $rows) {
        if ($row -match 'orchestrator|synthetic-data|benchmark-runner|hai-|redis') {
            Add-Content -Path $Path -Value "$timestamp`t$Phase`t$TestName`t$Iteration`t$row"
        }
    }
}

try {
    $statsPath = Join-Path $evidence 'resource-snapshots.tsv'
    "timestamp`tphase`ttest`titeration`tcontainer`tCPU`tMemoryUsage`tMemoryPercent`tNetworkIO`tBlockIO`tPIDs" | Set-Content -Path $statsPath -Encoding utf8

    $tests = @()
    if ($Workload -in @('Synthesizer', 'Both')) {
        $tests += [pscustomobject]@{
            Name = 'Synthesizer'
            Script = '10-Test-Synthesizer.ps1'
            EvidenceSuffix = '10-synthesizer'
            RequiredFiles = @('run.txt','workflow.json','tasks.json','synth-artifact.json','synth-artifact-metadata.json')
            ExpectedResult = 'RESULT: service artifact retained.'
        }
    }
    if ($Workload -in @('Benchmark', 'Both')) {
        $tests += [pscustomobject]@{
            Name = 'Benchmark'
            Script = '20-Test-Benchmark.ps1'
            EvidenceSuffix = '20-benchmark'
            RequiredFiles = @('run.txt','workflow.json','tasks.json','benchmark-artifact.json','benchmark-artifact-metadata.json')
            ExpectedResult = 'RESULT: recorded.'
        }
    }

    $measurements = @()
    foreach ($test in $tests) {
        $scriptPath = Join-Path $PSScriptRoot $test.Script
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Required released test is missing: $scriptPath" }

        for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
            Write-Host "=== $($test.Name) initial-reference run $iteration of $Repetitions ==="
            Save-DutchResourceSnapshot -Path $statsPath -Phase 'before' -TestName $test.Name -Iteration $iteration
            $started = Get-Date
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',("`"$scriptPath`""),'-TimeoutSeconds',$TimeoutSeconds)
            $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -NoNewWindow -PassThru
            do {
                Start-Sleep -Seconds 5
                Save-DutchResourceSnapshot -Path $statsPath -Phase 'running' -TestName $test.Name -Iteration $iteration
                $process.Refresh()
            } while (-not $process.HasExited)
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            $watch.Stop()
            Save-DutchResourceSnapshot -Path $statsPath -Phase 'after' -TestName $test.Name -Iteration $iteration

            # The released scripts deliberately preserve artifacts after the
            # known common handoff failure. On Windows PowerShell, native Docker
            # output can leave powershell.exe with a non-zero host exit code even
            # though that expected evidence path completed. Validate the actual
            # child evidence instead of treating the host exit code as the
            # functional verdict.
            $childEvidence = Get-ChildItem -LiteralPath $settings.EvidenceRoot -Directory |
                Where-Object {
                    $_.Name -like "*-$($test.EvidenceSuffix)" -and
                    $_.CreationTime -ge $started.AddSeconds(-5)
                } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            $missingFiles = @()
            $expectedResultFound = $false
            if ($null -ne $childEvidence) {
                foreach ($requiredFile in $test.RequiredFiles) {
                    if (-not (Test-Path -LiteralPath (Join-Path $childEvidence.FullName $requiredFile))) {
                        $missingFiles += $requiredFile
                    }
                }
                $childTranscript = Join-Path $childEvidence.FullName 'run.txt'
                if (Test-Path -LiteralPath $childTranscript) {
                    $expectedResultFound = (Get-Content -LiteralPath $childTranscript -Raw) -like "*$($test.ExpectedResult)*"
                }
            }
            $evidenceComplete = ($null -ne $childEvidence -and $missingFiles.Count -eq 0 -and $expectedResultFound)

            $measurements += [pscustomobject][ordered]@{
                Node              = 'Dutch'
                Test              = $test.Name
                Iteration         = $iteration
                StartedAt         = $started.ToString('o')
                DurationSeconds   = [math]::Round($watch.Elapsed.TotalSeconds, 3)
                ChildExitCode     = $exitCode
                ChildEvidenceFolder = if ($null -ne $childEvidence) { $childEvidence.FullName } else { '' }
                ExpectedResultFound = $expectedResultFound
                MissingEvidenceFiles = ($missingFiles -join ';')
                EvidenceComplete  = $evidenceComplete
                BaselineCommit    = $settings.ExpectedCommit
                Interpretation    = 'Initial technical reference only; existing functional verdict remains authoritative.'
            }
        }
    }

    $measurements | Export-Csv -Path (Join-Path $evidence 'measurements.csv') -NoTypeInformation -Encoding utf8
    $summary = $measurements | Group-Object Test | ForEach-Object {
        $durations = @($_.Group.DurationSeconds)
        [pscustomobject][ordered]@{
            Test            = $_.Name
            Runs            = $_.Count
            CompleteEvidenceRuns = @($_.Group | Where-Object EvidenceComplete -eq $true).Count
            ZeroExitCodeRuns = @($_.Group | Where-Object ChildExitCode -eq 0).Count
            MinimumSeconds  = [math]::Round(($durations | Measure-Object -Minimum).Minimum, 3)
            MeanSeconds     = [math]::Round(($durations | Measure-Object -Average).Average, 3)
            MaximumSeconds  = [math]::Round(($durations | Measure-Object -Maximum).Maximum, 3)
        }
    }
    Save-Json $summary (Join-Path $evidence 'summary.json')
    $summary | Format-Table -AutoSize

    if (@($measurements | Where-Object EvidenceComplete -ne $true).Count -gt 0) {
        Write-Host 'RESULT: RECORDED WITH INCOMPLETE EVIDENCE - one or more child runs did not produce the required artifacts and result marker. Preserve all evidence.'
    }
    else {
        Write-Host 'RESULT: PASS - every child run produced complete expected evidence; repeatable wall-clock and resource references were recorded. Child exit codes are diagnostic only. This is not a scalability result.'
    }
}
finally {
    try { Stop-Transcript } catch { }
}
