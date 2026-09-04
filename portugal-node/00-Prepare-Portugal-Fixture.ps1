param([switch]$Reset)
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Assert-T33PortugalBaseline $s;$e=New-T33PortugalEvidence $s '00-prepare-integrated';Start-T33PortugalTranscript $e
try {
    Write-Host '=== Frozen Portugal integration baseline ===';& git -C $s.RepositoryRoot rev-parse HEAD;& git -C $s.RepositoryRoot status --short
    $workspace=New-T33Workspace -Settings $s -Variant Integrated -Reset:$Reset;$fixture=Join-Path $workspace 'data\real_data.csv';$sourceFixture=Join-Path $s.TefServicesRoot 'synthetic_data_generation\real_data.csv'
    [PSCustomObject]@{Workspace=$workspace;TefServicesRoot=$s.TefServicesRoot;OverlayRoot=$s.IntegratedOverlayRoot;FixtureSource=$sourceFixture;FixtureRows=(@(Get-Content $fixture).Count-1);FixtureSHA256=(Get-FileHash -Algorithm SHA256 $fixture).Hash;WorkspaceMarker=Test-Path (Join-Path $workspace '.t33-portugal-workspace.json');SharedNetworkOverride=Test-Path (Join-Path $workspace '.t33-shared-network.override.yml');TestVolumes=(Get-T33TestVolumeNames Integrated) -join ', '}|Format-List
    Copy-Item $fixture (Join-Path $e 'real_data.csv') -Force;Get-Content (Join-Path $workspace '.t33-portugal-workspace.json')|Set-Content (Join-Path $e 'workspace-manifest.json')
    Write-Host 'RESULT: PASS - integrated workspace was built from the supplied TEF source and the AI-EFFECT overlay.'
} finally {Stop-T33PortugalTranscript}
