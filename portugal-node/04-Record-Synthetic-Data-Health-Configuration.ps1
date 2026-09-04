. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Assert-T33PortugalBaseline $s
$e = New-T33PortugalEvidence $s '04-synthetic-data-health-configuration'
Start-T33PortugalTranscript $e

try {
    & docker inspect tef-synthetic-data *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'tef-synthetic-data is not running. Run 01-Start-Core-And-Portugal-Services.ps1 first.'
    }

    $state = & docker inspect tef-synthetic-data --format '{{json .State}}'
    $effectiveHealthCheck = & docker inspect tef-synthetic-data --format '{{json .Config.Healthcheck}}'
    $suppliedCompose = Join-Path $s.IntegratedOverlayRoot 'docker-compose.yml'
    $suppliedHealthCheck = @(
        Get-Content $suppliedCompose |
        Where-Object { $_ -match 'curl.*localhost:600/' }
    ) -join "`n"

    $hostChecks = foreach ($path in @('/', '/health', '/docs', '/openapi.json', '/models')) {
        $response = Invoke-T33PortugalWebRequest -Method GET -Uri "http://127.0.0.1:8003$path"
        [PSCustomObject]@{ Path = $path; StatusCode = $response.StatusCode }
    }

    [PSCustomObject]@{
        ContainerState = ($state | ConvertFrom-Json).Status
        DockerHealth = (($state | ConvertFrom-Json).Health.Status)
        SuppliedComposeHealthCheck = $suppliedHealthCheck
        EffectiveTestHealthCheck = $effectiveHealthCheck
    } | Format-List

    $hostChecks | Format-Table -AutoSize

    $rootCheck = @($hostChecks | Where-Object { $_.Path -eq '/' })[0].StatusCode
    $openApiCheck = @($hostChecks | Where-Object { $_.Path -eq '/openapi.json' })[0].StatusCode

    if ($rootCheck -eq 404 -and $openApiCheck -eq 200 -and $suppliedHealthCheck) {
        Write-Host 'RESULT: DEFECT CONFIRMED - supplied Compose health check calls the undefined root path; Synthetic Data is responsive at /openapi.json.'
    }
    else {
        Write-Host 'RESULT: RECORDED - inspect the state, supplied health check and endpoint responses above.'
    }
}
finally {
    Stop-T33PortugalTranscript
}
