<#
.SYNOPSIS
Creates one evaluator's heuristic-evaluation forms for one interface (UX-01).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Creates, under EvidenceRoot\ux\<Interface>\<Evaluator>:
  coverage.csv  - the ten heuristics; the evaluator enters 'yes' in Checked for each one examined;
  problems.csv  - one row per usability problem: Heuristic (H1-H10), Location, Description, Severity (0-4);
  session.json  - interface, evaluator pseudonym, start time and baselines.
Evaluators work alone and use pseudonyms only (E1, E2, ...). Follow UX-EVALUATION-PROTOCOL.md.

.NOTES
Run once per evaluator and interface. Existing forms are never overwritten.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^E[0-9]{1,2}$')][string]$Evaluator,
    [Parameter(Mandatory)][ValidateSet('Dutch-HAI','Danish-WebUI','Service-Onboarding')][string]$Interface
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

$script:T33Heuristics = [ordered]@{
    H1 = 'Visibility of system status'; H2 = 'Match between system and the real world'; H3 = 'User control and freedom'
    H4 = 'Consistency and standards'; H5 = 'Error prevention'; H6 = 'Recognition rather than recall'
    H7 = 'Flexibility and efficiency of use'; H8 = 'Aesthetic and minimalist design'
    H9 = 'Help users recognise, diagnose and recover from errors'; H10 = 'Help and documentation'
}

Invoke-T33SupTest -Settings $s -Label "40-ux-forms-$($Interface.ToLower())-$($Evaluator.ToLower())" -Body {
    param($e)
    $folder = Join-Path $s.EvidenceRoot "ux\$Interface\$Evaluator"
    if (Test-Path $folder) { Stop-T33Blocked "forms already exist for $Evaluator on $Interface at $folder. They are never overwritten." }
    New-Item -ItemType Directory -Force $folder | Out-Null

    $coverage = foreach ($k in $script:T33Heuristics.Keys) { [pscustomobject][ordered]@{ Heuristic = $k; Name = $script:T33Heuristics[$k]; Checked = '' } }
    Save-T33Csv (Join-Path $folder 'coverage.csv') $coverage
    Save-T33Text (Join-Path $folder 'problems.csv') ('"Heuristic","Location","Description","Severity"' + "`r`n")
    Save-T33Json (Join-Path $folder 'session.json') ([ordered]@{
        interface = $Interface; evaluator = $Evaluator; created_at = (Get-Date).ToString('o')
        platform_commit = $s.PlatformCommit; severity_scale = '0 not a problem, 1 cosmetic, 2 minor, 3 major, 4 catastrophic'
    })
    Write-Host "Forms created in $folder"
    Write-Host 'Fill coverage.csv (Checked = yes) and problems.csv, one row per problem, then run 41-Summarise-UX-Evaluation.ps1.'
    return (New-T33Verdict 'RECORDED' "evaluation forms for $Evaluator on $Interface created in $folder.")
}
