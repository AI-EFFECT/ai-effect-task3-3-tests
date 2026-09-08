<#
.SYNOPSIS
Checks that the orchestrator rejects missing and invalid tokens and accepts the configured test token.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Require-T33PortugalKeys;$e=New-T33PortugalEvidence $s '02-authentication';Start-T33PortugalTranscript $e
try {
    Wait-T33Container (Get-T33OrchestratorContainer)
    $uri="$($s.OrchestratorUrl)/workflows/not-a-real-workflow";$missing=Invoke-T33PortugalWebRequest -Method Get -Uri $uri;$invalid=Invoke-T33PortugalWebRequest -Method Get -Uri $uri -Headers (Get-T33BearerHeaders 'not-a-valid-key');$valid=Invoke-T33PortugalWebRequest -Method Get -Uri $uri -Headers (Get-T33BearerHeaders $env:ORCHESTRATOR_API_KEY)
    [PSCustomObject]@{MissingToken=$missing.StatusCode;InvalidToken=$invalid.StatusCode;ValidToken=$valid.StatusCode}|Format-List
    if($missing.StatusCode -eq 401 -and $invalid.StatusCode -eq 401 -and $valid.StatusCode -ne 401){Write-Host 'RESULT: PASS - valid token reached the application.'}else{throw 'Authentication behaviour differs from the expected access-control sequence.'}
} finally {Stop-T33PortugalTranscript}
