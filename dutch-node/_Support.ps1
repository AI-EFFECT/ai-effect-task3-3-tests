<#
.SYNOPSIS
Provides shared settings, evidence, HTTP and container helpers for the Dutch test scripts.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It centralises behaviour used by the executable tests.

.NOTES
This is an internal helper file loaded by other scripts; do not run it directly.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Settings {
    $path = Join-Path $PSScriptRoot 'Test-Settings.psd1'
    if (-not (Test-Path -LiteralPath $path)) { throw "Create Test-Settings.psd1 by copying Test-Settings.psd1.example." }
    $s = Import-PowerShellDataFile -Path $path
    foreach ($key in @('RepositoryRoot','EvidenceRoot','ExpectedCommit','OrchestratorUrl','NodePublicBaseUrl')) {
        if ([string]::IsNullOrWhiteSpace($s[$key])) { throw "Missing setting: $key" }
    }
    $s['OrchestratorApiKey'] = $env:ORCHESTRATOR_API_KEY
    $s['ServiceApiKey'] = $env:SERVICE_API_KEY
    return $s
}

function Assert-Baseline {
    param([hashtable]$Settings)
    if (-not (Test-Path -LiteralPath $Settings.RepositoryRoot)) { throw "RepositoryRoot was not found: $($Settings.RepositoryRoot)" }
    Push-Location $Settings.RepositoryRoot
    try {
        $inside = (git rev-parse --is-inside-work-tree 2>$null).Trim()
        if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') { throw 'RepositoryRoot is not a Git worktree.' }
        $changes = git status --porcelain
        if ($LASTEXITCODE -ne 0) { throw 'Git status could not be read.' }
        if ($changes) { throw 'Repository is not clean. Stop without testing.' }
        $commit = (git rev-parse HEAD).Trim()
        if ($commit -ne $Settings.ExpectedCommit) { throw "Unexpected commit $commit. Expected $($Settings.ExpectedCommit)." }
        $submodules = git submodule status --recursive
        if ($submodules -match '(?m)^[+-U]') { throw 'One or more submodules are not pinned.' }
    } finally { Pop-Location }
}

function Require-Keys {
    param([hashtable]$Settings,[switch]$OnlyOrchestrator)
    if ([string]::IsNullOrWhiteSpace($Settings.OrchestratorApiKey)) { throw 'ORCHESTRATOR_API_KEY is not available in this terminal.' }
    if (-not $OnlyOrchestrator -and [string]::IsNullOrWhiteSpace($Settings.ServiceApiKey)) { throw 'SERVICE_API_KEY is not available in this terminal.' }
}

function New-EvidenceFolder {
    param([hashtable]$Settings,[string]$TestId)
    $folder = Join-Path $Settings.EvidenceRoot ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$TestId)
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    return $folder
}

function Wait-Container {
    param([string]$Container,[int]$TimeoutSeconds=180)
    docker inspect $Container *> $null
    if ($LASTEXITCODE -ne 0) { throw "Container not found: $Container" }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $state = (docker inspect $Container --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}').Trim()
        if ($state -eq 'healthy' -or $state -eq 'running') { Write-Host "Container $Container is $state"; return }
        if ($state -eq 'unhealthy' -or $state -eq 'exited' -or $state -eq 'dead') { throw "Container $Container failed; state is $state" }
        Write-Host "Waiting for ${Container}; state is $state"
        Start-Sleep -Seconds 5
    }
    throw "Container $Container did not become ready within $TimeoutSeconds seconds."
}

function Get-OrchestratorHeaders { param([hashtable]$Settings) ; @{Authorization="Bearer $($Settings.OrchestratorApiKey)"} }

function Wait-WorkflowComplete {
    param([hashtable]$Settings,[string]$WorkflowId,[int]$TimeoutSeconds=1800)
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $workflow=Invoke-RestMethod -Method Get -Uri "$($Settings.OrchestratorUrl)/workflows/$WorkflowId" -Headers (Get-OrchestratorHeaders $Settings)
        $tasks=Invoke-RestMethod -Method Get -Uri "$($Settings.OrchestratorUrl)/workflows/$WorkflowId/tasks" -Headers (Get-OrchestratorHeaders $Settings)
        $summary=@($tasks.tasks|ForEach-Object { "$($_.node_key):$($_.status)" }) -join ', '
        Write-Host "$(Get-Date -Format o) workflow=$($workflow.status); tasks=$summary"
        if ($workflow.status -eq 'completed' -or $workflow.status -eq 'failed') { return @{Workflow=$workflow;Tasks=$tasks} }
        Start-Sleep -Seconds 5
    }
    throw "Workflow $WorkflowId did not finish within $TimeoutSeconds seconds."
}

function Save-Json { param($Object,[string]$Path) ; $Object|ConvertTo-Json -Depth 100|Set-Content -Path $Path -Encoding utf8 }
