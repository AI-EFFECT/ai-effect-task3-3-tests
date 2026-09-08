<#
.SYNOPSIS
Validates German workflow definitions without claiming VILLAS-dependent runtime execution.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Require-Keys $s;Assert-Baseline $s;$e=New-EvidenceFolder $s '40-definition-validation';Start-EvidenceTranscript $e
try {$d=Get-GermanyDefinition $s;$blueprint=Get-Content $d.Blueprint -Raw|ConvertFrom-Json;$dockerinfo=Get-Content $d.DockerInfo -Raw|ConvertFrom-Json;$sourceNode=@($blueprint.nodes|Where-Object{$_.container_name -eq 'data_provider1'}|Select-Object -First 1);if($sourceNode.Count -ne 1){throw 'Expected Germany data_provider1 node was not found.'};$operation=@($sourceNode[0].operation_signature_list|Where-Object{$_.operation_signature.operation_name -eq 'ProvideData'}|Select-Object -First 1);if($operation.Count -ne 1){throw 'Expected ProvideData operation was not found.'};$connection=@($operation[0].connected_to|Select-Object -First 1);if($connection.Count -ne 1){throw 'Expected downstream connection was not found.'};$original=$connection[0].container_name;$connection[0].container_name='not_a_real_service';$body=@{blueprint=$blueprint;dockerinfo=$dockerinfo;inputs=@();services_api_key=$s.ServiceApiKey}|ConvertTo-Json -Depth 100;$response=Invoke-T33WebRequest -Method Post -Uri "$($s.OrchestratorUrl)/workflows" -Headers (Get-OrchestratorHeaders $s) -ContentType 'application/json' -Body $body;[IO.File]::WriteAllText((Join-Path $e 'invalid-target-response.json'),$response.Content,[Text.UTF8Encoding]::new($false));[pscustomobject]@{StatusCode=$response.StatusCode;OriginalTarget=$original;InjectedTarget=$connection[0].container_name}|Format-List;if($response.StatusCode -eq 400){Write-Host 'RESULT: PASS - invalid connection target rejected before execution.'}else{Write-Host 'RESULT: FAIL - invalid connection target was not rejected with HTTP 400.'}} finally {Stop-EvidenceTranscript}
