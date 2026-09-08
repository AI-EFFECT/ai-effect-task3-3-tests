<#
.SYNOPSIS
Verifies safe handling of a missing Portuguese input file without a successful output reference.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s = Read-T33PortugalSettings
Assert-T33PortugalBaseline $s
Assert-T33Workspace $s Integrated | Out-Null
Wait-T33Container 'tef-data-provision'
$e = New-T33PortugalEvidence $s '22-invalid-input'
Start-T33PortugalTranscript $e
try {
    $taskId = 'task_t33_pt_invalid_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $request = @{
        method = 'ExecuteQuery'; workflow_id = 'wf_t33_pt_invalid_' + [Guid]::NewGuid().ToString('N').Substring(0, 12); task_id = $taskId
        inputs = @(ConvertTo-T33InlineReference @{ file_path = '/app/does-not-exist.csv'; max_rows = 10; rename_columns = @{} })
    } | ConvertTo-Json -Depth 20 -Compress
    $response = Invoke-T33PortugalWebRequest -Method Post -Uri 'http://127.0.0.1:8001/control/execute' -Headers (Get-T33BearerHeaders $env:SERVICE_API_KEY) -Body $request
    Save-T33Text (Join-Path $e 'invalid-input-response.json') $response.Content
    $body = $response.Content | ConvertFrom-Json
    [PSCustomObject]@{ HttpStatus = $response.StatusCode; ServiceStatus = $body.status; Error = $body.error; OutputIsNull = ($null -eq $body.output) } | Format-List
    if ($response.StatusCode -eq 200 -and $body.status -eq 'failed' -and $body.error -match 'does-not-exist|No such file|not found') {
        Write-Host 'RESULT: PASS - invalid source file was rejected without a successful output reference.'
    }
    else { Write-Host 'RESULT: RECORDED - invalid-input behaviour differs from the expected safe failure pattern. Inspect the saved response.' }
}
finally { Stop-T33PortugalTranscript }
