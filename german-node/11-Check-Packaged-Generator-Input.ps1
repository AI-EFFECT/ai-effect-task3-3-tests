<#
.SYNOPSIS
Inspects the packaged German generator input and records whether required data is usable.

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 German node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
#>
. (Join-Path $PSScriptRoot '_Support.ps1')
$s=Read-Settings;Assert-Baseline $s;$e=New-EvidenceFolder $s '11-generator-input';Start-EvidenceTranscript $e
try {$raw=Get-ChildItem $s.GermanyRoot -Recurse -Filter 'SGen1.csv'|Select-Object -First 1;$converted=Get-ChildItem $s.GermanyRoot -Recurse -Filter 'SGen1_converted.csv'|Select-Object -First 1;if(-not $raw -or -not $converted){throw 'SGen1.csv or SGen1_converted.csv was not found under GermanyRoot.'};$rawRows=[Math]::Max(0,@(Get-Content $raw.FullName).Count-1);$convertedRows=[Math]::Max(0,@(Get-Content $converted.FullName).Count-1);[pscustomobject]@{Raw=$raw.FullName;RawRows=$rawRows;Converted=$converted.FullName;ConvertedRows=$convertedRows}|Format-List;if($rawRows -gt 0 -and $convertedRows -eq 0){Write-Host 'RESULT: DEFECT CONFIRMED - packaged SGen1_converted.csv has no data rows.'}else{Write-Host 'RESULT: RECORDED - generator input differs from the frozen baseline; review semantics with the node owner.'}} finally {Stop-EvidenceTranscript}
