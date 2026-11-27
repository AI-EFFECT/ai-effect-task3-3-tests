<#
.SYNOPSIS
Provides shared settings, evidence, Docker, Compose and orchestrator helpers for the supplementary Task 3.3 tests.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. It centralises behaviour used by the executable tests.
Secrets are read only from environment variables and are never printed or saved.

.NOTES
This is an internal helper file loaded by other scripts; do not run it directly.
#>
Set-StrictMode -Version Latest

$script:T33HelperImage = 'alpine:3.20'
$script:T33NodeNames = @('Germany','Portugal','Netherlands')

# Settings and frozen-source checks
function Read-T33SupSettings {
    $path = Join-Path $PSScriptRoot 'Test-Settings.psd1'
    if (-not (Test-Path $path)) { throw 'Create Test-Settings.psd1 by copying Test-Settings.psd1.example.' }
    $settings = Import-PowerShellDataFile -Path $path
    foreach ($name in @('EvidenceRoot','PlatformRoot','PlatformCommit','OrchestratorUrl','OrchestratorCompose','VendorWorkspace','VendorPortBase','MinimumFreeGB','Nodes')) {
        if (-not $settings.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$settings[$name])) { throw "Test-Settings.psd1 is missing $name." }
    }
    return $settings
}

function Get-T33SupNode([hashtable]$Settings, [string]$Name) {
    if (-not $Settings.Nodes.ContainsKey($Name)) { throw "Node '$Name' is not defined in Test-Settings.psd1." }
    $node = $Settings.Nodes[$Name]
    foreach ($key in @('SourceRoot','ExpectedCommit','ComposeSets')) {
        if (-not $node.ContainsKey($key)) { throw "Node '$Name' is missing $key in Test-Settings.psd1." }
    }
    return $node
}

function Assert-T33SupCommit([string]$Root, [string]$Expected) {
    if (-not (Test-Path $Root)) { Stop-T33Blocked "Source root was not found: $Root" }
    $actual = (& git -C $Root rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($actual)) { Stop-T33Blocked "Could not read the source commit in $Root." }
    $actual = $actual.Trim()
    if ($actual -ne $Expected) { Stop-T33Blocked "Unexpected source commit in ${Root}: $actual. Expected $Expected." }
    $dirty = @(& git -C $Root status --porcelain 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($dirty.Count -gt 0) { Stop-T33Blocked "Source tree $Root is not clean ($($dirty.Count) changed paths). Stop without testing." }
    return $actual
}

function Assert-T33SupPlatform([hashtable]$Settings) { return (Assert-T33SupCommit $Settings.PlatformRoot $Settings.PlatformCommit) }

function Require-T33SupKeys {
    if ([string]::IsNullOrWhiteSpace($env:ORCHESTRATOR_API_KEY)) { Stop-T33Blocked 'ORCHESTRATOR_API_KEY is not set in this terminal.' }
    if ([string]::IsNullOrWhiteSpace($env:SERVICE_API_KEY)) { Stop-T33Blocked 'SERVICE_API_KEY is not set in this terminal.' }
}

# Verdicts and the test wrapper
function Stop-T33Blocked([string]$Message) { throw [System.InvalidOperationException]::new("T33-BLOCKED: $Message") }

function New-T33Verdict([ValidateSet('PASS','FAIL','DEFECT CONFIRMED','BLOCKED','RECORDED','FINDINGS RECORDED')][string]$Verdict, [string]$Message) {
    return [pscustomobject]@{ Verdict = $Verdict; Message = $Message }
}

# Runs one test body inside a timestamped evidence folder and prints exactly one RESULT line.
# Harness failures are reported as ERROR, never as FAIL, so they cannot be counted as defects.
function Invoke-T33SupTest {
    param([Parameter(Mandatory)][hashtable]$Settings, [Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Body)
    $evidence = Join-Path $Settings.EvidenceRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Label)
    New-Item -ItemType Directory -Force $evidence | Out-Null
    Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force | Out-Null
    $verdict = 'ERROR'; $message = 'the test body returned no verdict.'
    try {
        Write-Host "Evidence folder: $evidence"
        Write-Host "Started at $((Get-Date).ToString('o')) on PowerShell $($PSVersionTable.PSVersion)"
        $result = & $Body $evidence
        $final = @($result | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains 'Verdict' }) | Select-Object -Last 1
        if ($null -ne $final) { $verdict = $final.Verdict; $message = $final.Message }
    }
    catch {
        if ($_.Exception.Message -like 'T33-BLOCKED: *') { $verdict = 'BLOCKED'; $message = $_.Exception.Message.Substring(13) }
        else {
            $verdict = 'ERROR'
            $message = "harness error: $($_.Exception.Message). Fix the harness and rerun; preserve this evidence folder."
            Write-Host ($_ | Out-String)
        }
    }
    finally {
        Write-Host "RESULT: $verdict - $message"
        Stop-Transcript | Out-Null
    }
    if ($verdict -in @('PASS','RECORDED','FINDINGS RECORDED')) { exit 0 } else { exit 1 }
}

