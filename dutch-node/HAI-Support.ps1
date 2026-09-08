<#
.SYNOPSIS
Provides shared session, proxy-link and lifecycle helpers for the Dutch HAI tests.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It centralises behaviour used by the executable tests.

.NOTES
This is an internal helper file loaded by other scripts; do not run it directly.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Support.ps1')

# Deployment readiness and service-key discovery
function Initialize-HAITest {
    $settings = Read-Settings
    Assert-Baseline $settings
    Wait-Container 'hai-testing-service' 180
    Wait-Container 'hai-session-proxy' 180
    return $settings
}

function Get-HAIServiceKey {
    $entry = @(docker inspect hai-testing-service --format '{{range .Config.Env}}{{println .}}{{end}}' |
        Where-Object { $_.StartsWith('SERVICE_API_KEY=') }) | Select-Object -First 1
    if (-not $entry) { throw 'SERVICE_API_KEY was not found in hai-testing-service.' }
    return $entry.Substring('SERVICE_API_KEY='.Length)
}

# Redis-backed slot state used by the capacity and cleanup tests
function Get-HAISlots {
    [PSCustomObject]@{
        Slot1 = (docker exec hai-redis redis-cli --raw GET hai:slot:1).Trim()
        Slot2 = (docker exec hai-redis redis-cli --raw GET hai:slot:2).Trim()
    }
}

# Create an isolated technical session and decode its inline signed links.
function Start-HAITestSession {
    param([Parameter(Mandatory)][string]$ServiceKey,[Parameter(Mandatory)][string]$Label,[int]$TimeoutSeconds=300)
    $nonce=[Guid]::NewGuid().ToString('N').Substring(0,12)
    $taskId="task_t33_hai_$Label`_$nonce"
    $spec=@{scenario=@{name=''};agent=@{name=''};survey=@{survey_id=''};kpis=@();session_timeout_seconds=$TimeoutSeconds}
    $inline=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($spec|ConvertTo-Json -Depth 10 -Compress)))
    $request=@{method='StartHumanAISession';workflow_id="wf_t33_hai_$Label`_$nonce";task_id=$taskId;inputs=@(@{protocol='inline';uri=$inline;format='json'})}
    $requestB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request|ConvertTo-Json -Depth 20 -Compress)))
    $shell=@'
set -eu
printf '%s' "$T33_REQUEST_B64" | base64 -d > /tmp/t33-hai-request.json
curl -sS -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $T33_KEY" --data-binary @/tmp/t33-hai-request.json http://localhost:8080/control/execute
rm -f /tmp/t33-hai-request.json
'@
    $text=@($shell|docker exec -i -e "T33_KEY=$ServiceKey" -e "T33_REQUEST_B64=$requestB64" hai-testing-service sh) -join "`n"
    $response=$text|ConvertFrom-Json
    $links=$null
    if($response.output -and $response.output.protocol -eq 'inline'){
        $links=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($response.output.uri))|ConvertFrom-Json)
    }
    [PSCustomObject]@{TaskId=$taskId;Response=$response;ResponseText=$text;Links=$links}
}

# Session observation and controlled test cleanup
function Get-HAIStatus {
    param([Parameter(Mandatory)][string]$ServiceKey,[Parameter(Mandatory)][string]$TaskId)
    $text=@(docker exec hai-testing-service curl -sS -H "Authorization: Bearer $ServiceKey" "http://localhost:8080/control/status/$TaskId") -join "`n"
    return $text|ConvertFrom-Json
}

function Remove-HAITestSession {
    param([Parameter(Mandatory)][string]$TaskId,[switch]$RemoveRecord)
    $slots=Get-HAISlots
    $slot=if($slots.Slot1 -eq $TaskId){1}elseif($slots.Slot2 -eq $TaskId){2}else{$null}
    if($null -eq $slot){ return $false }
    docker exec hai-testing-service curl -fsS -X POST "http://hai-slot-$slot-simulator:5000/hai/reset" | Out-Null
    docker exec hai-testing-service curl -fsS -X POST "http://hai-slot-$slot-survey:80/api/reset" | Out-Null
    docker exec hai-redis redis-cli DEL "hai:slot:$slot" "hai:session-lock:$TaskId" | Out-Null
    if($RemoveRecord){
        docker exec hai-redis redis-cli DEL "hai:session:$TaskId" | Out-Null
        docker exec hai-redis redis-cli SREM hai:sessions $TaskId | Out-Null
    }
    return $true
}

# Post-restart readiness check used by the rerun test
function Wait-HAIHealthy {
    $deadline=(Get-Date).AddSeconds(120)
    while((Get-Date)-lt $deadline){
        $state=(docker inspect hai-testing-service --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}').Trim()
        if($state -eq 'healthy'){return $true}
        Write-Host "Waiting for hai-testing-service; state=$state"; Start-Sleep -Seconds 5
    }
    return $false
}
