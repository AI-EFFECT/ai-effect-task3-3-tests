. (Join-Path $PSScriptRoot '_Support.ps1')

$s = Read-T33PortugalSettings
Require-T33PortugalKeys
Assert-T33PortugalBaseline $s
$workspace = Assert-T33Workspace $s Sidecar
$e = New-T33PortugalEvidence $s '31-sidecar-compatibility'
Start-T33PortugalTranscript $e

try {
    Ensure-T33SharedNetwork
    $integratedMarker = Join-Path $s.IntegratedWorkspace '.t33-portugal-workspace.json'
    if (Test-Path $integratedMarker) {
        Write-Host 'Stopping only the disposable integrated Portugal test containers before using the same ports for the sidecar check.'
        & docker compose -f (Join-Path $s.IntegratedWorkspace 'docker-compose.yml') -f (Get-T33SharedNetworkOverride $s.IntegratedWorkspace) down | Out-Host
    }

    Write-Host '=== Start the supplied TEF services for the legacy-sidecar route ==='
    $compose = Join-Path $workspace 'docker-compose-tef.yml'
    $start = @(& docker compose -f $compose -f (Get-T33SharedNetworkOverride $workspace) up -d --build 2>&1)
    $start | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw 'The supplied TEF services could not be started. Preserve this transcript; do not change the supplied source.' }

    Wait-T33Container 'tef-sc-clickhouse' 180

    # Data Provision has a supplied Docker health check that is not suitable
    # for its gRPC service. Do not treat "healthy" as readiness here. Instead,
    # wait for the service's own startup log before classifying the interface.
    Write-Host 'Waiting for the Data Provision startup record (up to 90 seconds).'
    $startupDeadline = (Get-Date).AddSeconds(90)
    $grpcEvidence = $false
    $logs = @()
    $dataProvisionState = 'not-created'

    do {
        $stateOutput = @(& docker inspect tef-sc-data-provision --format '{{.State.Status}}' 2>$null)
        if ($stateOutput.Count -gt 0) {
            $dataProvisionState = $stateOutput[0].Trim()
        }
        $logs = @(& docker logs tef-sc-data-provision --tail 120 2>&1)
        $grpcEvidence = (($logs -join "`n") -match 'gRPC server.*50051|port 50051')

        if ($grpcEvidence) {
            Write-Host 'Data Provision gRPC startup record observed.'
            break
        }

        if ($dataProvisionState -in @('exited', 'dead')) {
            Write-Host "Data Provision stopped before its startup interface could be recorded: $dataProvisionState"
            break
        }

        Write-Host "Waiting for Data Provision startup record; state=$dataProvisionState"
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $startupDeadline)

    Write-Host "`n=== Record the data-provision interface expected by the supplied sidecar ==="
    $effectiveConfig = @(& docker compose -f $compose -f (Get-T33SharedNetworkOverride $workspace) config 2>&1)
    Save-T33Text (Join-Path $e 'tef-compose-effective.yml') ($effectiveConfig -join "`n")
    $adapterCompose = Join-Path $workspace 'sidecar-adapters\docker-compose.yml'
    $adapterConfig = @(& docker compose -f $adapterCompose config 2>&1)
    Save-T33Text (Join-Path $e 'sidecar-adapters-effective.yml') ($adapterConfig -join "`n")
    $inspect = @(& docker inspect tef-sc-data-provision 2>&1)
    Save-T33Text (Join-Path $e 'data-provision-inspect.json') ($inspect -join "`n")
    $logs = @(& docker logs tef-sc-data-provision --tail 120 2>&1)
    Save-T33Text (Join-Path $e 'data-provision-logs.txt') ($logs -join "`n")

    $isRunning = ((& docker inspect tef-sc-data-provision --format '{{.State.Running}}').Trim() -eq 'true')
    $health = (& docker inspect tef-sc-data-provision --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}').Trim()
    $grpcEvidence = (($logs -join "`n") -match 'gRPC server.*50051|port 50051')
    $http600Expected = (($adapterConfig -join "`n") -match 'DATA_PROVISION_URL=.*:600|http://.*:600')

    [PSCustomObject]@{
        DataProvisionRunning       = $isRunning
        DataProvisionState         = $dataProvisionState
        DockerHealth               = $health
        ServiceLogShowsGrpc50051   = $grpcEvidence
        SuppliedComposeExpectsHttp600 = $http600Expected
        EvidenceFolder             = $e
    } | Format-List

    if ($isRunning -and $grpcEvidence -and $http600Expected) {
        Write-Host 'RESULT: BLOCKED AS SUPPLIED - the legacy Data Provision service is running as gRPC on port 50051, while the supplied sidecar Compose and adapter configuration expect HTTP on port 600. Do not run script 32 until the Portugal owner supplies a compatible adapter or approved deployment configuration.'
    }
    else {
        Write-Host 'RESULT: RECORDED - inspect the saved Compose configuration, container inspection and logs before attempting the sidecar workflow.'
    }
}
finally { Stop-T33PortugalTranscript }
