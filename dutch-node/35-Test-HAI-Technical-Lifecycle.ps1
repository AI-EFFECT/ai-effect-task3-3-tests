<#
.SYNOPSIS
Exercises the technical HAI trace, survey, completion, artifact and slot-release lifecycle.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '35-hai-technical-lifecycle'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
try {
    $key = Get-HAIServiceKey
    $session = Start-HAITestSession -ServiceKey $key -Label 'lifecycle' -TimeoutSeconds 300
    if ($session.Response.status -ne 'pending' -or $null -eq $session.Links) { throw 'The lifecycle session did not start.' }
    $token = ([uri]$session.Links.gui_url).Query.TrimStart('?').Split('&') | Where-Object { $_ -like 't=*' } | Select-Object -First 1
    if (-not $token) { throw 'The signed GUI URL does not contain a session token.' }
    $token = $token.Substring(2)
    # The public proxy forwards these to /collect/session-trace and
    # /collect/survey-outcome.  The session token belongs in the JSON body;
    # it authorises producers that cannot hold the service API key.
    $traceBody = @{ wp3_session_id = $session.TaskId; session_token = $token; event = 'technical-test'; timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress
    $surveyBody = @{ wp3_session_id = $session.TaskId; session_token = $token; answer = 'technical-test'; submitted_at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress
    $traceCode = (Invoke-WebRequest -UseBasicParsing -Method Post -ContentType 'application/json' -Body $traceBody -Uri 'http://127.0.0.1:8443/wp3/collect/session-trace').StatusCode
    $surveyCode = (Invoke-WebRequest -UseBasicParsing -Method Post -ContentType 'application/json' -Body $surveyBody -Uri 'http://127.0.0.1:8443/wp3/collect/survey-outcome').StatusCode
    $final = Get-HAIStatus -ServiceKey $key -TaskId $session.TaskId
    $outputText = @(docker exec hai-testing-service curl -sS -H "Authorization: Bearer $key" "http://localhost:8080/control/output/$($session.TaskId)") -join "`n"
    $output = $outputText | ConvertFrom-Json
    Save-Json $session.Response (Join-Path $evidence 'session-response.json')
    Save-Json $final (Join-Path $evidence 'final-status.json')
    Save-Json $output (Join-Path $evidence 'output-reference.json')
    if ($output.output.protocol -ne 'http' -or [string]::IsNullOrWhiteSpace($output.output.uri)) { throw 'Completed session did not publish an HTTP output reference.' }
    # Retrieve locally from the authenticated service endpoint.  This avoids
    # relying on whether the public hostname resolves from inside Docker.
    $artifactText = @(docker exec hai-testing-service curl -sS -H "Authorization: Bearer $key" "http://localhost:8080/control/data/$($session.TaskId)") -join "`n"
    [IO.File]::WriteAllText((Join-Path $evidence 'human-ai-session-result.json'), $artifactText, [Text.UTF8Encoding]::new($false))
    $artifact = $artifactText | ConvertFrom-Json
    $slots = Get-HAISlots
    [PSCustomObject]@{
        TaskId = $session.TaskId
        TracePostHttpStatus = $traceCode
        SurveyPostHttpStatus = $surveyCode
        FinalSessionStatus = $final.status
        FinalProgress = $final.progress
        OutputProtocol = $output.output.protocol
        OutputFormat = $output.output.format
        ArtifactSessionIdMatches = ($artifact.session_id -eq $session.TaskId)
        ArtifactContainsTrace = ($null -ne $artifact.kpis)
        ArtifactContainsSurvey = ($null -ne $artifact.survey_outcomes)
        Slot1FreeAfterCompletion = ($slots.Slot1 -ne $session.TaskId)
        Slot2FreeAfterCompletion = ($slots.Slot2 -ne $session.TaskId)
    } | Format-List
    if ($final.status -ne 'complete' -or $final.progress -ne 100) { throw 'Technical lifecycle did not complete.' }
    Write-Host 'RESULT: PASS - technical lifecycle fixture recorded. This is not evidence of a completed human-operator study or KPI quality.'
}
finally { try { Stop-Transcript } catch {} }
