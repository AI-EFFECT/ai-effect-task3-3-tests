# Release notes

## Version 1.2 - validated closure extension

Validated on 8 September 2026 against frozen AI-EFFECT commit `486ccc702bb2afca79fb7d31258d62ee0f94dbfc` and the recorded supplied external TEF fixture.

Added:

- `23-Test-Repeatability-And-Performance.ps1`
- `24-Test-Restart-And-Rerun.ps1`
- `25-Test-Bounded-Concurrency.ps1`
- `TEST-RESULTS-SUMMARY.md`

Recorded closure results:

- Three of three integrated workflows completed with stable 1,000-row, 10-column output structure; mean harness-observed duration was 18.864 seconds.
- Four TEF containers recovered in 38.828 seconds, retained named volumes and completed a post-restart workflow.
- Two overlapping workflows completed with no incomplete tasks and 1,000 output rows each.
- The legacy-sidecar path remains blocked by the confirmed gRPC `50051` versus HTTP `600` mismatch.

Documentation now places close-out inventory before shutdown and explicitly separates T3.3 closure references from T3.4 scalability, long-term monitoring and optimisation work.

## Version 1.1 - sidecar readiness correction

Script 31 waits up to 90 seconds for Data Provision's startup record before classifying the interface. This prevents an inconclusive early inspection from being mistaken for the validated gRPC/HTTP mismatch.

## Version 1.0 - initial Portugal handover

Initial integrated-route and conditional-sidecar reproduction suite. Earlier fixture mapping, healthcheck isolation and sidecar service-name mistakes were corrected before release and are not Portugal service defects.

See [KNOWN-FINDINGS.md](KNOWN-FINDINGS.md) for current findings.

