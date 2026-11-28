<#
.SYNOPSIS
Validates and aggregates all heuristic-evaluation forms (UX-02).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. For each interface under EvidenceRoot\ux it checks that
every evaluator covered all ten heuristics and that every problem has a valid heuristic and a severity from 0 to 4.

Duplicate problems reported by several evaluators are merged only where the facilitator has filled an optional
MergedId column in problems.csv (same MergedId = same problem). Without it, each row counts as its own problem.
Outputs per-interface and per-heuristic summaries and the list of severity 3-4 problems.

.NOTES
Fewer than three evaluators on an interface is recorded but does not meet the protocol.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label '41-ux-summary' -Body {
    param($e)
    $root = Join-Path $s.EvidenceRoot 'ux'
    if (-not (Test-Path $root)) { Stop-T33Blocked 'no evaluation forms were found. Run 40-New-UX-Evaluation-Forms.ps1 for each evaluator first.' }
    $valid = 'H1','H2','H3','H4','H5','H6','H7','H8','H9','H10'
    $issues = New-Object System.Collections.Generic.List[string]
    $interfaceRows = New-Object System.Collections.Generic.List[object]
    $heuristicRows = New-Object System.Collections.Generic.List[object]
    $severe = New-Object System.Collections.Generic.List[object]

    foreach ($ui in (Get-ChildItem $root -Directory)) {
        $all = New-Object System.Collections.Generic.List[object]
        $evaluators = @(Get-ChildItem $ui.FullName -Directory)
        foreach ($ev in $evaluators) {
            $coverage = @(Import-Csv (Join-Path $ev.FullName 'coverage.csv'))
            $missing = @($coverage | Where-Object { $_.Checked -notmatch '^(?i)y(es)?$' } | ForEach-Object Heuristic)
            if ($missing.Count -gt 0) { $issues.Add("$($ui.Name)/$($ev.Name): heuristics not marked as checked: $($missing -join ', ')") }
            foreach ($p in @(Import-Csv (Join-Path $ev.FullName 'problems.csv'))) {
                $sev = -1; [void][int]::TryParse([string]$p.Severity, [ref]$sev)
                if ($p.Heuristic -notin $valid -or $sev -lt 0 -or $sev -gt 4) { $issues.Add("$($ui.Name)/$($ev.Name): invalid row '$($p.Heuristic)' severity '$($p.Severity)'"); continue }
                $merged = if ($p.PSObject.Properties.Name -contains 'MergedId' -and $p.MergedId) { [string]$p.MergedId } else { "$($ev.Name)-$($all.Count + 1)" }
                $all.Add([pscustomobject]@{ Evaluator = $ev.Name; Heuristic = $p.Heuristic; Location = $p.Location; Description = $p.Description; Severity = $sev; MergedId = $merged })
            }
        }
        $unique = @($all | Group-Object MergedId)
        foreach ($g in $unique) {
            $maxSev = ($g.Group | Measure-Object Severity -Maximum).Maximum
            $finders = @($g.Group | ForEach-Object Evaluator | Sort-Object -Unique)
            if ($maxSev -ge 3) {
                $first = $g.Group[0]
                $severe.Add([pscustomobject][ordered]@{ Interface = $ui.Name; MergedId = $g.Name; Heuristic = $first.Heuristic; Location = $first.Location; Description = $first.Description; MaxSeverity = $maxSev; FoundBy = ($finders -join ' '); Evaluators = $finders.Count })
            }
        }
        foreach ($h in $valid) {
            $rows = @($all | Where-Object Heuristic -eq $h)
            $heuristicRows.Add([pscustomobject][ordered]@{
                Interface = $ui.Name; Heuristic = $h; Reports = $rows.Count
                MeanSeverity = if ($rows.Count) { [math]::Round(($rows | Measure-Object Severity -Average).Average, 2) } else { '' }
                MaxSeverity = if ($rows.Count) { ($rows | Measure-Object Severity -Maximum).Maximum } else { '' }
            })
        }
        $interfaceRows.Add([pscustomobject][ordered]@{
            Interface = $ui.Name; Evaluators = $evaluators.Count; Reports = $all.Count; UniqueProblems = $unique.Count
            Severity3or4 = @($unique | Where-Object { ($_.Group | Measure-Object Severity -Maximum).Maximum -ge 3 }).Count
            FoundByTwoOrMore = @($unique | Where-Object { @($_.Group | ForEach-Object Evaluator | Sort-Object -Unique).Count -ge 2 }).Count
            MeetsProtocol = ($evaluators.Count -ge 3)
        })
    }

    Save-T33Csv (Join-Path $e 'ux-interfaces.csv') $interfaceRows
    Save-T33Csv (Join-Path $e 'ux-heuristics.csv') $heuristicRows
    Save-T33Csv (Join-Path $e 'ux-severe-problems.csv') $severe
    Save-T33Text (Join-Path $e 'validation-issues.txt') ($issues -join "`r`n")
    foreach ($r in $interfaceRows) { Write-Host "$($r.Interface): evaluators=$($r.Evaluators) unique=$($r.UniqueProblems) severe=$($r.Severity3or4)" }

    if ($issues.Count -gt 0) { return (New-T33Verdict 'FAIL' "$($issues.Count) form problem(s) must be corrected before the summary can be used. See validation-issues.txt.") }
    $short = @($interfaceRows | Where-Object { -not $_.MeetsProtocol } | ForEach-Object Interface)
    if ($short.Count -gt 0) { return (New-T33Verdict 'RECORDED' "summary produced, but these interfaces have fewer than three evaluators: $($short -join ', ').") }
    return (New-T33Verdict 'FINDINGS RECORDED' "$($interfaceRows.Count) interface(s) evaluated; $($severe.Count) problem(s) of severity 3 or 4. See ux-severe-problems.csv.")
}
