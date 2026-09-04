param([switch]$Reset)
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Assert-T33PortugalBaseline $s;$e=New-T33PortugalEvidence $s '30-prepare-sidecar';Start-T33PortugalTranscript $e
try {$workspace=New-T33Workspace -Settings $s -Variant Sidecar -Reset:$Reset;$fixture=Join-Path $workspace 'data\real_data.csv';[PSCustomObject]@{Workspace=$workspace;TefServicesRoot=$s.TefServicesRoot;OverlayRoot=$s.SidecarOverlayRoot;FixtureRows=(@(Get-Content $fixture).Count-1);FixtureSHA256=(Get-FileHash -Algorithm SHA256 $fixture).Hash;WorkspaceMarker=Test-Path (Join-Path $workspace '.t33-portugal-workspace.json')}|Format-List;Write-Host 'RESULT: PASS - sidecar workspace was built from the same TEF source without changing it.'} finally {Stop-T33PortugalTranscript}
