<#
.SYNOPSIS
Verifies that unknown or path-like benchmark algorithm names are safely rejected without producing an artifact.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$settings=Read-Settings;Require-Keys $settings;Assert-Baseline $settings;Wait-Container 'benchmark-runner'
$evidence=New-EvidenceFolder $settings '22-invalid-algorithm';Start-Transcript (Join-Path $evidence 'run.txt') -Force
try {
    # Algorithms are selected by file name from the node's read-only algorithm
    # directory; requests cannot carry code. Each case must be rejected before
    # a job starts, so no <workflow_id>.<task_id> artifact may appear.
    $cases=@(
        @{Name='unknown-name';Algorithm='t33_does_not_exist.py';ExpectedError='Unknown algorithm'},
        @{Name='path-traversal';Algorithm='../service.py';ExpectedError='must be a bare name'}
    )
    $shell='printf "%s" "$T33_REQUEST_B64" | base64 -d >/tmp/request.json; curl -sS -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $T33_KEY" --data-binary @/tmp/request.json http://localhost:8080/control/execute; rm -f /tmp/request.json'
    $results=foreach($case in $cases){
        $nonce=[Guid]::NewGuid().ToString('N').Substring(0,12);$workflowId="wf-t33-invalid-$nonce";$taskId="task_t33_invalid_algo_$nonce";$jobId="$workflowId.$taskId"
        $payload=@{algorithm=$case.Algorithm;benchmark=@{env_name='l2rpn_case14_sandbox';max_steps=10;time_series_ids=@(0)}}|ConvertTo-Json -Depth 20 -Compress
        [IO.File]::WriteAllText((Join-Path $evidence "input-$($case.Name).json"),$payload,[Text.UTF8Encoding]::new($false))
        $request=@{method='RunBenchmark';workflow_id=$workflowId;task_id=$taskId;inputs=@(@{protocol='inline';uri=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload));format='json'})}|ConvertTo-Json -Depth 30 -Compress
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
        $output=@($shell|docker exec -i -e "T33_KEY=$($settings.ServiceApiKey)" -e "T33_REQUEST_B64=$encoded" benchmark-runner sh)
        $http=[int]$output[-1];$response=($output[0..($output.Count-2)]-join "`n")|ConvertFrom-Json
        docker exec benchmark-runner sh -c "test -e '/artifacts/$jobId.payload' -o -e '/artifacts/$jobId.meta.json'";$artifactExists=($LASTEXITCODE -eq 0)
        $passed=($http -eq 200 -and $response.status -eq 'failed' -and "$($response.error)" -match [regex]::Escape($case.ExpectedError) -and -not $artifactExists)
        [pscustomobject]@{Case=$case.Name;Algorithm=$case.Algorithm;HttpStatus=$http;ServiceStatus=$response.status;Error=$response.error;NoArtifact=(-not $artifactExists);Passed=$passed}
    }
    $results|Format-List;Save-Json $results (Join-Path $evidence 'results.json')
    if(@($results|Where-Object { -not $_.Passed }).Count -gt 0){throw 'Invalid-algorithm acceptance criteria failed.'}
    Write-Host 'RESULT: PASS — unknown and path-like algorithm names rejected; no artifact created.'
} finally {try{Stop-Transcript}catch{}}
