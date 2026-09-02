# AI-EFFECT Task 3.3 — Germany Node Baseline Suite v2.0

This release reproduces the German-node checks that were successfully run on the frozen baseline on 2 September 2026. It is deliberately a **baseline evidence suite**, not a claim that the complete Germany workflow is ready for sign-off.

## What this release can run

| Script | Result on the frozen baseline |
|---|---|
| `00-Preflight-And-Dependency-Check.ps1` | Pass |
| `01-Start-Core-And-Germany-Services.ps1` | Blocked at unavailable VILLASnode image; core stack starts |
| `02-Test-Authentication.ps1` | Pass |
| `11-Check-Packaged-Generator-Input.ps1` | Defect confirmed |
| `40-Test-Workflow-Definition-Validation.ps1` | Pass |
| `50-Test-Secret-Lifecycle.ps1` | Defect confirmed |
| `99-Collect-Closeout-Evidence.ps1` | Pass |

The VILLASnode-dependent functional, output, repeatability and concurrency tests are listed in `BLOCKED-TEST-CATALOG.md`. They are intentionally not included as runnable scripts in this release because the exact referenced VILLASnode image cannot be retrieved.

## Local layout

```text
C:\T33\ai-effect-wp3                AI-EFFECT WP3 source repository
C:\T33\ai-effect-task3-3-tests\german-node
                                      This GitHub test package
C:\ae33de-evidence                   Evidence output
```

## First-time setup

```powershell
Set-Location C:\T33\ai-effect-task3-3-tests\german-node
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
Copy-Item .\Test-Settings.psd1.example .\Test-Settings.psd1
```

Check `Test-Settings.psd1` before running. The default values match the documented local layout above.

Create temporary keys in the same terminal before running scripts 01, 02 or 40:

```powershell
function New-TestSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}
$env:ORCHESTRATOR_API_KEY = New-TestSecret
$env:SERVICE_API_KEY = New-TestSecret
```

## Run order

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-Preflight-And-Dependency-Check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\01-Start-Core-And-Germany-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\02-Test-Authentication.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\11-Check-Packaged-Generator-Input.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\40-Test-Workflow-Definition-Validation.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\50-Test-Secret-Lifecycle.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\99-Collect-Closeout-Evidence.ps1
```

If script 01 reports that the VILLAS image is unavailable, preserve its evidence and continue only with scripts 02, 11, 40, 50 and 99. Do not substitute another VILLAS image for an official baseline result.

## Safety boundaries

The scripts do not edit source files, Compose files, dependency locks or submodule revisions. `Test-Settings.psd1` is local-only and is excluded from version control. Each run creates a timestamped evidence folder under `C:\ae33de-evidence`.
