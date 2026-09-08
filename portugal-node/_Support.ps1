<#
.SYNOPSIS
Provides shared settings, workspace, evidence, HTTP and container helpers for the Portuguese tests.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It centralises behaviour used by the executable tests.

.NOTES
This is an internal helper file loaded by other scripts; do not run it directly.
#>
Set-StrictMode -Version Latest

function Read-T33PortugalSettings {
    $path = Join-Path $PSScriptRoot 'Test-Settings.psd1'
    if (-not (Test-Path $path)) { throw 'Create Test-Settings.psd1 by copying Test-Settings.psd1.example.' }
    $settings = Import-PowerShellDataFile -Path $path
    foreach ($name in @('RepositoryRoot','TefServicesRoot','IntegratedOverlayRoot','SidecarOverlayRoot','IntegratedWorkspace','SidecarWorkspace','EvidenceRoot','ExpectedCommit','OrchestratorUrl','OrchestratorCompose')) {
        if (-not $settings.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($settings[$name])) { throw "Test-Settings.psd1 is missing $name." }
    }
    foreach ($pathToCheck in @($settings.RepositoryRoot,$settings.TefServicesRoot,$settings.IntegratedOverlayRoot,$settings.SidecarOverlayRoot,$settings.OrchestratorCompose)) {
        if (-not (Test-Path $pathToCheck)) { throw "Required path was not found: $pathToCheck" }
    }
    foreach ($service in @('data_provision','knowledge_store','synthetic_data_generation')) {
        $servicePath = Join-Path $settings.TefServicesRoot $service
        if (-not (Test-Path $servicePath)) { throw "TEF source service was not found: $servicePath" }
        if (-not (Test-Path (Join-Path $servicePath 'Dockerfile'))) { throw "TEF source Dockerfile was not found: $servicePath\Dockerfile" }
        if (-not (Test-Path (Join-Path $servicePath 'requirements.txt'))) { throw "TEF source requirements.txt was not found: $servicePath\requirements.txt" }
    }
    if (-not (Test-Path (Join-Path $settings.TefServicesRoot 'synthetic_data_generation\real_data.csv'))) { throw 'The supplied TEF fixture synthetic_data_generation\real_data.csv was not found.' }
    return $settings
}

function Assert-T33PortugalBaseline([hashtable]$Settings) {
    $actual = (& git -C $Settings.RepositoryRoot rev-parse HEAD).Trim()
    if ($actual -ne $Settings.ExpectedCommit) { throw "Unexpected source commit: $actual. Expected $($Settings.ExpectedCommit)." }
    $dirty = @(& git -C $Settings.RepositoryRoot status --porcelain)
    if ($dirty.Count -gt 0) { throw 'Repository is not clean. Stop without testing.' }
}

function Require-T33PortugalKeys {
    if ([string]::IsNullOrWhiteSpace($env:ORCHESTRATOR_API_KEY)) { throw 'ORCHESTRATOR_API_KEY is not set in this terminal.' }
    if ([string]::IsNullOrWhiteSpace($env:SERVICE_API_KEY)) { throw 'SERVICE_API_KEY is not set in this terminal.' }
}

function New-T33PortugalEvidence([hashtable]$Settings, [string]$Label) {
    $path = Join-Path $Settings.EvidenceRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Label)
    New-Item -ItemType Directory -Force $path | Out-Null
    return $path
}
function Start-T33PortugalTranscript([string]$EvidencePath) { Start-Transcript -Path (Join-Path $EvidencePath 'run.txt') -Force }
function Stop-T33PortugalTranscript { try { Stop-Transcript } catch { } }
function Get-T33BearerHeaders([string]$Key) { return @{ Authorization = "Bearer $Key" } }

function Ensure-T33SharedNetwork {
    & docker network inspect ai-effect-services *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Using the existing shared Docker network: ai-effect-services'
        return
    }

    Write-Host 'Creating the shared Docker network: ai-effect-services'
    & docker network create ai-effect-services | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the ai-effect-services Docker network.' }
}

function Get-T33SharedNetworkOverride([string]$Workspace) {
    $path = Join-Path $Workspace '.t33-shared-network.override.yml'
    if (-not (Test-Path $path)) { throw "The test-only shared-network override is missing: $path" }
    return $path
}

function Get-T33TestVolumeNames([ValidateSet('Integrated','Sidecar')][string]$Variant) {
    $prefix = if ($Variant -eq 'Integrated') { 'pt33-tef-integrated' } else { 'pt33-tef-sidecar' }
    return @(
        "${prefix}-clickhouse-data",
        "${prefix}-synthetic-models"
    )
}

function Remove-T33TestVolumes([ValidateSet('Integrated','Sidecar')][string]$Variant) {
    foreach ($volume in (Get-T33TestVolumeNames $Variant)) {
        & docker volume inspect $volume *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removing the isolated test volume: $volume"
            & docker volume rm $volume | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Could not remove $volume. Run 35-Stop-Portugal-Test-Services.ps1 first, then retry the reset."
            }
        }
    }
}

function Invoke-T33PortugalWebRequest {
    param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$Uri,[hashtable]$Headers=@{},[string]$Body,[string]$ContentType='application/json')
    try {
        $args=@{Method=$Method;Uri=$Uri;Headers=$Headers;UseBasicParsing=$true;ErrorAction='Stop'}
        if($PSBoundParameters.ContainsKey('Body')){$args.Body=$Body;$args.ContentType=$ContentType}
        $response=Invoke-WebRequest @args
        return [PSCustomObject]@{StatusCode=[int]$response.StatusCode;Content=[string]$response.Content}
    } catch {
        $webResponse=$_.Exception.Response
        if($null -eq $webResponse){throw}
        $reader=New-Object System.IO.StreamReader($webResponse.GetResponseStream());$content=$reader.ReadToEnd();$reader.Dispose()
        return [PSCustomObject]@{StatusCode=[int]$webResponse.StatusCode;Content=[string]$content}
    }
}