# Evidence helpers
function Save-T33Text([string]$Path, [string]$Content) { [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false)) }
function Save-T33Json([string]$Path, $Object) { Save-T33Text $Path ($Object | ConvertTo-Json -Depth 30) }
function Save-T33Csv([string]$Path, $Rows) { @($Rows) | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }

function Get-T33FreeGB([string]$Path) {
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    $drive = [IO.DriveInfo]::new($root)
    return [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
}

# Docker and Compose helpers. Native stderr is discarded so Windows PowerShell does not turn it into errors.
function Invoke-T33Docker([string[]]$DockerArgs, [switch]$AllowFailure) {
    $out = & docker @DockerArgs 2>$null
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and -not $AllowFailure) { throw "docker $($DockerArgs -join ' ') failed with exit code $exit." }
    return [pscustomobject]@{ ExitCode = $exit; Output = (@($out) -join "`n") }
}

function Get-T33ComposeFiles([string]$ComposeSet) {
    $files = @($ComposeSet -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($file in $files) { if (-not (Test-Path $file)) { Stop-T33Blocked "Compose file was not found: $file" } }
    return $files
}

function Get-T33ComposeArgs([string]$ComposeSet) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($file in (Get-T33ComposeFiles $ComposeSet)) { $list.Add('-f'); $list.Add($file) }
    return $list.ToArray()
}

# Returns the resolved Compose model. It may contain interpolated secrets, so callers must save only extracts.
function Get-T33ComposeModel([string]$ComposeSet) {
    $result = Invoke-T33Docker (@('compose') + (Get-T33ComposeArgs $ComposeSet) + @('config','--format','json'))
    return ($result.Output | ConvertFrom-Json)
}

