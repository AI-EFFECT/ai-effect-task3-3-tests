<#
.SYNOPSIS
Verifies that an invalid benchmark algorithm is safely rejected without producing an artifact.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Require-Keys $settings;Assert-Baseline $settings;Wait-Container 'benchmark-runner'
$evidence=New-EvidenceFolder $settings '22-invalid-algorithm';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    $nonce=[Guid]::NewGuid().ToString('N').Substring(0,12);$taskId="task_t33_invalid_algo_$nonce"
    $payload=@{benchmark=@{env_name='l2rpn_case14_sandbox';max_steps=10;time_series_ids=@(0)};algorithm=@{source="def wrong_agent(env, context):`n    return None"}}|ConvertTo-Json -Depth 20 -Compress
    [IO.File]::WriteAllText((Join-Path $evidence 'input.json'),$payload,[Text.UTF8Encoding]::new($false))
    $request=@{method='RunBenchmark';workflow_id="wf-t33-invalid-$nonce";task_id=$taskId;inputs=@(@{protocol='inline';uri=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload));format='json'})}|ConvertTo-Json -Depth 30 -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    $shell='printf "%s" "$T33_REQUEST_B64" | base64 -d >/tmp/request.json; curl -sS -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $T33_KEY" --data-binary @/tmp/request.json http://localhost:8080/control/execute; rm -f /tmp/request.json'
    $output=@($shell|docker exec -i -e "T33_KEY=$($settings.ServiceApiKey)" -e "T33_REQUEST_B64=$encoded" benchmark-runner sh)
    $http=[int]$output[-1];$response=($output[0..($output.Count-2)]-join "`n")|ConvertFrom-Json
    docker exec benchmark-runner sh -c "test -e /artifacts/$taskId.payload -o -e /artifacts/$taskId.meta.json";$artifactExists=($LASTEXITCODE -eq 0)
    [pscustomobject]@{HttpStatus=$http;ServiceStatus=$response.status;Error=$response.error;NoArtifact=(-not $artifactExists)}|Format-List
    if($http -ne 200 -or $response.status -ne 'failed' -or $response.error -notmatch 'build_agent\(env, context\)' -or $artifactExists){throw 'Invalid-algorithm acceptance criteria failed.'}
    Write-Host 'RESULT: PASS — invalid algorithm rejected; no artifact created.'
} finally {try{Stop-Transcript}catch{}}
