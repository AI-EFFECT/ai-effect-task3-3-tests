<#
.SYNOPSIS
Guides a named reviewer through a structured expert heuristic review of the live HAI interface.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 Dutch node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reviewer,
    [switch]$StartReviewSession,
    [switch]$ObservedLiveSession,
    [string]$RelatedEvidence = ''
)

. (Join-Path $PSScriptRoot 'HAI-Support.ps1')

$settings = Initialize-HAITest
$evidence = New-EvidenceFolder $settings '51-hai-expert-ux-review'
Start-Transcript -Path (Join-Path $evidence 'run.txt') -Force
$reviewSession = $null

function Read-Rating {
    param([string]$Prompt)
    do {
        $raw = Read-Host "$Prompt (1=poor, 2, 3, 4, 5=excellent, N/A)"
        if ($raw -eq 'N/A') { return $null }
        $rating = 0
        $valid = [int]::TryParse($raw, [ref]$rating) -and $rating -ge 1 -and $rating -le 5
        if (-not $valid) { Write-Host 'Enter 1 to 5, or N/A.' }
    } while (-not $valid)
    return $rating
}

try {
    $liveSessionObserved = $ObservedLiveSession.IsPresent
    if ($StartReviewSession) {
        $key = Get-HAIServiceKey
        $reviewSession = Start-HAITestSession -ServiceKey $key -Label 'uxreview' -TimeoutSeconds 1800
        if ($reviewSession.Response.status -ne 'pending' -or $null -eq $reviewSession.Links -or
            [string]::IsNullOrWhiteSpace($reviewSession.Links.gui_url)) {
            throw 'The HAI review session did not provide a signed GUI link.'
        }
        if ($null -eq (Get-Command Set-Clipboard -ErrorAction SilentlyContinue)) {
            throw 'Set-Clipboard is unavailable. The signed review link was not printed to avoid exposing its token.'
        }
        $reviewSession.Links.gui_url | Set-Clipboard
        [pscustomobject][ordered]@{
            TaskId = $reviewSession.TaskId
            Status = $reviewSession.Response.status
            SignedUrlCopiedToClipboard = $true
            SignedUrlRecordedInEvidence = $false
        } | ConvertTo-Json | Set-Content -Path (Join-Path $evidence 'review-session.json') -Encoding utf8
        Write-Host "A labelled HAI review session was started: $($reviewSession.TaskId)"
        Write-Host 'Its signed GUI link was copied to the Windows clipboard and was not written to the transcript.'
        [void](Read-Host 'Open a browser, paste the link, inspect the live technical journey, then press Enter here')
        $confirmation = Read-Host 'Type OBSERVED to confirm that you personally inspected the live session'
        $liveSessionObserved = ($confirmation -ceq 'OBSERVED')
    }

    if (-not $liveSessionObserved) {
        Write-Host 'RESULT: INCOMPLETE - no explicit confirmation of a personally observed live HAI session was recorded.'
        return
    }

    Write-Host 'This is an expert heuristic review of the technical interface. It is not a participant study.'
    $checks = @(
        @{ Id='UX-01'; Area='Entry and task clarity'; Question='How clearly does the interface explain what the operator must do?' },
        @{ Id='UX-02'; Area='Navigation'; Question='How easily can the operator identify the current step and the next action?' },
        @{ Id='UX-03'; Area='System status'; Question='How clearly are loading, running, waiting and completion states shown?' },
        @{ Id='UX-04'; Area='Error recovery'; Question='How clearly are timeout, refusal and recovery actions explained?' },
        @{ Id='UX-05'; Area='Terminology'; Question='How understandable and consistent are labels and domain terms?' },
        @{ Id='UX-06'; Area='Readability'; Question='How readable are text, controls, spacing and visual hierarchy at normal zoom?' },
        @{ Id='UX-07'; Area='Keyboard and focus'; Question='How usable are the main actions with keyboard navigation and visible focus?' },
        @{ Id='UX-08'; Area='Completion feedback'; Question='How clearly does the interface confirm submission and completion?' },
        @{ Id='UX-09'; Area='Trust and data notice'; Question='How clearly does the interface explain technical data use and session state?' },
        @{ Id='UX-10'; Area='Overall technical usability'; Question='How usable is the tested technical journey overall?' }
    )

    $results = @()
    foreach ($check in $checks) {
        Write-Host "`n$($check.Id) - $($check.Area)"
        $rating = Read-Rating -Prompt $check.Question
        $observation = Read-Host 'Brief observation or evidence reference'
        $results += [pscustomobject][ordered]@{
            TestId          = $check.Id
            Area            = $check.Area
            Rating          = $rating
            Observation     = $observation
            Reviewer        = $Reviewer
            ReviewedAt      = (Get-Date).ToString('o')
            RelatedEvidence = $RelatedEvidence
            ReviewSessionTaskId = if ($null -ne $reviewSession) { $reviewSession.TaskId } else { '' }
        }
    }

    $results | Export-Csv -Path (Join-Path $evidence 'hai-ux-review.csv') -NoTypeInformation -Encoding utf8
    Save-Json $results (Join-Path $evidence 'hai-ux-review.json')
    $numeric = @($results | Where-Object { $null -ne $_.Rating })
    $average = if ($numeric.Count) { [math]::Round(($numeric.Rating | Measure-Object -Average).Average, 2) } else { $null }
    $low = @($numeric | Where-Object Rating -le 2)
    [pscustomobject]@{ ReviewedItems=$results.Count; RatedItems=$numeric.Count; MeanRating=$average; LowRatedItems=($low.TestId -join ', ') } | Format-List

    if ($numeric.Count -lt 7) {
        Write-Host 'RESULT: PARTIAL - fewer than seven heuristic areas were rated. Preserve the review and explain exclusions.'
    }
    elseif ($low.Count -gt 0) {
        Write-Host 'RESULT: FINDINGS RECORDED - expert UI/UX review completed with one or more low-rated areas.'
    }
    else {
        Write-Host 'RESULT: PASS - expert technical UI/UX review completed. This is not evidence from a real participant study.'
    }
}
finally {
    if ($null -ne $reviewSession) {
        [void](Remove-HAITestSession -TaskId $reviewSession.TaskId -RemoveRecord)
    }
    try { Stop-Transcript } catch { }
}
