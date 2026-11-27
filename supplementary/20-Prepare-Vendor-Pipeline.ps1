<#
.SYNOPSIS
Builds the stand-in third-party vendor pipeline from the platform templates and checks that it works (EXT-01).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Creates a marked, disposable vendor workspace, copies the
platform's common library and template handlers from the frozen commit, adds the vendor's own service code, builds
and starts the two services, generates the onboarding export with the platform's generator, checks that the vendor
enforces its service key (a positive control for the SEC-06 probe) and runs one smoke workflow with inline data.

.NOTES
Run after 00-Preflight.ps1. Use -Reset to replace an earlier vendor workspace and its test-owned data volume.
#>
[CmdletBinding()]
param(
    [switch]$Reset,
    [ValidateRange(60, 1800)][int]$TimeoutSeconds = 900
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '20-prepare-vendor' -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $ws = $s.VendorWorkspace
    $marker = Join-Path $ws '.t33-vendor-workspace.json'
    $compose = Join-Path $ws 'docker-compose.yml'

    if (Test-Path $ws) {
        if (-not $Reset) { Stop-T33Blocked "$ws already exists. Inspect it, then rerun with -Reset to replace this test workspace." }
        if (-not (Test-Path $marker)) { Stop-T33Blocked "Refusing to replace $ws because it is not marked as a T3.3 vendor workspace." }
        Write-Host 'Stopping the earlier vendor services and removing the test-owned vendor volume.'
        Invoke-T33Docker @('compose','-f',$compose,'down','--volumes') -AllowFailure | Out-Null
        Remove-Item -LiteralPath $ws -Recurse -Force
    }

    # Assemble the workspace: vendor code from this package, template code from the frozen platform.
    New-Item -ItemType Directory -Force $ws | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'vendor\*') -Destination $ws -Recurse -Force
    $useCases = Join-Path $s.PlatformRoot 'use-cases'
    Copy-Item (Join-Path $useCases 'common') -Destination (Join-Path $ws 'common') -Recurse -Force
    $templateMap = [ordered]@{
        'vendor_ingest' = Join-Path $useCases 'templates\file_based\sequential'
        'vendor_model'  = Join-Path $useCases 'templates\file_based\concurrent'
    }
    $provenance = [ordered]@{}
    foreach ($svc in $templateMap.Keys) {
        foreach ($file in @('handler.py','requirements.txt')) {
            $src = Join-Path $templateMap[$svc] $file
            if (-not (Test-Path $src)) { Stop-T33Blocked "Template file was not found: $src" }
            Copy-Item $src (Join-Path $ws "services\$svc\$file") -Force
            $provenance["$svc/$file"] = [ordered]@{ source = $src; sha256 = (Get-FileHash -Algorithm SHA256 $src).Hash }
        }
    }
    foreach ($f in @('concurrent.py','sequential.py')) { $provenance["common/$f"] = [ordered]@{ sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $useCases "common\$f")).Hash } }
    Save-T33Json $marker ([ordered]@{ created_at = (Get-Date).ToString('o'); platform_commit = $commit; provenance = $provenance })
    Copy-Item $marker (Join-Path $e 'vendor-workspace.json')

    # Start the vendor services on the shared network.
    Invoke-T33Docker @('network','inspect','ai-effect-services') -AllowFailure | ForEach-Object {
        if ($_.ExitCode -ne 0) { Invoke-T33Docker @('network','create','ai-effect-services') | Out-Null }
    }
    $ingestPort = [int]$s.VendorPortBase; $modelPort = $ingestPort + 1
    $env:T33_VENDOR_INGEST_PORT = "$ingestPort"; $env:T33_VENDOR_MODEL_PORT = "$modelPort"
    $up = Invoke-T33Docker @('compose','-f',$compose,'up','-d','--build') -AllowFailure
    Save-T33Text (Join-Path $e 'compose-up.txt') $up.Output
    if ($up.ExitCode -ne 0) { Stop-T33Blocked 'docker compose up failed for the vendor pipeline. See compose-up.txt.' }
    foreach ($port in @($ingestPort, $modelPort)) {
        if (-not (Wait-T33HttpOk "http://127.0.0.1:$port/health" 180)) { Stop-T33Blocked "Vendor service on port $port did not become healthy." }
    }

    # Onboarding export with the platform's own generator.
    Push-Location $ws
    try { $gen = & python (Join-Path $s.PlatformRoot 'scripts\onboarding-export-generator.py') $ws 'export' '--overwrite' 2>&1 | Out-String } finally { Pop-Location }
    Save-T33Text (Join-Path $e 'export-generator.txt') $gen
    $export = Get-T33VendorExport $s
    Copy-Item (Join-Path $ws 'export\blueprint.json') (Join-Path $e 'blueprint.json')
    Copy-Item (Join-Path $ws 'export\dockerinfo.json') (Join-Path $e 'dockerinfo.json')

    # Positive control for SEC-06: the vendor must refuse missing/invalid tokens and accept the valid one.
    $auth = New-Object System.Collections.Generic.List[object]
    foreach ($port in @($ingestPort, $modelPort)) {
        foreach ($case in @(@{ Name = 'missing'; H = @{} }, @{ Name = 'invalid'; H = @{ Authorization = 'Bearer t33-invalid-token' } }, @{ Name = 'valid'; H = @{ Authorization = "Bearer $env:SERVICE_API_KEY" } })) {
            $r = Invoke-T33Request -Method POST -Uri "http://127.0.0.1:$port/control/execute" -Headers $case.H -Body '{}'
            $auth.Add([pscustomobject]@{ Port = $port; Token = $case.Name; Status = $r.StatusCode })
        }
    }
    Save-T33Csv (Join-Path $e 'vendor-auth.csv') $auth
    $authOk = (@($auth | Where-Object { $_.Token -ne 'valid' -and $_.Status -notin @(401,403) }).Count -eq 0) -and (@($auth | Where-Object { $_.Token -eq 'valid' -and $_.Status -ne 422 }).Count -eq 0)

    # Smoke workflow with inline records.
    $records = @(1..24 | ForEach-Object { [ordered]@{ hour = $_; load_kw = [math]::Round(50 + 10 * [math]::Sin($_ / 4.0), 3) } })
    $json = $records | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $expectedSha = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') })
    $ref = @{ protocol = 'inline'; uri = [Convert]::ToBase64String($bytes); format = 'json' }
    $submit = Start-T33VendorWorkflow $s $export $ref 0 't33-smoke'
    Save-T33Text (Join-Path $e 'smoke-submit.json') $submit.Content
    if (-not $submit.WorkflowId) { return (New-T33Verdict 'FAIL' "vendor smoke workflow submission returned HTTP $($submit.StatusCode) without a workflow_id.") }
    $wf = Wait-T33Workflow $s $submit.WorkflowId $TimeoutSeconds
    Save-T33Text (Join-Path $e 'smoke-workflow.json') $wf.WorkflowText
    Save-T33Text (Join-Path $e 'smoke-tasks.json') $wf.TasksText
    $modelTask = Get-T33TaskByContainer $wf.Tasks 'vendor_model'
    $outputUri = if ($modelTask -and $modelTask.output_refs) { [string]@($modelTask.output_refs)[0].uri } else { '' }
    $output = if ($outputUri) { Read-T33VendorFile $outputUri } else { $null }
    if ($output) { Save-T33Text (Join-Path $e 'smoke-model-output.json') $output }
    $doc = if ($output) { $output | ConvertFrom-Json } else { $null }
    $smokeOk = ($wf.Status -in @('complete','completed')) -and $doc -and ($doc.source_sha256 -eq $expectedSha) -and ([int]$doc.records -eq 24) -and ($doc.marker -eq 't33-smoke')

    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{
        platform_commit = $commit; ingest_port = $ingestPort; model_port = $modelPort
        vendor_auth_enforced = $authOk; smoke_workflow = $submit.WorkflowId; smoke_status = $wf.Status
        expected_sha256 = $expectedSha; vendor_sha256 = if ($doc) { $doc.source_sha256 } else { $null }
    })
    if (-not $authOk) { return (New-T33Verdict 'FAIL' 'the vendor services did not enforce the service key as configured; the SEC-06 probe method cannot be trusted. See vendor-auth.csv.') }
    if (-not $smokeOk) { return (New-T33Verdict 'FAIL' "the vendor smoke workflow ended as $($wf.Status) or its output did not match the inline input. See smoke-*.json.") }
    return (New-T33Verdict 'PASS' 'vendor pipeline built from the platform templates, onboarding export generated, service key enforced and smoke workflow output matched its input.')
}
