<#
.SYNOPSIS
Checks that the orchestrator rejects missing and invalid tokens and accepts the configured test token.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings; Require-Keys $settings -OnlyOrchestrator; Assert-Baseline $settings
$evidence=New-EvidenceFolder $settings '01-authentication'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
try {
    Wait-Container 'orchestrator-api'
    $url="$($settings.OrchestratorUrl)/workflows/not-a-real-id";$missing=$null;$invalid=$null;$valid=$null
    try { Invoke-WebRequest -Uri $url -ErrorAction Stop|Out-Null } catch { $missing=$_.Exception.Response.StatusCode.value__ }
    try { Invoke-WebRequest -Uri $url -Headers @{Authorization='Bearer deliberately-wrong'} -ErrorAction Stop|Out-Null } catch { $invalid=$_.Exception.Response.StatusCode.value__ }
    try { $valid=(Invoke-WebRequest -Uri $url -Headers (Get-OrchestratorHeaders $settings) -ErrorAction Stop).StatusCode } catch { $valid=$_.Exception.Response.StatusCode.value__ }
    [pscustomobject]@{MissingToken=$missing;InvalidToken=$invalid;ValidToken=$valid}|Format-List
    if($missing -ne 401 -or $invalid -ne 401 -or $null -eq $valid -or $valid -eq 401){throw 'Authentication acceptance criteria failed.'}
    Write-Host 'RESULT: PASS — valid token reached the application.'
} finally { try { Stop-Transcript } catch {} }
