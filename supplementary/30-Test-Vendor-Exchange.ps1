<#
.SYNOPSIS
Passes a node's workflow outputs to the third-party vendor pipeline and checks the data arrives intact (EXT-02, EXT-04).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package.

EXT-02: every output reference of the completed tasks in -SourceWorkflowId (a workflow the node ran on this
orchestrator, even one that later failed) or the reference in -SourceReferenceFile is sent, unchanged, as the input
of a vendor workflow. The harness reads the same data independently (inline: decoded here; http: fetched from inside
the shared network; file: read through the producing container's mount) and compares SHA-256 and size with what the
vendor recorded. For file references the vendor ingest service is recreated with the node's mount attached
read-only, exactly as a co-located third-party service would be deployed, and restored afterwards.

EXT-04 (-NegativeCases): unsupported protocol, missing file and malformed JSON must fail explicitly with no output.

.NOTES
Run 20-Prepare-Vendor-Pipeline.ps1 and the node's own workflow first. Preserve the evidence folder.
#>
[CmdletBinding(DefaultParameterSetName = 'Workflow')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Workflow')][Parameter(Mandatory, ParameterSetName = 'File')]
    [ValidateSet('Germany','Portugal','Netherlands')][string]$Node,
    [Parameter(Mandatory, ParameterSetName = 'Workflow')][string]$SourceWorkflowId,
    [Parameter(Mandatory, ParameterSetName = 'File')][string]$SourceReferenceFile,
    [Parameter(Mandatory, ParameterSetName = 'Negative')][switch]$NegativeCases,
    [ValidateRange(60, 1800)][int]$TimeoutSeconds = 600
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

function Get-T33Sha256Hex([byte[]]$Bytes) { return -join ([Security.Cryptography.SHA256]::Create().ComputeHash($Bytes) | ForEach-Object { $_.ToString('X2') }) }

# Finds the container mount that holds a file path, among the node's containers.
function Find-T33MountForPath([string[]]$Containers, [string]$Path) {
    $best = $null
    foreach ($c in $Containers) {
        $info = @((Invoke-T33Docker @('inspect',$c)).Output | ConvertFrom-Json)[0]
        foreach ($m in @($info.Mounts)) {
            $dest = ([string]$m.Destination).TrimEnd('/')
            if ($Path.StartsWith("$dest/") -and ($null -eq $best -or $dest.Length -gt $best.Destination.Length)) {
                $source = if ($m.Type -eq 'volume') { [string]$m.Name } else { [string]$m.Source }
                $best = [pscustomobject]@{ Container = $c; Type = [string]$m.Type; Source = $source; Destination = $dest }
            }
        }
    }
    return $best
}

# Reads the referenced data independently of the vendor: returns SHA-256 and size.
function Measure-T33Reference($Ref, $Mount) {
    $protocol = [string]$Ref.protocol
    if ($protocol -eq 'inline') { $b = [Convert]::FromBase64String([string]$Ref.uri); return [pscustomobject]@{ Sha = (Get-T33Sha256Hex $b); Bytes = $b.Length; Note = 'decoded inline' } }
    # No double quotes inside these commands: Windows PowerShell 5.1 does not escape them when it passes
    # an argument to docker.exe, so the sh -c string would arrive split. set -f stops globbing of the
    # unquoted $0; DataReference URIs and container paths contain no spaces.
    $shCommand = $null; $runArgs = @('run','--rm')
    if ($protocol -in @('http','https')) {
        $runArgs += @('--network','ai-effect-services')
        $shCommand = 'set -f; wget -q -O /tmp/x $0 && sha256sum /tmp/x | awk ''{print $1}'' && wc -c < /tmp/x'
    } elseif ($protocol -eq 'file') {
        if ($null -eq $Mount) { return [pscustomobject]@{ Sha = ''; Bytes = -1; Note = 'no node container mount holds this path' } }
        $runArgs += @('-v', "$($Mount.Source):$($Mount.Destination):ro")
        $shCommand = 'set -f; sha256sum $0 | awk ''{print $1}'' && wc -c < $0'
    } else { return [pscustomobject]@{ Sha = ''; Bytes = -1; Note = "protocol $protocol cannot be read by the harness" } }
    $r = Invoke-T33Docker ($runArgs + @($script:T33HelperImage,'sh','-c',$shCommand,[string]$Ref.uri)) -AllowFailure
    $lines = @($r.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($r.ExitCode -ne 0 -or $lines.Count -lt 2) { return [pscustomobject]@{ Sha = ''; Bytes = -1; Note = "harness read failed (exit $($r.ExitCode))" } }
    return [pscustomobject]@{ Sha = $lines[0].ToUpper(); Bytes = [long]$lines[1]; Note = "read via $protocol" }
}

function Get-T33VendorOutputs($Workflow) {
    $result = [ordered]@{ Ingest = $null; Model = $null; ModelUri = '' }
    $ingestTask = Get-T33TaskByContainer $Workflow.Tasks 'vendor_ingest'
    $modelTask = Get-T33TaskByContainer $Workflow.Tasks 'vendor_model'
    if ($ingestTask -and $ingestTask.output_refs) { $t = Read-T33VendorFile ([string]@($ingestTask.output_refs)[0].uri); if ($t) { $result.Ingest = $t | ConvertFrom-Json } }
    if ($modelTask -and $modelTask.output_refs) { $result.ModelUri = [string]@($modelTask.output_refs)[0].uri; $t = Read-T33VendorFile $result.ModelUri; if ($t) { $result.Model = $t | ConvertFrom-Json } }
    return [pscustomobject]$result
}

$label = if ($NegativeCases) { '30-vendor-negative' } else { "30-vendor-exchange-$($Node.ToLower())" }
Invoke-T33SupTest -Settings $s -Label $label -Body {
    param($e)
    $commit = Assert-T33SupPlatform $s
    Require-T33SupKeys
    $export = Get-T33VendorExport $s
    $helper = Ensure-T33HelperImage
    $compose = Join-Path $s.VendorWorkspace 'docker-compose.yml'
    $env:T33_VENDOR_INGEST_PORT = "$([int]$s.VendorPortBase)"; $env:T33_VENDOR_MODEL_PORT = "$([int]$s.VendorPortBase + 1)"

    if ($NegativeCases) {
        $cases = @(
            @{ Name = 'unsupported-protocol'; Ref = @{ protocol = 'ftp'; uri = 'ftp://t33.invalid/none.csv'; format = 'csv' } },
            @{ Name = 'missing-file'; Ref = @{ protocol = 'file'; uri = '/vendor-data/t33-missing/none.json'; format = 'json' } },
            @{ Name = 'malformed-json'; Ref = @{ protocol = 'inline'; uri = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"a":')); format = 'json' } }
        )
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($case in $cases) {
            $submit = Start-T33VendorWorkflow $s $export $case.Ref 0 "t33-neg-$($case.Name)"
            $status = "submission HTTP $($submit.StatusCode)"; $outputs = $null
            if ($submit.WorkflowId) {
                $wf = Wait-T33Workflow $s $submit.WorkflowId $TimeoutSeconds
                Save-T33Text (Join-Path $e "$($case.Name)-tasks.json") $wf.TasksText
                $status = $wf.Status; $outputs = Get-T33VendorOutputs $wf
            }
            $explicit = ($status -eq 'failed') -or ($submit.StatusCode -in @(400,422))
            $noOutput = ($null -eq $outputs) -or ($null -eq $outputs.Model)
            $rows.Add([pscustomobject][ordered]@{ Case = $case.Name; WorkflowId = $submit.WorkflowId; Status = $status; ExplicitFailure = $explicit; NoModelOutput = $noOutput; Ok = ($explicit -and $noOutput) })
            Write-Host "$($case.Name): status=$status ok=$($explicit -and $noOutput)"
        }
        Save-T33Csv (Join-Path $e 'negative-cases.csv') $rows
        $bad = @($rows | Where-Object { -not $_.Ok } | ForEach-Object Case)
        if ($bad.Count -gt 0) { return (New-T33Verdict 'FAIL' "invalid input was not rejected explicitly for: $($bad -join ', ').") }
        return (New-T33Verdict 'PASS' 'unsupported protocol, missing file and malformed JSON all failed explicitly with no vendor output.')
    }

    $n = Get-T33SupNode $s $Node
    $nodeCommit = Assert-T33SupCommit $n.SourceRoot $n.ExpectedCommit
    $nodeContainers = @(Get-T33NodeContainers $n)

    # Collect the node references to exchange.
    $refs = New-Object System.Collections.Generic.List[object]
    if ($SourceReferenceFile) {
        $refs.Add([pscustomobject]@{ Task = 'supplied'; Ref = (Get-Content $SourceReferenceFile -Raw | ConvertFrom-Json) })
    } else {
        $src = Get-T33Workflow $s $SourceWorkflowId
        Save-T33Text (Join-Path $e 'source-workflow.json') $src.WorkflowText
        Save-T33Text (Join-Path $e 'source-tasks.json') $src.TasksText
        if ($src.Status -eq 'missing') { Stop-T33Blocked "workflow $SourceWorkflowId is not known to this orchestrator." }
        foreach ($t in @($src.Tasks.tasks)) {
            if ($t.status -notin @('complete','completed') -or -not $t.output_refs) { continue }
            foreach ($r in @($t.output_refs)) { $refs.Add([pscustomobject]@{ Task = [string]$t.node_key; Ref = $r }) }
        }
    }
    if ($refs.Count -eq 0) { Stop-T33Blocked 'the source workflow has no completed task with an output reference. Run the node workflow, or pass -SourceReferenceFile.' }

    # Attach the node mounts that hold file references to the vendor ingest service (read-only).
    $mounts = @{}
    foreach ($item in $refs) {
        if ([string]$item.Ref.protocol -ne 'file') { continue }
        $m = Find-T33MountForPath $nodeContainers ([string]$item.Ref.uri)
        $item | Add-Member -NotePropertyName Mount -NotePropertyValue $m
        if ($m -and -not $mounts.ContainsKey($m.Destination)) { $mounts[$m.Destination] = $m }
    }
    $override = Join-Path $s.VendorWorkspace '.t33-node-mounts.override.yml'
    if ($mounts.Count -gt 0) {
        $lines = @('services:','  vendor-ingest:','    volumes:')
        $volDecl = @()
        foreach ($m in $mounts.Values) {
            $lines += "      - type: $($m.Type)"
            $lines += "        source: '$($m.Source)'"
            $lines += "        target: '$($m.Destination)'"
            $lines += '        read_only: true'
            if ($m.Type -eq 'volume') { $volDecl += "  '$($m.Source)':"; $volDecl += '    external: true' }
        }
        if ($volDecl.Count -gt 0) { $lines += 'volumes:'; $lines += $volDecl }
        Save-T33Text $override (($lines -join "`n") + "`n")
        Copy-Item $override (Join-Path $e 'vendor-node-mounts.override.yml')
        $up = Invoke-T33Docker @('compose','-f',$compose,'-f',$override,'up','-d','--no-deps','vendor-ingest') -AllowFailure
        if ($up.ExitCode -ne 0) { Stop-T33Blocked 'could not attach the node mounts to the vendor ingest service. See vendor-node-mounts.override.yml.' }
        if (-not (Wait-T33HttpOk "http://127.0.0.1:$($s.VendorPortBase)/health" 120)) { Stop-T33Blocked 'vendor ingest did not return healthy after attaching the node mounts.' }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    try {
        $i = 0
        foreach ($item in $refs) {
            $i++
            $marker = "t33-ext-$($Node.ToLower())-$i"
            $mount = if ($item.PSObject.Properties.Name -contains 'Mount') { $item.Mount } else { $null }
            $expected = Measure-T33Reference $item.Ref $mount
            $refCopy = @{ protocol = [string]$item.Ref.protocol; uri = [string]$item.Ref.uri; format = [string]$item.Ref.format }
            $submit = Start-T33VendorWorkflow $s $export $refCopy 0 $marker
            $status = "submission HTTP $($submit.StatusCode)"; $out = $null
            if ($submit.WorkflowId) {
                $wf = Wait-T33Workflow $s $submit.WorkflowId $TimeoutSeconds
                Save-T33Text (Join-Path $e "exchange-$i-tasks.json") $wf.TasksText
                $status = $wf.Status; $out = Get-T33VendorOutputs $wf
                if ($out.Ingest) { Save-T33Json (Join-Path $e "exchange-$i-ingest-summary.json") ([ordered]@{ source = $out.Ingest.source; profile = $out.Ingest.profile; marker = $out.Ingest.marker }) }
                if ($out.Model) { Save-T33Json (Join-Path $e "exchange-$i-model-output.json") $out.Model }
            }
            $vendorSha = if ($out -and $out.Ingest) { [string]$out.Ingest.source.sha256 } else { '' }
            $vendorBytes = if ($out -and $out.Ingest) { [long]$out.Ingest.source.bytes } else { -1 }
            $records = if ($out -and $out.Ingest) { [long]$out.Ingest.profile.records } else { -1 }
            $own = $out -and $out.Model -and ($out.Model.workflow_id -eq $submit.WorkflowId) -and ($out.Model.marker -eq $marker) -and ($out.Model.ingest_marker -eq $marker) -and $out.ModelUri.StartsWith("/vendor-data/$($submit.WorkflowId)/")
            $result = if (-not $expected.Sha) { 'BLOCKED' }
                      elseif ($status -in @('complete','completed') -and $vendorSha -eq $expected.Sha -and $vendorBytes -eq $expected.Bytes -and $records -gt 0 -and $own) { 'PASS' }
                      else { 'FAIL' }
            $rows.Add([pscustomobject][ordered]@{
                Index = $i; SourceTask = $item.Task; Protocol = $refCopy.protocol; Format = $refCopy.format; Uri = $(if ($refCopy.protocol -eq 'inline') { '(inline)' } else { $refCopy.uri })
                HarnessSha256 = $expected.Sha; HarnessBytes = $expected.Bytes; HarnessNote = $expected.Note
                VendorWorkflowId = $submit.WorkflowId; VendorStatus = $status; VendorSha256 = $vendorSha; VendorBytes = $vendorBytes; Records = $records
                OwnModelOutput = [bool]$own; Result = $result
            })
            Write-Host "[$i] $($item.Task) $($refCopy.protocol): $result (vendor=$status, records=$records)"
        }
    }
    finally {
        if ($mounts.Count -gt 0) {
            Write-Host 'Restoring the vendor ingest service without node mounts.'
            Invoke-T33Docker @('compose','-f',$compose,'up','-d','--no-deps','--force-recreate','vendor-ingest') -AllowFailure | Out-Null
            Remove-Item -LiteralPath $override -Force -ErrorAction SilentlyContinue
        }
    }

    Save-T33Csv (Join-Path $e 'exchange-results.csv') $rows
    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{ node = $Node; node_commit = $nodeCommit; platform_commit = $commit; helper_image = $helper; source_workflow = $SourceWorkflowId; references = $rows.Count; results = @($rows | Group-Object Result | ForEach-Object { "$($_.Name)=$($_.Count)" }) })
    $failed = @($rows | Where-Object Result -eq 'FAIL'); $blocked = @($rows | Where-Object Result -eq 'BLOCKED'); $passed = @($rows | Where-Object Result -eq 'PASS')
    if ($failed.Count -gt 0) { return (New-T33Verdict 'FAIL' "$($failed.Count) of $($rows.Count) node outputs did not reach the vendor intact or produced no own output. See exchange-results.csv.") }
    if ($passed.Count -eq 0) { Stop-T33Blocked "none of the $($rows.Count) node outputs could be read independently by the harness. See exchange-results.csv." }
    $note = if ($blocked.Count -gt 0) { " $($blocked.Count) reference(s) could not be checked independently and are recorded as BLOCKED." } else { '' }
    return (New-T33Verdict 'PASS' "$($passed.Count) $Node output reference(s) reached the third-party vendor with identical SHA-256 and size, and each produced its own model output.$note")
}
