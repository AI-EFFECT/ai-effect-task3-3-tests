<#
.SYNOPSIS
Records the frozen baselines, Docker, disk space and keys before any supplementary test runs.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Checks the platform commit, each node's source commit,
Docker Engine and Compose, free disk space and the presence (never the values) of the test keys.
BLOCKED lists what to fix. Node-level problems are listed per node so other nodes can still be tested.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '00-preflight' -Body {
    param($e)
    $checks = New-Object System.Collections.Generic.List[object]
    function Add-Check([string]$Scope, [string]$Name, [bool]$Ok, [string]$Detail) {
        $checks.Add([pscustomobject]@{ Scope = $Scope; Check = $Name; Ok = $Ok; Detail = $Detail })
        $mark = if ($Ok) { 'OK  ' } else { 'FAIL' }
        Write-Host "$mark [$Scope] ${Name}: $Detail"
    }

    $engine = Invoke-T33Docker @('version','--format','{{.Server.Version}}') -AllowFailure
    Add-Check 'core' 'Docker Engine' ($engine.ExitCode -eq 0) $engine.Output.Trim()
    $compose = Invoke-T33Docker @('compose','version','--short') -AllowFailure
    Add-Check 'core' 'Docker Compose' ($compose.ExitCode -eq 0) $compose.Output.Trim()

    $freeEvidence = Get-T33FreeGB $s.EvidenceRoot
    Add-Check 'core' 'free disk on evidence drive' ($freeEvidence -ge [double]$s.MinimumFreeGB) "$freeEvidence GB free, $($s.MinimumFreeGB) GB required"
    $freeSystem = Get-T33FreeGB $env:SystemDrive
    Add-Check 'core' 'free disk on system drive (Docker data)' ($freeSystem -ge [double]$s.MinimumFreeGB) "$freeSystem GB free, $($s.MinimumFreeGB) GB required"

    foreach ($key in @('ORCHESTRATOR_API_KEY','SERVICE_API_KEY')) {
        $present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))
        Add-Check 'core' "environment $key" $present $(if ($present) { 'set' } else { 'not set' })
    }

    $platformCommit = ''
    try { $platformCommit = Assert-T33SupCommit $s.PlatformRoot $s.PlatformCommit; Add-Check 'core' 'platform commit' $true $platformCommit }
    catch { Add-Check 'core' 'platform commit' $false ($_.Exception.Message -replace '^T33-BLOCKED: ','') }
    Add-Check 'core' 'orchestrator Compose file' (Test-Path $s.OrchestratorCompose) $s.OrchestratorCompose
    Add-Check 'core' 'onboarding export generator' (Test-Path (Join-Path $s.PlatformRoot 'scripts\onboarding-export-generator.py')) 'scripts\onboarding-export-generator.py'
    $python = Get-Command python -ErrorAction SilentlyContinue
    Add-Check 'core' 'Python for the export generator' ($null -ne $python) $(if ($python) { $python.Source } else { 'python not found on PATH' })

    $nodeReady = [ordered]@{}
    foreach ($name in $s.Nodes.Keys) {
        $node = Get-T33SupNode $s $name
        $ok = $true
        try { $commit = Assert-T33SupCommit $node.SourceRoot $node.ExpectedCommit; Add-Check $name 'source commit' $true $commit }
        catch { $ok = $false; Add-Check $name 'source commit' $false ($_.Exception.Message -replace '^T33-BLOCKED: ','') }
        foreach ($set in $node.ComposeSets) {
            foreach ($file in @($set -split ';' | Where-Object { $_.Trim() })) {
                $exists = Test-Path $file.Trim()
                if (-not $exists) { $ok = $false }
                Add-Check $name 'Compose file' $exists $file.Trim()
            }
        }
        $nodeReady[$name] = $ok
    }

    Save-T33Json (Join-Path $e 'preflight.json') ([ordered]@{
        machine = [Environment]::MachineName
        powershell = $PSVersionTable.PSVersion.ToString()
        docker_engine = $engine.Output.Trim()
        docker_compose = $compose.Output.Trim()
        platform_commit = $platformCommit
        node_ready = $nodeReady
        checks = $checks
    })

    $coreFailed = @($checks | Where-Object { $_.Scope -eq 'core' -and -not $_.Ok } | ForEach-Object { $_.Check })
    if ($coreFailed.Count -gt 0) { return (New-T33Verdict 'BLOCKED' "fix these before testing: $($coreFailed -join ', ').") }
    $notReady = @($nodeReady.Keys | Where-Object { -not $nodeReady[$_] })
    if ($notReady.Count -gt 0) { return (New-T33Verdict 'RECORDED' "core is ready; these nodes are not ready and their node-level tests will be blocked: $($notReady -join ', ').") }
    return (New-T33Verdict 'PASS' 'frozen baselines, Docker, disk space and keys are ready for every node.')
}
