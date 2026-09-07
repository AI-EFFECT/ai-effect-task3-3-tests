# AI-EFFECT Task 3.3 - Germany Node Baseline Suite v2.1

This release reproduces the German-node checks that were successfully run on
the frozen baseline and adds a final dependency closure gate executed on 7
September 2026. It is a **baseline evidence suite**, not a claim that the
complete Germany workflow is ready for sign-off.

## What this release can run

| Script | Result on the frozen baseline |
|---|---|
| `00-Preflight-And-Dependency-Check.ps1` | Pass |
| `01-Start-Core-And-Germany-Services.ps1` | Blocked at the unavailable VILLASnode image; core and adapter services can start |
| `02-Test-Authentication.ps1` | Pass |
| `11-Check-Packaged-Generator-Input.ps1` | Defect confirmed |
| `40-Test-Workflow-Definition-Validation.ps1` | Pass |
| `50-Test-Secret-Lifecycle.ps1` | Defect confirmed |
| `60-Check-VILLAS-Closure-Gate.ps1` | Blocked; resolves the actual `villas-node` Compose service and confirms its configured image is unavailable locally |
| `99-Collect-Closeout-Evidence.ps1` | Pass |

The VILLASnode-dependent functional, output, recovery, concurrency and resource
tests are listed in `BLOCKED-TEST-CATALOG.md`. They are not included as runnable
scripts because the exact referenced VILLASnode image cannot be retrieved or
started on the frozen baseline.

## Local layout

```text
C:\T33\ai-effect-wp3
                                      AI-EFFECT WP3 source repository
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

Check `Test-Settings.psd1` before running. The default values match the
documented local layout. `Test-Settings.psd1` is local-only and must not be
committed.

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

Do not display or paste the expanded Compose configuration because it can
contain temporary test keys.

## Run order

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-Preflight-And-Dependency-Check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\01-Start-Core-And-Germany-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\02-Test-Authentication.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\11-Check-Packaged-Generator-Input.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\40-Test-Workflow-Definition-Validation.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\50-Test-Secret-Lifecycle.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\60-Check-VILLAS-Closure-Gate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\99-Collect-Closeout-Evidence.ps1
```

If script 01 reports that the VILLAS image cannot be retrieved, preserve its
evidence and continue with the non-VILLAS checks. Script 60 must then confirm
the dependency state without pulling or substituting an image.

## Expected v2.1 closure position

- The orchestrator, authentication, packaged-input, workflow-validation,
  service-key and close-out checks remain reproducible.
- The configured `villas-node` service requires
  `registry.git.rwth-aachen.de/acs/public/villas/node:hook-timeseries-chronix-conversion`.
- That exact image was unavailable from the registry and was not present
  locally during the 7 September 2026 closure run.
- A local image named `germany-node-villas-chronics` is an adapter image and
  must not be treated as the external VILLASnode runtime.
- The correct Task 3.3 status is conditional closure with VILLAS-dependent
  checks blocked pending an owner-supplied immutable runtime.

## Safety boundaries

The scripts do not edit source files, Compose files, dependency locks or
submodule revisions. Each run creates a timestamped evidence folder under
`C:\ae33de-evidence`. Do not publish evidence directories, test settings,
credentials or local Docker configuration in this repository.

