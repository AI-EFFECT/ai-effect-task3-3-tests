# AI-EFFECT Task 3.3 - Germany Node Baseline Suite v2.1

This release reproduces available German-node checks and includes the dependency
closure gate executed on 7 September 2026. It is a baseline evidence suite, not
an unqualified end-to-end sign-off. See
[TEST-RESULTS-SUMMARY.md](TEST-RESULTS-SUMMARY.md) for the consolidated outcome.

## What this release can run

| Script | Result on the frozen baseline |
|---|---|
| `00-Preflight-And-Dependency-Check.ps1` | Pass |
| `01-Start-Core-And-Germany-Services.ps1` | Blocked at unavailable VILLASnode image; core and adapter services can start |
| `02-Test-Authentication.ps1` | Pass |
| `11-Check-Packaged-Generator-Input.ps1` | Defect confirmed |
| `40-Test-Workflow-Definition-Validation.ps1` | Pass |
| `50-Test-Secret-Lifecycle.ps1` | Defect confirmed |
| `60-Check-VILLAS-Closure-Gate.ps1` | Blocked; exact Compose image unavailable locally |
| `99-Collect-Closeout-Evidence.ps1` | Pass |

VILLASnode-dependent functional, output, recovery, concurrency, security and
resource tests are catalogued in `BLOCKED-TEST-CATALOG.md`. They cannot be run
until the exact owner-approved runtime is available.

## Local layout and setup

```text
C:\T33\ai-effect-wp3
                                      Frozen AI-EFFECT WP3 source
C:\T33\ai-effect-task3-3-tests\german-node
                                      Test package
C:\ae33de-evidence                   Evidence output
```

```powershell
Set-Location C:\T33\ai-effect-task3-3-tests\german-node
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
Copy-Item .\Test-Settings.psd1.example .\Test-Settings.psd1
```

Keep `Test-Settings.psd1` local. Generate temporary keys in the same terminal
without displaying them. Do not print or save expanded Compose configuration,
because it may contain test keys.

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
evidence and continue only with the independent checks. Script 60 must confirm
the dependency state without pulling or substituting another image.

## Closure position

- Frozen commit: `486ccc702bb2afca79fb7d31258d62ee0f94dbfc`.
- Required Compose image:
  `registry.git.rwth-aachen.de/acs/public/villas/node:hook-timeseries-chronix-conversion`.
- The exact image was unavailable from the registry and absent locally during
  closure testing.
- `germany-node-villas-chronics` is an adapter image, not VILLASnode.
- Status: conditional closure, with VILLAS-dependent checks blocked.

Each run creates timestamped evidence under `C:\ae33de-evidence`. Do not commit
evidence, settings, credentials or local Docker configuration.

