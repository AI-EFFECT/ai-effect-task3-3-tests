<#
.SYNOPSIS
Checks that a valid signed GUI link works and a tampered link is rejected.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '34-hai-signed-proxy-link'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
$session = $null
try {
    $key = Get-HAIServiceKey
    $session = Start-HAITestSession -ServiceKey $key -Label 'proxy' -TimeoutSeconds 120
    if ($session.Response.status -ne 'pending' -or $null -eq $session.Links -or [string]::IsNullOrWhiteSpace($session.Links.gui_url)) {
        throw 'The HAI session did not provide a signed GUI link.'
    }

    $validBody = Join-Path $evidence 'valid-link-body.html'
    $tamperedBody = Join-Path $evidence 'tampered-link-body.html'
    $validCookies = Join-Path $evidence 'valid-link-cookies.txt'
    $tamperedCookies = Join-Path $evidence 'tampered-link-cookies.txt'
    # -c/-b starts an empty cookie jar, then permits the proxy's token-to-cookie
    # exchange while following its redirect.
    $validCode = (& curl.exe -sS -L --max-time 30 -c $validCookies -b $validCookies -o $validBody -w '%{http_code}' $session.Links.gui_url).Trim()
    $tamperedUrl = "$($session.Links.gui_url)x"
    $tamperedCode = (& curl.exe -sS -L --max-time 30 -c $tamperedCookies -b $tamperedCookies -o $tamperedBody -w '%{http_code}' $tamperedUrl).Trim()
    Save-Json $session.Response (Join-Path $evidence 'session-response.json')

    [PSCustomObject]@{
        TaskId = $session.TaskId
        SessionStarted = ($session.Response.status -eq 'pending')
        ValidSignedLinkFinalHttpStatus = $validCode
        TamperedSignedLinkFinalHttpStatus = $tamperedCode
        ValidLinkReachedGui = ($validCode -eq '200')
        TamperedLinkRejected = ($tamperedCode -eq '403')
    } | Format-List
    if ($validCode -ne '200' -or $tamperedCode -ne '403') { throw 'Signed-link access control did not match the expected result.' }
    Write-Host 'RESULT: PASS - valid signed link reached the GUI and a tampered link was rejected.'
}
finally {
    if ($session) { [void](Remove-HAITestSession -TaskId $session.TaskId -RemoveRecord) }
    try { Stop-Transcript } catch {}
}