function Get-T33ComposeContainers([string]$ComposeSet) {
    $result = Invoke-T33Docker (@('compose') + (Get-T33ComposeArgs $ComposeSet) + @('ps','-a','--format','json'))
    $text = $result.Output.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    if ($text.StartsWith('[')) { return @($text | ConvertFrom-Json) }
    return @($text -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-T33NodeContainers([hashtable]$Node) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($set in $Node.ComposeSets) { foreach ($c in (Get-T33ComposeContainers $set)) { $names.Add([string]$c.Name) } }
    return @($names | Sort-Object -Unique)
}

function Get-T33NodeVolumes([hashtable]$Node) {
    $volumes = New-Object System.Collections.Generic.List[string]
    foreach ($set in $Node.ComposeSets) {
        $model = Get-T33ComposeModel $set
        if ($model.PSObject.Properties.Name -contains 'volumes' -and $null -ne $model.volumes) {
            foreach ($prop in $model.volumes.PSObject.Properties) {
                $name = if ($prop.Value.PSObject.Properties.Name -contains 'name' -and $prop.Value.name) { [string]$prop.Value.name } else { "$($model.name)_$($prop.Name)" }
                $volumes.Add($name)
            }
        }
    }
    return @($volumes | Sort-Object -Unique)
}

function Get-T33ContainerState([string]$Name) {
    $r = Invoke-T33Docker @('inspect',$Name,'--format','{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}') -AllowFailure
    if ($r.ExitCode -ne 0) { return 'missing' }
    return $r.Output.Trim()
}

function Wait-T33Container([string]$Name, [int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $state = Get-T33ContainerState $Name
        if ($state -in @('healthy','running')) { Write-Host "Container $Name is $state"; return $state }
        Write-Host "Waiting for ${Name}; state=$state"
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return (Get-T33ContainerState $Name)
}

function Get-T33CoreContainers {
    $r = Invoke-T33Docker @('ps','-a','--format','{{.Names}}')
    return @($r.Output -split "`n" | Where-Object { $_ -match '^orchestrator-(api|worker|redis)(-\d+)?$' } | Sort-Object)
}

function Ensure-T33HelperImage {
    $r = Invoke-T33Docker @('image','inspect',$script:T33HelperImage,'--format','{{index .RepoDigests 0}}') -AllowFailure
    if ($r.ExitCode -ne 0) {
        Write-Host "Pulling helper image $script:T33HelperImage"
        Invoke-T33Docker @('pull',$script:T33HelperImage) | Out-Null
        $r = Invoke-T33Docker @('image','inspect',$script:T33HelperImage,'--format','{{index .RepoDigests 0}}')
    }
    return $r.Output.Trim()
}

# File manifest of a named volume: one "sha256  ./path" line per file, sorted by path.
function Get-T33VolumeManifest([string]$Volume) {
    $cmd = 'cd /v && find . -type f -print0 | sort -z | xargs -0 -r sha256sum'
    $r = Invoke-T33Docker @('run','--rm','-v',"${Volume}:/v:ro",$script:T33HelperImage,'sh','-c',$cmd)
    return $r.Output
}

# HTTP helpers
function Invoke-T33Request {
    param([Parameter(Mandatory)][string]$Method, [Parameter(Mandatory)][string]$Uri, [hashtable]$Headers = @{}, [string]$Body, [int]$TimeoutSeconds = 30)
    try {
        $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; UseBasicParsing = $true; ErrorAction = 'Stop'; TimeoutSec = $TimeoutSeconds }
        if ($PSBoundParameters.ContainsKey('Body')) { $params.Body = [Text.Encoding]::UTF8.GetBytes($Body); $params.ContentType = 'application/json' }
        $response = Invoke-WebRequest @params
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Content = [string]$response.Content }
    }
    catch {
        $webResponse = $null
        if ($_.Exception.PSObject.Properties.Name -contains 'Response') { $webResponse = $_.Exception.Response }
        if ($null -eq $webResponse) { return [pscustomobject]@{ StatusCode = 0; Content = "connection error: $($_.Exception.Message)" } }
        $content = ''
        try { $reader = New-Object IO.StreamReader($webResponse.GetResponseStream()); $content = $reader.ReadToEnd(); $reader.Dispose() } catch { }
        return [pscustomobject]@{ StatusCode = [int]$webResponse.StatusCode; Content = [string]$content }
    }
}

function Get-T33OrchestratorHeaders { return @{ Authorization = "Bearer $env:ORCHESTRATOR_API_KEY" } }

function Wait-T33HttpOk([string]$Uri, [int]$TimeoutSeconds = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $r = Invoke-T33Request -Method GET -Uri $Uri -TimeoutSeconds 5
        if ($r.StatusCode -eq 200) { return $true }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    return $false
}

# Orchestrator workflow helpers
function ConvertTo-T33InlineReference($Value) {
    $json = $Value | ConvertTo-Json -Depth 30 -Compress
    return @{ protocol = 'inline'; uri = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)); format = 'json' }
}

function Submit-T33Workflow {
    param([hashtable]$Settings, $Blueprint, $DockerInfo, [object[]]$Inputs, [hashtable]$Parameters = @{})
    $body = [ordered]@{ blueprint = $Blueprint; dockerinfo = $DockerInfo; inputs = @($Inputs); services_api_key = $env:SERVICE_API_KEY }
    if ($Parameters.Count -gt 0) { $body.parameters = $Parameters }
    $r = Invoke-T33Request -Method POST -Uri "$($Settings.OrchestratorUrl)/workflows" -Headers (Get-T33OrchestratorHeaders) -Body ($body | ConvertTo-Json -Depth 40 -Compress)
    $id = $null
    if ($r.StatusCode -in @(200,201,202)) { try { $id = ($r.Content | ConvertFrom-Json).workflow_id } catch { $id = $null } }
    return [pscustomobject]@{ StatusCode = $r.StatusCode; Content = $r.Content; WorkflowId = $id }
}

