. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Assert-Baseline $s;$e=New-EvidenceFolder $s '00-preflight';Start-EvidenceTranscript $e
try {
    Write-Host '=== Frozen Germany baseline ===';Push-Location $s.RepositoryRoot;git rev-parse HEAD;git status --short;git submodule status --recursive;Pop-Location
    Write-Host '=== Docker capability ===';docker version;docker compose version
    $compose=Get-GermanyCompose $s;Write-Host '=== Germany Compose services ===';docker compose -f $compose config --services;docker compose -f $compose ps
    $villasId=@(docker compose -f $compose ps -q $s.VillasServiceName|Where-Object{$_}|Select-Object -First 1)
    if($villasId){$v=(docker inspect $villasId[0] --format '{{.Name}}').Trim().TrimStart('/');$image=(docker inspect $villasId[0] --format '{{.Config.Image}}').Trim();[pscustomobject]@{VillasContainer=$v;RuntimeState='running';ConfiguredImage=$image}|Format-List}
    else{docker compose -f $compose config --images|Set-Content (Join-Path $e 'configured-compose-images.txt');[pscustomobject]@{VillasContainer='not running';RuntimeState='stopped';ConfiguredImage='See configured-compose-images.txt'}|Format-List;Write-Host 'CHECK: Germany services are stopped. Run script 01 next; this is not a preflight failure.'}
    Write-Host 'RESULT: PASS - baseline and dependency state recorded.'
} finally {Stop-EvidenceTranscript}
