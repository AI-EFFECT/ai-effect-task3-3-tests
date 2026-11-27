# Supplementary script guide

| Script | Purpose and interpretation |
|---|---|
| `_Supplementary.ps1` | Shared library: settings, evidence, verdicts, Docker and Compose discovery, orchestrator and vendor helpers. Do not run directly. |
| `00-Preflight.ps1` | Records baselines, Docker, free disk space and key presence. `BLOCKED` lists core problems; `RECORDED` lists nodes that are not ready. |
| `10-Scan-Compose-Security.ps1` | Static review of the core and node Compose files (SEC-01 to SEC-04). `DEFECT CONFIRMED` when an authentication key defaults to empty. Starts nothing. |
| `11-Inspect-Runtime-Security.ps1` | Runtime review of running containers (SEC-03 to SEC-08): privileges, root users, digests, unauthenticated control endpoints and data stores, and stored service keys. Probes cannot start work. |
| `20-Prepare-Vendor-Pipeline.ps1` | Builds the stand-in third-party vendor from the platform templates, onboards it with the export generator, checks that it enforces its key and runs a smoke workflow (EXT-01). |
| `21-Test-Orchestrator-Restart-Midrun.ps1` | Restarts workers, the API or Redis while a vendor task runs (RES-01 to RES-03). A hang or lost record is `DEFECT CONFIRMED`; an explicit failure is `FINDINGS RECORDED`. |
| `22-Test-Orchestrator-State-Recreate.ps1` | Recreates the Redis container and checks whether a completed workflow is still retrievable (RES-04). Deletes orchestrator state held only in Redis. |
| `23-Test-Volume-Backup-Restore.ps1` | Backs up each node volume, restores it into a test-owned volume and compares manifests (RES-05). Stops the node during the backup unless `-Live`. |
| `24-Record-Before-Engine-Restart.ps1` | Records restart policies (RES-06), running containers, volume manifests and a reference workflow before a Docker Desktop restart. |
| `25-Verify-After-Engine-Restart.ps1` | Checks recovery after the restart against script 24's record (RES-07). |
| `30-Test-Vendor-Exchange.ps1` | Sends a node's workflow outputs to the vendor and compares SHA-256 and size with an independent read (EXT-02). `-NegativeCases` checks explicit rejection of invalid references (EXT-04). |
| `31-Test-Template-Concurrency.ps1` | Overlapping vendor workflows. Each is classed `ok`, `exchanged` or `failed`; a missing output is never counted as an exchange (EXT-03). |
| `40-New-UX-Evaluation-Forms.ps1` | Creates one evaluator's heuristic-evaluation forms for one interface (UX-01). |
| `41-Summarise-UX-Evaluation.ps1` | Validates and aggregates all forms; lists severity 3 and 4 problems (UX-02). |
| `99-Collect-Closeout.ps1` | Saves baselines, the runtime inventory with image digests and an index of evidence folders with their results. |
| `vendor/` | Vendor source: connections, Compose file, protos and service code. Template handlers and the common library are copied from the frozen platform by script 20. |