function Get-T33Workflow([hashtable]$Settings, [string]$WorkflowId) {
    $base = "$($Settings.OrchestratorUrl)/workflows/$WorkflowId"
    $w = Invoke-T33Request -Method GET -Uri $base -Headers (Get-T33OrchestratorHeaders)
    $t = Invoke-T33Request -Method GET -Uri "$base/tasks" -Headers (Get-T33OrchestratorHeaders)
    $status = 'unreachable'
    if ($w.StatusCode -eq 404) { $status = 'missing' }
    elseif ($w.StatusCode -eq 200) { try { $status = [string]($w.Content | ConvertFrom-Json).status } catch { $status = 'unparseable' } }
    $tasks = $null
    if ($t.StatusCode -eq 200) { try { $tasks = $t.Content | ConvertFrom-Json } catch { $tasks = $null } }
    return [pscustomobject]@{ Status = $status; HttpStatus = $w.StatusCode; WorkflowText = $w.Content; TasksText = $t.Content; Tasks = $tasks }
}

function Wait-T33Workflow([hashtable]$Settings, [string]$WorkflowId, [int]$TimeoutSeconds = 600, [int]$PollSeconds = 2) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    do {
        Start-Sleep -Seconds $PollSeconds
        $last = Get-T33Workflow $Settings $WorkflowId
        Write-Host "$((Get-Date).ToString('o')) workflow=$WorkflowId status=$($last.Status)"
        if ($last.Status -in @('complete','completed','failed','missing')) { return $last }
    } while ((Get-Date) -lt $deadline)
    $last.Status = "timeout ($($last.Status))"
    return $last
}

function Get-T33TaskByContainer($Tasks, [string]$ContainerPrefix) {
    if ($null -eq $Tasks -or -not ($Tasks.PSObject.Properties.Name -contains 'tasks')) { return $null }
    return @($Tasks.tasks | Where-Object { ([string]$_.node_key).StartsWith("${ContainerPrefix}") }) | Select-Object -First 1
}

# Vendor pipeline export written by script 20
function Get-T33VendorExport([hashtable]$Settings) {
    $marker = Join-Path $Settings.VendorWorkspace '.t33-vendor-workspace.json'
    if (-not (Test-Path $marker)) { Stop-T33Blocked 'The vendor workspace is not prepared. Run 20-Prepare-Vendor-Pipeline.ps1 first.' }
    $export = Join-Path $Settings.VendorWorkspace 'export'
    $bp = Join-Path $export 'blueprint.json'; $di = Join-Path $export 'dockerinfo.json'
    if (-not (Test-Path $bp) -or -not (Test-Path $di)) { Stop-T33Blocked 'The vendor onboarding export is missing. Rerun 20-Prepare-Vendor-Pipeline.ps1.' }
    return [pscustomobject]@{ Blueprint = (Get-Content $bp -Raw | ConvertFrom-Json); DockerInfo = (Get-Content $di -Raw | ConvertFrom-Json); Marker = (Get-Content $marker -Raw | ConvertFrom-Json) }
}

# Reads a vendor output file from the vendor data volume.
function Read-T33VendorFile([string]$Uri) {
    $r = Invoke-T33Docker @('exec','t33-vendor-ingest','cat',$Uri) -AllowFailure
    if ($r.ExitCode -ne 0) { return $null }
    return $r.Output
}

# Submits one vendor workflow with a model delay, so restarts can be timed while a task is running.
function Start-T33VendorWorkflow([hashtable]$Settings, $Export, $InputReference, [int]$DelaySeconds = 0, [string]$Marker = '') {
    $params = @{}
    $modelContainer = @($Export.Blueprint.nodes | Where-Object { $_.container_name -like 'vendor_model*' } | Select-Object -First 1)[0].container_name
    $ingestContainer = @($Export.Blueprint.nodes | Where-Object { $_.container_name -like 'vendor_ingest*' } | Select-Object -First 1)[0].container_name
    $params[$modelContainer] = @{ delay_seconds = $DelaySeconds; marker = $Marker }
    $params[$ingestContainer] = @{ marker = $Marker }
    return (Submit-T33Workflow -Settings $Settings -Blueprint $Export.Blueprint -DockerInfo $Export.DockerInfo -Inputs @($InputReference) -Parameters $params)
}
