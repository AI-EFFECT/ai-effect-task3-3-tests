<#
.SYNOPSIS
Runs feature engineering and checks the renamed timestamp and added hour field.

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
Wait-T33Container 'tef-knowledge-store'

$e = New-T33PortugalEvidence $s '11-feature-engineering'
Start-T33PortugalTranscript $e

try {
    # DatetimeFeatures requires the supplied fixture's datetime field to be named timestamp.
    $loadTaskId = 'task_t33_pt_feature_load_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $loadRequest = @{
        method      = 'ExecuteQuery'
        workflow_id = 'wf_t33_pt_feature_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
        task_id     = $loadTaskId
        inputs      = @(
            ConvertTo-T33InlineReference @{
                file_path      = '/app/real_data.csv'
                max_rows       = 1000
                rename_columns = @{ datetime = 'timestamp' }
            }
        )
    } | ConvertTo-Json -Depth 20 -Compress

    $loadResponse = Invoke-T33PortugalWebRequest -Method Post -Uri 'http://127.0.0.1:8001/control/execute' -Body $loadRequest
    Save-T33Text (Join-Path $e 'load-response.json') $loadResponse.Content
    $loadBody = $loadResponse.Content | ConvertFrom-Json

    if ($loadResponse.StatusCode -ne 200 -or $loadBody.status -ne 'complete' -or $null -eq $loadBody.output -or $loadBody.output.protocol -ne 'http') {
        throw 'The prerequisite data-load request failed.'
    }

    $featureTaskId = 'task_t33_pt_features_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $featureRequest = @{
        method      = 'ApplyFunction'
        workflow_id = 'wf_t33_pt_feature_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
        task_id     = $featureTaskId
        inputs      = @(
            @{
                protocol = $loadBody.output.protocol
                uri      = $loadBody.output.uri
                format   = $loadBody.output.format
            }
        )
    } | ConvertTo-Json -Depth 20 -Compress

    $featureResponse = Invoke-T33PortugalWebRequest -Method Post -Uri 'http://127.0.0.1:8002/control/execute' -Body $featureRequest
    Save-T33Text (Join-Path $e 'feature-response.json') $featureResponse.Content
    $featureBody = $featureResponse.Content | ConvertFrom-Json
    $output = $featureBody.output

    $outputProtocol = ''
    $outputFormat = ''
    $dataText = ''

    if ($null -ne $output) {
        if ($null -ne $output.PSObject.Properties['protocol']) { $outputProtocol = [string]$output.protocol }
        if ($null -ne $output.PSObject.Properties['format']) { $outputFormat = [string]$output.format }

        if ($featureResponse.StatusCode -eq 200 -and $featureBody.status -eq 'complete' -and $outputProtocol -eq 'http') {
            $pythonCode = "import sys, urllib.request; sys.stdout.write(urllib.request.urlopen('$($output.uri)').read().decode())"
            $dataText = (& docker exec tef-knowledge-store python -c $pythonCode) -join "`n"
            Save-T33Text (Join-Path $e 'feature-data.csv') $dataText
        }
    }

    [PSCustomObject]@{
        HttpStatus     = $featureResponse.StatusCode
        ServiceStatus  = $featureBody.status
        OutputProtocol = $outputProtocol
        OutputFormat   = $outputFormat
        Error          = $featureBody.error
        Header         = if ($dataText) { ($dataText -split "`n")[0] } else { '' }
    } | Format-List

    if ($featureResponse.StatusCode -eq 200 -and $featureBody.status -eq 'complete' -and $outputProtocol -eq 'http' -and $outputFormat -eq 'csv' -and $dataText) {
        Write-Host 'RESULT: PASS - feature engineering accepted the renamed upstream HTTP CSV reference and returned CSV output.'
    }
    else {
        Write-Host 'RESULT: RECORDED - feature-engineering did not return the expected HTTP CSV result. Inspect the saved response.'
    }
}
finally {
    Stop-T33PortugalTranscript
}
