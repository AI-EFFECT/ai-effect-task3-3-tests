# German node — Task 3.3

## Use-case overview

The German use case evaluates data-pipeline orchestration and exchange through the supplied data provider, VILLASnode/chronics gateway components and output formatter. VILLASnode is the key interoperability dependency for the end-to-end route.

## What was tested

The package records the frozen source baseline and Docker configuration, checks orchestrator authentication, inspects the packaged generator input, validates workflow definitions, examines service-secret lifecycle behaviour and applies a strict VILLASnode closure gate. It also produces a close-out inventory suitable for review.

## Current conclusion

The German node has **conditional T3.3 closure**.

- Baseline, dependency-state, configuration and close-out evidence were captured.
- Authentication and non-VILLAS checks can be run independently.
- The exact Compose image `registry.git.rwth-aachen.de/acs/public/villas/node:hook-timeseries-chronix-conversion` was unavailable.
- The suite deliberately did not substitute another image, so no VILLAS-dependent end-to-end claim is made.
- The review also records a packaged-input issue and a persistent service-key lifecycle finding.

The blocked route can be closed later by rerunning the gate and dependent tests against the exact immutable VILLASnode runtime.

## Reading and running the package

- [Runbook and prerequisites](START-HERE.md)
- [Plain-language script guide](SCRIPT-GUIDE.md)
- [Reviewed test results](TEST-RESULTS-SUMMARY.md)
- [Catalog of blocked checks](BLOCKED-TEST-CATALOG.md)
- [Release notes](RELEASE-NOTES.md)
- [Shared developer notes](../DEVELOPER-NOTES.md)

Do not replace the official image when producing baseline evidence. A transparent blocked result is preferable to an unsupported end-to-end claim.

