[CmdletBinding()]
param([switch]$AttemptStart)

. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-Settings
Assert-Baseline $s
$e = New-EvidenceFolder $s '60-villas-closure-gate'
Start-EvidenceTranscript $e
$gateStage = 'initialisation'

function Set-GateStage {
    param([string]$Name)
    $script:gateStage = $Name
    [pscustomobject]@{Stage=$Name;RecordedAt=(Get-Date).ToString('o')} |
        ConvertTo-Json | Set-Content -Path (Join-Path $e 'current-stage.json') -Encoding utf8
    Write-Host "GATE STAGE: $Name"
}

function ConvertTo-T33TrimmedString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
    }
    return ''
}

try {
    Set-GateStage 'resolve-compose-images'
    $compose = Get-GermanyCompose $s
    $configuredImages = @(& docker compose -f $compose config --images 2>&1)
    $configuredImages | Set-Content -Path (Join-Path $e 'configured-images.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Germany Compose image configuration could not be resolved.' }

    Set-GateStage 'select-villas-image'
    # Resolve the image from the named Compose service. Do not use the optional
    # VillasImage setting as the authority: an earlier harness revision could
    # mistake the `germany-node-villas-chronics` adapter image for VILLASnode.
    # Keep the full Compose JSON in memory because it can contain test secrets.
    $composeJsonLines = @(& docker compose -f $compose config --format json 2>$null)
    if ($LASTEXITCODE -ne 0 -or $composeJsonLines.Count -eq 0) { throw 'Germany Compose JSON configuration could not be resolved.' }
    $composeModel = (($composeJsonLines -join "`n") | ConvertFrom-Json)
    $serviceProperty = $composeModel.services.PSObject.Properties[$s.VillasServiceName]
    if ($null -eq $serviceProperty) { throw "Compose service was not found: $($s.VillasServiceName)" }
    $candidate = [string]$serviceProperty.Value.image
    $settingsCandidate = if ($s.Keys -contains 'VillasImage') { [string]$s['VillasImage'] } else { '' }
    [pscustomobject][ordered]@{
        Service=$s.VillasServiceName
        ComposeImage=$candidate
        OptionalSettingsImage=$settingsCandidate
        SettingsMatchesCompose=([string]::IsNullOrWhiteSpace($settingsCandidate) -or $settingsCandidate -eq $candidate)
    } | ConvertTo-Json | Set-Content -Path (Join-Path $e 'selected-villas-image.json') -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        [pscustomobject]@{Status='BLOCKED';Reason='No VILLAS image reference is configured.';CheckedAt=(Get-Date).ToString('o')} |
            ConvertTo-Json | Set-Content -Path (Join-Path $e 'gate-result.json') -Encoding utf8
        Write-Host 'RESULT: BLOCKED - no VILLAS image reference is configured. Do not substitute another runtime.'
        return
    }

    Set-GateStage 'inspect-local-image'
    # `docker image inspect` writes the expected missing-image condition to
    # stderr. The shared support file treats native stderr as terminating, so
    # use the non-erroring image-list filter as the availability probe.
    $localImageRows = @(& docker image ls --filter "reference=$candidate" --no-trunc --digests --format "{{.ID}}`t{{.Repository}}`t{{.Tag}}`t{{.Digest}}")
    $localImageRows | Set-Content -Path (Join-Path $e 'local-image-candidates.tsv') -Encoding utf8
    $imageId = ConvertTo-T33TrimmedString @($localImageRows | ForEach-Object { ($_ -split "`t")[0] } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($imageId)) {
        [pscustomobject]@{Status='BLOCKED';Image=$candidate;Reason='The configured VILLAS image is not available locally.';CheckedAt=(Get-Date).ToString('o')} |
            ConvertTo-Json | Set-Content -Path (Join-Path $e 'gate-result.json') -Encoding utf8
        Write-Host "RESULT: BLOCKED - configured VILLAS image is unavailable locally: $candidate. No pull or substitution was attempted."
        return
    }

    Set-GateStage 'resolve-immutable-image-identity'
    & docker image inspect $imageId | Set-Content -Path (Join-Path $e 'image-inspect.json') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "The locally listed VILLAS image disappeared before inspection: $imageId" }
    $repoDigestsJson = ConvertTo-T33TrimmedString @(& docker image inspect $imageId --format '{{json .RepoDigests}}')
    $repoDigests = if ([string]::IsNullOrWhiteSpace($repoDigestsJson)) { @() } else { @($repoDigestsJson | ConvertFrom-Json) }
    if ($repoDigests.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$repoDigests[0])) {
        [pscustomobject]@{Status='BLOCKED';Image=$candidate;ImageId=$imageId;Reason='Image has no immutable repository digest.';CheckedAt=(Get-Date).ToString('o')} |
            ConvertTo-Json | Set-Content -Path (Join-Path $e 'gate-result.json') -Encoding utf8
        Write-Host 'RESULT: BLOCKED - a local image exists, but it has no immutable repository digest. It cannot establish the official baseline.'
        return
    }

    if ($AttemptStart) {
        Set-GateStage 'attempt-owner-configured-start'
        Require-Keys $s
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '01-Start-Core-And-Germany-Services.ps1')
    }

    Set-GateStage 'resolve-running-container'
    $containerId = ConvertTo-T33TrimmedString @(& docker compose -f $compose ps -q $s.VillasServiceName 2>$null)
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        [pscustomobject]@{Status='READY_NOT_RUNNING';Image=$candidate;ImageId=$imageId;RepoDigests=$repoDigests;Reason='Immutable image recorded, but VILLAS service is not running.';CheckedAt=(Get-Date).ToString('o')} |
            ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $e 'gate-result.json') -Encoding utf8
        Write-Host 'RESULT: READY NOT RUNNING - immutable image evidence exists, but the VILLAS service is not running. No E2E claim can be made.'
        return
    }

    Set-GateStage 'inspect-running-container'
    & docker inspect $containerId | Set-Content -Path (Join-Path $e 'villas-container-inspect.json') -Encoding utf8
    & docker stats --no-stream $containerId | Set-Content -Path (Join-Path $e 'villas-resource-snapshot.txt') -Encoding utf8
    & docker port $containerId | Set-Content -Path (Join-Path $e 'villas-published-ports.txt') -Encoding utf8
    $privileged = ConvertTo-T33TrimmedString @(& docker inspect $containerId --format '{{.HostConfig.Privileged}}' 2>&1)
    $user = ConvertTo-T33TrimmedString @(& docker inspect $containerId --format '{{.Config.User}}' 2>&1)
    $runningImage = ConvertTo-T33TrimmedString @(& docker inspect $containerId --format '{{.Image}}' 2>&1)
    $matches = ($runningImage -eq $imageId)
    $result = [pscustomobject][ordered]@{
        Status=if($matches){'READY'}else{'BLOCKED'}
        ConfiguredImage=$candidate;ImageId=$imageId;RepoDigests=$repoDigests
        ContainerId=$containerId;RunningImageId=$runningImage;RunningImageMatches=$matches
        Privileged=$privileged;ConfiguredUser=$user;CheckedAt=(Get-Date).ToString('o')
        Limitation='This gate does not constitute end-to-end workflow or output-quality sign-off.'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $e 'gate-result.json') -Encoding utf8

    if ($matches) {
        Write-Host 'RESULT: READY - the running VILLAS container matches an immutable local image. Preserve this evidence and run only an owner-approved Germany regression set.'
    }
    else {
        Write-Host 'RESULT: BLOCKED - the running container does not match the inspected immutable VILLAS image.'
    }
}
catch {
    $failure = [pscustomobject][ordered]@{
        Status='HARNESS_ERROR';Stage=$gateStage;Message=$_.Exception.Message
        ScriptName=[string]$_.InvocationInfo.ScriptName
        ScriptLineNumber=$_.InvocationInfo.ScriptLineNumber
        Line=[string]$_.InvocationInfo.Line
        StackTrace=[string]$_.ScriptStackTrace
        RecordedAt=(Get-Date).ToString('o')
    }
    $failure | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $e 'gate-error.json') -Encoding utf8
    Write-Host "RESULT: HARNESS ERROR - stage=$gateStage; line=$($_.InvocationInfo.ScriptLineNumber); $($_.Exception.Message)"
    throw
}
finally { Stop-EvidenceTranscript }
