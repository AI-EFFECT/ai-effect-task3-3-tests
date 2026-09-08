# Dutch node script guide

This page explains each PowerShell file in the package. Follow the run order in [START-HERE.md](START-HERE.md); the numbering groups related tests but does not make every script safe to run in isolation.

| Script | Purpose and interpretation |
|---|---|
| `_Support.ps1` | Shared evidence, HTTP and container helpers. Loaded by other scripts; do not run directly. |
| `HAI-Support.ps1` | Shared HAI session and signed-link helpers. Loaded by HAI scripts; do not run directly. |
| `00-Start-Core-Services.ps1` | Verifies the frozen baseline, starts the orchestrator, synthesizer and benchmark services, and waits for readiness. |
| `01-Test-Authentication.ps1` | Confirms missing and invalid tokens are rejected while a valid token reaches the orchestrator application. |
| `10-Test-Synthesizer.ps1` | Submits the synthesizer workflow and retains its artifact even when the frozen baseline fails at the shared handoff boundary. |
| `11-Validate-Synthesizer-Artifact.ps1` | Compares graph topology with the pandapower representation; a failure is a semantic data-quality finding. |
| `20-Test-Benchmark.ps1` | Submits the benchmark workflow and retains the benchmark artifact and metadata for review. |
| `21-Validate-Benchmark-Artifact.ps1` | Parses the benchmark result and inventories episodes, backend and populated KPI leaves. |
| `22-Test-Invalid-Algorithm.ps1` | Sends an invalid algorithm template and verifies safe rejection without an output artifact. |
| `29-Prepare-HAI-Simulator.ps1` | Verifies or prepares the local PowerGrid simulator image needed by the HAI tests. |
| `30-Attempt-HAI-Startup.ps1` | Starts the supplied HAI deployment and records container readiness and any startup blocker. |
| `31-Test-HAI-Slot-Capacity.ps1` | Opens two sessions and confirms that a third request is safely refused at the configured two-slot limit. |
| `32-Test-HAI-Timeout-Reclaim.ps1` | Checks whether expired sessions release their slots. The validated baseline reproduces a timeout-reclaim defect. |
| `33-Clear-HAI-Test-Sessions.ps1` | Performs controlled cleanup of test-created HAI sessions so later tests start from known free slots. |
| `34-Test-HAI-Signed-Proxy-Link.ps1` | Confirms that a valid signed GUI link works and a tampered signature is rejected. |
| `35-Test-HAI-Technical-Lifecycle.ps1` | Exercises trace submission, survey submission, completion, artifact content and slot release using a technical fixture. It is not a human study. |
| `36-Test-HAI-Restart-And-Rerun.ps1` | Restarts the HAI control service, checks active-session persistence and starts a fresh session after controlled cleanup. |
| `40-Check-Studio-Manifest.ps1` | Records whether the supplied Solution Studio blueprint has the required service-declaration shape. This is supplementary evidence. |
| `50-Measure-Dutch-Reference.ps1` | Repeats synthesizer and benchmark runs and records timing/resource references. It does not establish scalability. |
| `51-Record-HAI-UX-Review.ps1` | Guides a named reviewer through a structured expert heuristic review of the live HAI interface. It is not a participant study. |

Every script writes timestamped evidence under the configured evidence root. Preserve the full folder, including results that report a defect or blocker.

