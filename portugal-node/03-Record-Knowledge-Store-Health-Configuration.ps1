<#
.SYNOPSIS
Compares the supplied Knowledge Store health check with the effective test check and live endpoints.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Assert-T33PortugalBaseline $s
$e = New-T33PortugalEvidence $s '03-knowledge-store-health-configuration'
Start-T33PortugalTranscript $e

try {
    & docker inspect tef-knowledge-store *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'tef-knowledge-store is not running. Run 01-Start-Core-And-Portugal-Services.ps1 first.'
    }

    $state = & docker inspect tef-knowledge-store --format '{{json .State}}'
    $effectiveHealthCheck = & docker inspect tef-knowledge-store --format '{{json .Config.Healthcheck}}'
    $suppliedCompose = Join-Path $s.IntegratedOverlayRoot 'docker-compose.yml'
    $suppliedHealthCheck = @(
        Get-Content $suppliedCompose |
        Where-Object { $_ -match 'curl.*localhost:8000/' }
    ) -join "`n"
    $curlPath = (& docker exec tef-knowledge-store sh -c 'command -v curl || true') -join ''

    $hostChecks = foreach ($path in @('/', '/health', '/docs', '/openapi.json')) {
        $response = Invoke-T33PortugalWebRequest -Method GET -Uri "http://127.0.0.1:8002$path"
        [PSCustomObject]@{ Path = $path; StatusCode = $response.StatusCode }
    }

    [PSCustomObject]@{
        ContainerState = ($state | ConvertFrom-Json).Status
        DockerHealth = (($state | ConvertFrom-Json).Health.Status)
        SuppliedComposeHealthCheck = $suppliedHealthCheck
        EffectiveTestHealthCheck = $effectiveHealthCheck
        CurlAvailableInImage = -not [string]::IsNullOrWhiteSpace($curlPath)
    } | Format-List

    $hostChecks | Format-Table -AutoSize

    $rootCheck = @($hostChecks | Where-Object { $_.Path -eq '/' })[0].StatusCode
    $healthEndpoint = @($hostChecks | Where-Object { $_.Path -eq '/health' })[0].StatusCode

    if ($rootCheck -eq 404 -and $healthEndpoint -eq 200 -and [string]::IsNullOrWhiteSpace($curlPath) -and $suppliedHealthCheck) {
        Write-Host 'RESULT: DEFECT CONFIRMED - supplied Compose health check calls curl on /; this image has no curl and the service health endpoint is /health.'
    }
    else {
        Write-Host 'RESULT: RECORDED - inspect the state, configured health check and endpoint responses above.'
    }
}
finally {
    Stop-T33PortugalTranscript
}
