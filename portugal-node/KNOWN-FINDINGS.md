# Portugal node: known findings

These findings apply to frozen AI-EFFECT commit `486ccc702bb2afca79fb7d31258d62ee0f94dbfc` and the supplied external TEF fixture used in the 8 September 2026 closure run.

| ID | Finding | Validated evidence | Impact | Recommended owner action |
|---|---|---|---|---|
| PT-CFG-01 | Knowledge Store's supplied Compose healthcheck uses `curl` on `/`; the image has no `curl` and the service health endpoint is `/health`. | Script 03: `/` returned `404`; `/health`, `/docs` and `/openapi.json` returned `200`; `curl` was absent. | Supplied Compose can classify an available application as unhealthy. | Use a command present in the image and call `/health`. |
| PT-CFG-02 | Synthetic Data's supplied healthcheck calls undefined `/`. | Script 04: `/` and `/health` returned `404`; `/docs`, `/openapi.json` and `/models` returned `200`. | Supplied Compose can classify an available API as unhealthy. | Use a documented endpoint or add a dedicated health endpoint. |
| PT-SC-01 | Legacy Data Provision runs gRPC on `50051`, while the supplied sidecar expects HTTP on `600`. | Script 31 recorded the running service, gRPC startup log and effective sidecar configuration. | Legacy-sidecar workflow cannot be exercised as supplied; integrated route is unaffected. | Supply an approved gRPC-aware adapter or compatible official deployment configuration. |

## Recorded observations, not confirmed defects

- Three repeated integrated runs completed with 1,000 rows and 10 columns each. Their generated-data hashes differed. Synthetic variation is expected, but deterministic reproducibility was not established because the workflow had no asserted fixed-seed contract.
- Four TEF containers recovered in 38.828 seconds and a new workflow completed. No recovery-time requirement was defined, so this is a reference value rather than an SLA pass.
- Two overlapping workflows completed with 1,000-row outputs. This is a bounded concurrency smoke test, not a measured capacity limit.
- The large Synthetic Data image downloaded and resolved substantial ML dependencies during builds. Build optimisation and dependency pinning should be evaluated in T3.4; no build-performance acceptance threshold existed in T3.3.

## Test-package corrections

An early feature-engineering fixture omitted the explicit `datetime` to `timestamp` rename, and an early sidecar check inspected the service before its gRPC startup record. Both harness issues were corrected before the validated closure run and are not Portugal-node defects.

