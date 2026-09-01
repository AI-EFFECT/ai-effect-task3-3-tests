[CmdletBinding()]
param(
    [switch]$ForceRebuild
)

. (Join-Path $PSScriptRoot '_Support.ps1')

$settings = Read-Settings
Assert-Baseline $settings

$evidence = New-EvidenceFolder $settings '29-hai-simulator-image'
Start-Transcript (Join-Path $evidence 'run.txt') -Force

try {
    $image = if ([string]::IsNullOrWhiteSpace($env:HAI_SIMULATOR_IMAGE)) {
        'powergrid-simulator-app:latest'
    }
    else {
        $env:HAI_SIMULATOR_IMAGE
    }

    $compose = Join-Path $settings.RepositoryRoot (
        'use-cases\dutch-node-hai-testing\services\human_ai_interaction_testing\' +
        'InteractiveAI\usecases_examples\PowerGrid\docker-compose.yml'
    )

    if (-not (Test-Path -LiteralPath $compose)) {
        throw "PowerGrid simulator Compose file is missing: $compose"
    }

    docker image inspect $image *> $null
    $imageExists = ($LASTEXITCODE -eq 0)

    if ($imageExists -and -not $ForceRebuild) {
        $imageId = (docker image inspect $image --format '{{.Id}}').Trim()
        Write-Host "Simulator image is already available: $image"
        Write-Host "Image ID: $imageId"
        Write-Host 'RESULT: PASS — existing local PowerGrid simulator image verified; no rebuild was required.'
        return
    }

    if ($imageExists) {
        Write-Host "Rebuilding local PowerGrid simulator image: $image"
    }
    else {
        Write-Host "Building required local PowerGrid simulator image: $image"
    }

    docker compose -f $compose build app
    if ($LASTEXITCODE -ne 0) {
        throw 'PowerGrid simulator image build failed. Preserve this transcript and resolve the build failure before running script 30.'
    }

    docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Build completed but required image was not found: $image"
    }

    $imageId = (docker image inspect $image --format '{{.Id}}').Trim()
    Write-Host "Simulator image is ready: $image"
    Write-Host "Image ID: $imageId"
    Write-Host 'RESULT: PASS — local PowerGrid simulator image is ready for HAI startup.'
}
finally {
    try { Stop-Transcript } catch {}
}