function ConvertTo-T33InlineReference([hashtable]$Object) {
    $json=$Object|ConvertTo-Json -Depth 30 -Compress
    return @{protocol='inline';uri=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json));format='json'}
}

function Wait-T33Container([string]$Name,[int]$TimeoutSeconds=300) {
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        & docker inspect $Name *> $null
        if($LASTEXITCODE -eq 0){
            $state=(& docker inspect $Name --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}').Trim()
            if($state -in @('healthy','running')){Write-Host "Container $Name is $state";return}
            Write-Host "Waiting for ${Name}; state=$state"
        } else {Write-Host "Waiting for $Name to be created"}
        Start-Sleep -Seconds 5
    } while((Get-Date)-lt $deadline)
    throw "Container $Name did not become healthy/running within $TimeoutSeconds seconds."
}

function Get-T33OrchestratorContainer {
    $names=@(& docker ps --format '{{.Names}}')
    $name=@($names|Where-Object{$_ -match '^orchestrator-api(-\d+)?$'}|Select-Object -First 1)[0]
    if([string]::IsNullOrWhiteSpace($name)){throw 'The orchestrator API container is not running.'}
    return $name
}
function Wait-T33HttpOk([string]$Uri,[int]$TimeoutSeconds=180) {
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try { $response=Invoke-WebRequest -UseBasicParsing -Uri $Uri -ErrorAction Stop;if([int]$response.StatusCode -eq 200){Write-Host "HTTP health check passed: $Uri";return} } catch { Write-Host "Waiting for HTTP health check: $Uri" }
        Start-Sleep -Seconds 5
    } while((Get-Date)-lt $deadline)
    throw "HTTP health check did not return 200 within $TimeoutSeconds seconds: $Uri"
}
function Save-T33Text([string]$Path,[string]$Content){[IO.File]::WriteAllText($Path,$Content,[Text.UTF8Encoding]::new($false))}
function Get-T33Workspace([hashtable]$Settings,[ValidateSet('Integrated','Sidecar')][string]$Variant){if($Variant -eq 'Integrated'){return $Settings.IntegratedWorkspace};return $Settings.SidecarWorkspace}
function Assert-T33Workspace([hashtable]$Settings,[ValidateSet('Integrated','Sidecar')][string]$Variant){$workspace=Get-T33Workspace $Settings $Variant;$marker=Join-Path $workspace '.t33-portugal-workspace.json';if(-not(Test-Path $marker)){throw "$Variant workspace is not prepared. Run its preparation script first."};return $workspace}

function New-T33Workspace {
    param([hashtable]$Settings,[ValidateSet('Integrated','Sidecar')][string]$Variant,[switch]$Reset)
    $workspace=Get-T33Workspace $Settings $Variant;$marker=Join-Path $workspace '.t33-portugal-workspace.json'
    if(Test-Path $workspace){
        if(-not $Reset){throw "$workspace already exists. Inspect its evidence, then rerun this script with -Reset to replace this known test workspace."}
        if(-not(Test-Path $marker)){throw "Refusing to replace $workspace because it is not marked as a T3.3 Portugal test workspace."}
        Remove-T33TestVolumes $Variant
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
    New-Item -ItemType Directory -Force $workspace|Out-Null
    foreach($service in @('data_provision','knowledge_store','synthetic_data_generation')){Copy-Item (Join-Path $Settings.TefServicesRoot $service) -Destination $workspace -Recurse -Force}
    $overlay=if($Variant -eq 'Integrated'){$Settings.IntegratedOverlayRoot}else{$Settings.SidecarOverlayRoot}
    Copy-Item (Join-Path $overlay '*') -Destination $workspace -Recurse -Force
    New-Item -ItemType Directory -Force (Join-Path $workspace 'data')|Out-Null
    $fixtureSource=Join-Path $Settings.TefServicesRoot 'synthetic_data_generation\real_data.csv'
    Copy-Item $fixtureSource (Join-Path $workspace 'data\real_data.csv') -Force
    $prefix = if ($Variant -eq 'Integrated') { 'pt33-tef-integrated' } else { 'pt33-tef-sidecar' }
    $knowledgeService = if ($Variant -eq 'Integrated') { 'knowledge-store' } else { 'sc-knowledge-store' }
    $syntheticService = if ($Variant -eq 'Integrated') { 'synthetic-data' } else { 'sc-synthetic-data' }
    @"
# Test-suite override. This file is created only in the disposable T3.3 workspace.
# It joins the existing AI-EFFECT shared network without claiming ownership of it.
services:
  ${knowledgeService}:
    # The supplied Compose check calls curl on /, but this image has no curl and the API health endpoint is /health.
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=5).read()"]
      interval: 30s
      timeout: 10s
      retries: 3
  ${syntheticService}:
    # The supplied check calls the undefined root path. The running API exposes OpenAPI at /openapi.json.
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:600/openapi.json"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  tef-network:
    name: ai-effect-services
    external: true

volumes:
  clickhouse_data:
    name: ${prefix}-clickhouse-data
  synthetic_models:
    name: ${prefix}-synthetic-models
"@ | Set-Content -Path (Join-Path $workspace '.t33-shared-network.override.yml') -Encoding utf8
    [ordered]@{variant=$Variant;created_at=(Get-Date).ToString('o');source_root=$Settings.TefServicesRoot;overlay_root=$overlay;source_fixture_sha256=(Get-FileHash -Algorithm SHA256 $fixtureSource).Hash}|ConvertTo-Json|Set-Content -Path $marker -Encoding utf8
    return $workspace
}
