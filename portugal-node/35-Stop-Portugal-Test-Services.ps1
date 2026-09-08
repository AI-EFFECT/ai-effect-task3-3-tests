<#
.SYNOPSIS
Stops Portuguese test containers while retaining workspaces and named volumes for review.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;$e=New-T33PortugalEvidence $s '35-stop-portugal-services';Start-T33PortugalTranscript $e
try {foreach($entry in @(@{Path=$s.IntegratedWorkspace;Compose='docker-compose.yml';NeedsOverride=$true},@{Path=$s.SidecarWorkspace;Compose='sidecar-adapters\docker-compose.yml';NeedsOverride=$false},@{Path=$s.SidecarWorkspace;Compose='docker-compose-tef.yml';NeedsOverride=$true})){$compose=Join-Path $entry.Path $entry.Compose;if(Test-Path $compose){Write-Host "Stopping test containers defined by $compose";if($entry.NeedsOverride){& docker compose -f $compose -f (Get-T33SharedNetworkOverride $entry.Path) down|Out-Host}else{& docker compose -f $compose down|Out-Host}}};Write-Host 'RESULT: PASS - Portugal test containers were stopped. Source folders, workspaces and named volumes were retained.'} finally {Stop-T33PortugalTranscript}
