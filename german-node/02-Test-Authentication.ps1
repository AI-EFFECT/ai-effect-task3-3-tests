<#
.SYNOPSIS
Checks orchestrator authentication for the German test context.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Require-Keys $s;Assert-Baseline $s;$e=New-EvidenceFolder $s '02-authentication';Start-EvidenceTranscript $e
try {$u="$($s.OrchestratorUrl)/workflows/does-not-exist";$missing=(Invoke-T33WebRequest -Uri $u).StatusCode;$bad=(Invoke-T33WebRequest -Uri $u -Headers @{Authorization='Bearer invalid'}).StatusCode;$valid=(Invoke-T33WebRequest -Uri $u -Headers (Get-OrchestratorHeaders $s)).StatusCode;[pscustomobject]@{MissingToken=$missing;InvalidToken=$bad;ValidToken=$valid}|Format-List;if($missing -ne 401 -or $bad -ne 401 -or $valid -eq 401){throw 'Authentication sequence did not show missing/invalid rejection and valid-token access.'};Write-Host 'RESULT: PASS - valid token reached the application.'} finally {Stop-EvidenceTranscript}
