# Portuguese node script guide

This page explains each PowerShell file in the package. Follow the run order in [START-HERE.md](START-HERE.md).

| Script | Purpose and interpretation |
|---|---|
| `_Support.ps1` | Shared settings, workspace, evidence, HTTP and container helpers. Loaded by other scripts; do not run directly. |
| `00-Prepare-Portugal-Fixture.ps1` | Builds a marked disposable integrated workspace from the supplied TEF source and AI-EFFECT overlay, then records the fixture hash. `-Reset` recreates only that marked workspace and isolated test volumes. |
| `01-Start-Core-And-Portugal-Services.ps1` | Starts the orchestrator and integrated Portuguese services with test-specific health-check overrides, then waits for readiness. |
| `02-Test-Orchestrator-Authentication.ps1` | Confirms missing and invalid tokens are rejected while a valid token reaches the orchestrator application. |
| `03-Record-Knowledge-Store-Health-Configuration.ps1` | Compares the supplied Knowledge Store health check with the effective test check and live endpoints. It documents the supplied configuration defect. |
| `04-Record-Synthetic-Data-Health-Configuration.ps1` | Compares the supplied Synthetic Data health check with the responsive endpoint used by the test deployment. |
| `10-Test-Portugal-Data-Load.ps1` | Loads the supplied wind-energy fixture through the integrated control path and validates the returned HTTP CSV. |
| `11-Test-Portugal-Feature-Engineering.ps1` | Passes the upstream CSV reference to feature engineering and checks the renamed timestamp and added hour feature. |
| `20-Test-Portugal-Workflow.ps1` | Runs the complete four-stage integrated workflow and saves task and output evidence. |
| `22-Test-Portugal-Invalid-Input.ps1` | Requests a missing input file and confirms safe failure without a successful output reference. |
| `23-Test-Repeatability-And-Performance.ps1` | Repeats the integrated workflow and records duration, output structure, hashes and resource samples. It is an initial reference, not a scalability result. |
| `24-Test-Restart-And-Rerun.ps1` | Restarts the isolated Portuguese service stack while retaining named volumes, measures observed recovery and runs a fresh workflow. |
| `25-Test-Bounded-Concurrency.ps1` | Starts a small number of overlapping workflows and records their completion and resource use. It is a smoke test, not a capacity limit. |
| `30-Prepare-Sidecar-Workspace.ps1` | Builds a separate marked workspace for the legacy sidecar route without modifying the supplied TEF source. |
| `31-Start-Sidecar-Services.ps1` | Applies the protocol/port gate before sidecar startup. It records a blocker when adapters expect gRPC but services expose HTTP. |
| `32-Test-Sidecar-Workflow.ps1` | Runs the legacy sidecar workflow only after the protocol gate passes; it must not be used to bypass the known mismatch. |
| `35-Stop-Portugal-Test-Services.ps1` | Stops integrated and sidecar test containers while retaining workspaces and named volumes for review. |
| `99-Collect-Closeout-Evidence.ps1` | Saves frozen-source, external-fixture, workspace, Compose, image and runtime inventories before shutdown. |

Preserve all timestamped evidence. Output values from unseeded synthetic generation may differ between runs, so repeatability is judged by completion and structure unless a deterministic seed is explicitly introduced.

