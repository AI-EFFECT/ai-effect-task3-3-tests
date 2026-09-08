# Portugal Node Task 3.3 - Validated Results Summary

## Baseline

- AI-EFFECT source commit: `486ccc702bb2afca79fb7d31258d62ee0f94dbfc`
- External TEF source commit observed: `7ba677f7f0a93b5ed6126e43a0b7b0e30f59d6b3`
- Fixture: 46,993 rows; SHA-256 `6B44C90A7378F9A69AE3FEC4C197078010AA5C21A8B8AEB2E9E4D7C2AFDFDFCD`
- Environment: Windows PowerShell, Docker Engine 28.5.1 and Compose 2.40.0
- Closure execution: 8 September 2026

The external TEF working tree contained the supplied integration changes. The suite copied and fingerprinted that fixture into marked disposable workspaces; it did not clean, reset, commit or modify the source.

## Results

| Area | Result | Evidence-based conclusion |
|---|---|---|
| Fixture preparation | Pass | Integrated and sidecar workspaces used the same 46,993-row fixture and hash. |
| Integrated startup | Pass | Orchestrator, Redis, ClickHouse, Data Provision, Knowledge Store and Synthetic Data started; required services became ready. |
| Authentication | Pass | Missing and invalid tokens returned `401`; a valid token reached the application and returned the expected resource-level `404`. |
| Knowledge Store healthcheck | Defect confirmed | Supplied check used unavailable `curl` and wrong `/` endpoint; live `/health` returned `200`. |
| Synthetic Data healthcheck | Defect confirmed | Supplied check used undefined `/`; documented API endpoints returned `200`. |
| Data load | Pass | 1,000 rows returned through an HTTP CSV reference with the expected source fields. |
| Feature engineering | Pass | `datetime` was renamed to `timestamp`; original variables were retained and `hour` was added. |
| Integrated workflow | Pass | GenerateData, ExecuteQuery, ApplyFunction and TrainModel all completed. |
| Invalid input | Pass | Missing file produced explicit failed status and error with no output reference. |
| Repeatability/reference | Pass | Three workflows completed; each returned 1,000 rows and 10 columns. Durations: 18.342-19.390 s; mean 18.864 s. |
| Restart and rerun | Pass | Four TEF containers recovered in 38.828 s; named volumes were retained and a new workflow completed. |
| Bounded concurrency | Pass | Two overlapping workflows completed in 5.240 s and 13.374 s, with zero incomplete tasks and 1,000 rows each. |
| Legacy-sidecar interoperability | Blocked as supplied | gRPC `50051` service is incompatible with sidecar's HTTP `600` expectation; script 32 was correctly not run. |
| Close-out and shutdown | Pass | Baseline, fixture hash, manifests and active runtime inventory were saved; test containers were then stopped. |

## Overall Task 3.3 position

The Portugal integrated route has a defensible functional closure for the tested baseline. It demonstrates authenticated orchestration, cross-service HTTP data exchange, basic semantic transformation, complete four-stage execution, safe invalid-input handling, repeated execution, container restart/rerun and bounded two-workflow concurrency.

Closure remains conditional because the supplied legacy-sidecar path is incompatible and cannot support an external-system interoperability claim. The evidence also does not establish model scientific suitability, deterministic output reproducibility, host-reboot or backup restoration, security penetration resistance, production performance, capacity limits or scalability.

## T3.4 handover

- Treat the 18.864-second mean, 38.828-second recovery and two-workflow result as initial references only.
- Separate cold image build, warm service startup, workflow queueing, service execution, polling and artifact-transfer time.
- Pin and inventory large ML dependencies; assess Docker cache reuse and image size.
- Define controlled workload sizes, warm-up rules, repetition count, resource isolation and percentile metrics.
- Add deterministic-seed/model-quality contracts where reproducibility is required.
- Monitor CPU, memory, I/O, queue time, failure rate, recovery time and data/model-quality indicators.
- Resolve PT-SC-01 and rerun the functional sidecar regression before measuring its scalability.

