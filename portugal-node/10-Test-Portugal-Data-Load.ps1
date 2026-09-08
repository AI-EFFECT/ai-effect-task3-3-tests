<#
.SYNOPSIS
Loads the supplied wind-energy fixture through the integrated control path and validates its CSV output.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Portuguese node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-T33PortugalSettings;Assert-T33PortugalBaseline $s;Assert-T33Workspace $s Integrated|Out-Null;Wait-T33Container 'tef-data-provision';$e=New-T33PortugalEvidence $s '10-data-load';Start-T33PortugalTranscript $e
try {
    $taskId='task_t33_pt_load_'+[Guid]::NewGuid().ToString('N').Substring(0,12);$request=@{method='ExecuteQuery';workflow_id='wf_t33_pt_load_'+[Guid]::NewGuid().ToString('N').Substring(0,12);task_id=$taskId;inputs=@(ConvertTo-T33InlineReference @{file_path='/app/real_data.csv';max_rows=1000;rename_columns=@{}})}|ConvertTo-Json -Depth 20 -Compress
    $response=Invoke-T33PortugalWebRequest -Method Post -Uri 'http://127.0.0.1:8001/control/execute' -Body $request;Save-T33Text (Join-Path $e 'execute-response.json') $response.Content;$body=$response.Content|ConvertFrom-Json;$output=$body.output;$dataText=''
    if($response.StatusCode -eq 200 -and $body.status -eq 'complete' -and $null -ne $output -and $output.protocol -eq 'http'){$dataText=(& docker exec tef-data-provision curl -fsS $output.uri)-join "`n";Save-T33Text (Join-Path $e 'loaded-data.csv') $dataText}
    [PSCustomObject]@{HttpStatus=$response.StatusCode;ServiceStatus=$body.status;OutputProtocol=$output.protocol;OutputFormat=$output.format;OutputRows=if($dataText){(@($dataText -split "`n").Count-1)}else{0};Header=if($dataText){($dataText -split "`n")[0]}else{''}}|Format-List
    if($response.StatusCode -eq 200 -and $body.status -eq 'complete' -and $output.protocol -eq 'http' -and $output.format -eq 'csv' -and $dataText){Write-Host 'RESULT: PASS - the supplied Portugal TEF fixture was loaded and served through the integrated control path.'}else{throw 'Portugal data-load check did not return the expected HTTP CSV result.'}
} finally {Stop-T33PortugalTranscript}
