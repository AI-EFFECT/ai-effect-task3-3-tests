. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Assert-T33PortugalBaseline $s;$e=New-T33PortugalEvidence $s '99-closeout';Start-T33PortugalTranscript $e
try {
    & git -C $s.RepositoryRoot rev-parse HEAD|Set-Content (Join-Path $e 'commit.txt');& git -C $s.RepositoryRoot status --short|Set-Content (Join-Path $e 'git-status.txt')
    $fixture=Join-Path $s.TefServicesRoot 'synthetic_data_generation\real_data.csv';Get-FileHash -Algorithm SHA256 $fixture|Format-List|Out-File (Join-Path $e 'tef-fixture-sha256.txt')
    foreach($workspace in @($s.IntegratedWorkspace,$s.SidecarWorkspace)){if(Test-Path (Join-Path $workspace '.t33-portugal-workspace.json')){Copy-Item (Join-Path $workspace '.t33-portugal-workspace.json') (Join-Path $e ((Split-Path $workspace -Leaf)+'-manifest.json')) -Force}}
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'|Set-Content (Join-Path $e 'docker-ps.txt')
    Write-Host 'RESULT: PASS - close-out saved the frozen baseline, external TEF fixture hash, workspace manifests and runtime inventory.'
} finally {Stop-T33PortugalTranscript}
