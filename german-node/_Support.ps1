<#
.SYNOPSIS
Provides shared settings, evidence and container helpers for the German test scripts.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It centralises behaviour used by the executable tests.

.NOTES
This is an internal helper file loaded by other scripts; do not run it directly.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Settings {
    $path = Join-Path $PSScriptRoot 'Test-Settings.psd1'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Create Test-Settings.psd1 by copying Test-Settings.psd1.example.' }
    $s = Import-PowerShellDataFile -Path $path
    foreach ($name in 'RepositoryRoot','GermanyRoot','EvidenceRoot','ExpectedCommit','OrchestratorUrl','GermanyComposeFile','VillasServiceName') {
        if ([string]::IsNullOrWhiteSpace([string]$s[$name])) { throw "Missing setting: $name" }
    }
    $s['OrchestratorApiKey'] = $env:ORCHESTRATOR_API_KEY
    $s['ServiceApiKey'] = $env:SERVICE_API_KEY
    return $s
}
function Assert-Baseline { param([hashtable]$Settings)
    if (-not (Test-Path -LiteralPath $Settings.RepositoryRoot)) { throw "RepositoryRoot was not found: $($Settings.RepositoryRoot)" }
    Push-Location $Settings.RepositoryRoot
    try {
        if ((git rev-parse --is-inside-work-tree 2>$null).Trim() -ne 'true') { throw 'RepositoryRoot is not a Git worktree.' }
        if (git status --porcelain) { throw 'Repository is not clean. Stop without testing.' }
        $head=(git rev-parse HEAD).Trim()
        if ($head -ne $Settings.ExpectedCommit) { throw "Unexpected commit $head. Expected $($Settings.ExpectedCommit)." }
        if ((git submodule status --recursive) -match '(?m)^[+-U]') { throw 'One or more submodules are not pinned.' }
    } finally { Pop-Location }
}
function Require-Keys { param([hashtable]$Settings)
    if ([string]::IsNullOrWhiteSpace($Settings.OrchestratorApiKey)) { throw 'ORCHESTRATOR_API_KEY is not set in this terminal.' }
    if ([string]::IsNullOrWhiteSpace($Settings.ServiceApiKey)) { throw 'SERVICE_API_KEY is not set in this terminal.' }
}
function New-EvidenceFolder { param([hashtable]$Settings,[string]$TestId)
    $p=Join-Path $Settings.EvidenceRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$TestId)
    New-Item -ItemType Directory -Force -Path $p | Out-Null; return $p
}
function Save-Json { param($Object,[string]$Path); $Object | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 -Path $Path }
function Start-EvidenceTranscript { param([string]$Folder); Start-Transcript -Path (Join-Path $Folder 'run.txt') -Force }
function Stop-EvidenceTranscript { try { Stop-Transcript } catch {} }
function Get-OrchestratorHeaders { param([hashtable]$Settings); return @{ Authorization="Bearer $($Settings.OrchestratorApiKey)" } }
function Invoke-T33WebRequest {
    param([Parameter(Mandatory)][string]$Uri,[ValidateSet('Get','Post','Delete','Put')][string]$Method='Get',[hashtable]$Headers=@{},[string]$ContentType,[string]$Body)
    $params=@{Uri=$Uri;Method=$Method;UseBasicParsing=$true;ErrorAction='Stop'}
    if($Headers.Count){$params.Headers=$Headers};if($ContentType){$params.ContentType=$ContentType};if($PSBoundParameters.ContainsKey('Body')){$params.Body=$Body}
    try {$r=Invoke-WebRequest @params;return [pscustomobject]@{StatusCode=[int]$r.StatusCode;Content=[string]$r.Content}}
    catch [System.Net.WebException] {$response=$_.Exception.Response;if($null -eq $response){throw};$reader=New-Object System.IO.StreamReader($response.GetResponseStream());try{$content=$reader.ReadToEnd()}finally{$reader.Dispose()};return [pscustomobject]@{StatusCode=[int]$response.StatusCode;Content=$content}}
}
function Wait-Container { param([string]$Name,[int]$TimeoutSeconds=180)
    docker inspect $Name *> $null;if($LASTEXITCODE -ne 0){throw "Container not found: $Name"};$until=(Get-Date).AddSeconds($TimeoutSeconds)
    while((Get-Date)-lt $until){$state=(docker inspect $Name --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}').Trim();if($state -in 'healthy','running'){Write-Host "Container $Name is $state";return};if($state -in 'unhealthy','exited','dead'){throw "Container $Name failed; state=$state"};Write-Host "Waiting for ${Name}; state=$state";Start-Sleep -Seconds 5};throw "Container $Name did not become ready within $TimeoutSeconds seconds."
}
function Get-GermanyCompose { param([hashtable]$Settings);if(-not(Test-Path -LiteralPath $Settings.GermanyComposeFile)){throw "Germany Compose file was not found: $($Settings.GermanyComposeFile)"};return $Settings.GermanyComposeFile }
function Get-GermanyDefinition { param([hashtable]$Settings)
    $b=Join-Path $Settings.GermanyRoot 'export\blueprint.json';$d=Join-Path $Settings.GermanyRoot 'export\dockerinfo.json';if((Test-Path $b)-and(Test-Path $d)){return @{Blueprint=$b;DockerInfo=$d}};throw 'Germany export blueprint.json or dockerinfo.json was not found.'
}
