# Release notes

## Version 1.1 — sidecar readiness correction

This release corrects the sidecar compatibility check. Version 1.0 could inspect Data Provision while its container was still starting, before the gRPC startup record was available. Script `31-Start-Sidecar-Services.ps1` now waits for the service's startup record for up to 90 seconds and reports an inconclusive result only if it cannot observe the interface.

No Portugal source, integration overlay, or test finding was changed.

## Version 1.0 — initial Portugal handover

This release replaces every earlier Portugal test-package draft.

It contains the test sequence that produced the recorded final evidence on 4 September 2026. The integrated route completed successfully. The legacy-sidecar route was assessed separately and is deliberately stopped at the documented interface mismatch.

The following earlier package issues were corrected before this final release:

1. A Feature Engineering fixture initially used `datetime`. The service correctly requires `timestamp`. The final package makes the same explicit column mapping used in the completed workflow.
2. The test-only health checks are scoped to disposable workspaces. They use live endpoints only to permit functional testing after the supplied health-check findings have been recorded.
3. The sidecar workspace uses its own Compose service names. The final compatibility check does not attempt to start adapters when the underlying protocol mismatch is present.

These were test-package corrections. They are not Portugal service defects.

See [KNOWN-FINDINGS.md](KNOWN-FINDINGS.md) for the current configuration and integration findings.
