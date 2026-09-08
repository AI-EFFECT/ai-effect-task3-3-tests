# Portuguese node — Task 3.3

## Use-case overview

The Portuguese use case is a wind-energy data and AI pipeline with four stages:

1. generate or prepare data;
2. load the requested data;
3. apply feature engineering; and
4. train the model.

The package tests the integrated HTTP-based route and separately records the status of the older sidecar integration route.

## What was tested

The suite checks fixture preparation, service startup and health configuration, orchestrator authentication, data loading, feature engineering, the complete four-stage workflow, invalid input, repeatability, restart and rerun behaviour, two overlapping workflows, the legacy sidecar boundary and close-out evidence.

## Current conclusion

The Portuguese node has **conditional T3.3 closure**.

- Authentication, data loading, feature engineering and the complete integrated workflow passed.
- Three repeated workflows completed with a stable 1,000-row, 10-column output structure.
- The stack recovered in 38.828 seconds in the observed restart test and completed a fresh workflow.
- Two overlapping workflows completed; this was a bounded smoke test, not a capacity limit.
- Supplied health-check definitions for Knowledge Store and Synthetic Data were incorrect, although corrected test overrides confirmed that the services were responsive.
- The legacy sidecar route remains blocked because the supplied adapters expect gRPC on port 50051 while the services expose HTTP on port 600.

Different output hashes were expected from unseeded generation; the suite does not claim deterministic values. Timing and concurrency observations are initial references only, not Task 3.4 scalability results.

## Reading and running the package

- [Runbook and prerequisites](START-HERE.md)
- [Plain-language script guide](SCRIPT-GUIDE.md)
- [Reviewed test results](TEST-RESULTS-SUMMARY.md)
- [Known findings](KNOWN-FINDINGS.md)
- [Release notes](RELEASE-NOTES.md)

The external TEF source is copied into marked disposable workspaces. The test package does not silently modify the supplied source fixture.

