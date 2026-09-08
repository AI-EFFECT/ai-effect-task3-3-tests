# German node script guide

This page explains each PowerShell file in the package. Follow the run order in [START-HERE.md](START-HERE.md).

| Script | Purpose and interpretation |
|---|---|
| `_Support.ps1` | Shared settings, evidence and container helpers. Loaded by other scripts; do not run directly. |
| `00-Preflight-And-Dependency-Check.ps1` | Records the frozen revision, Docker capability, configured services and whether the German stack is already running. A stopped stack is not itself a preflight failure. |
| `01-Start-Core-And-Germany-Services.ps1` | Starts the common orchestrator and supplied German services. If the exact VILLASnode image is unavailable, it records a blocker without substitution. |
| `02-Test-Authentication.ps1` | Confirms orchestrator token enforcement when the common core is available. |
| `11-Check-Packaged-Generator-Input.ps1` | Inspects the supplied generator input and records whether the packaged data required by the workflow is present and usable. |
| `40-Test-Workflow-Definition-Validation.ps1` | Validates workflow-definition handling without claiming VILLAS-dependent runtime execution. |
| `50-Test-Secret-Lifecycle.ps1` | Examines service-key creation and persistence behaviour and records the security lifecycle finding. |
| `60-Check-VILLAS-Closure-Gate.ps1` | Applies the strict closure gate: the configured VILLASnode image must be locally available with immutable identity and the service must be running before an end-to-end claim is possible. |
| `99-Collect-Closeout-Evidence.ps1` | Captures source, Compose, image and runtime inventories for the final review package. |

Keep `BLOCKED` evidence. It identifies an unavailable official dependency and must not be relabelled as a test failure or bypassed with an unapproved replacement image.

