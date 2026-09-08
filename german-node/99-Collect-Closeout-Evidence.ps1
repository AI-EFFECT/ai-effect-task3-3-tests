<#
.SYNOPSIS
Collects source, Compose, image and runtime inventories for German-node close-out.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Assert-Baseline $s;$e=New-EvidenceFolder $s '99-closeout';Start-EvidenceTranscript $e
try {Push-Location $s.RepositoryRoot;git rev-parse HEAD|Set-Content (Join-Path $e 'commit.txt');git status --short|Set-Content (Join-Path $e 'git-status.txt');git submodule status --recursive|Set-Content (Join-Path $e 'submodules.txt');Pop-Location;docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'|Set-Content (Join-Path $e 'docker-ps.txt');Write-Host 'RESULT: PASS - close-out baseline and runtime inventory saved.'} finally {Stop-EvidenceTranscript}
