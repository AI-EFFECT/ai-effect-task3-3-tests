# Dutch node — Task 3.3

## Use-case overview

The Dutch package covers three related services:

- **Data Synthesizer:** creates a synthetic power-grid data artifact.
- **Benchmarking:** executes an AI/grid benchmark and returns KPI results.
- **Human–AI Interaction (HAI):** manages a limited number of interactive operator sessions through signed proxy links.

A supplementary check also records whether the supplied Solution Studio blueprint has the expected import shape. That check is useful integration evidence but is not treated as a formal node acceptance test.

## What was tested

The suite checks service startup, orchestrator authentication, positive and negative workflows, artifact structure and semantics, HAI capacity and timeout handling, signed-link protection, lifecycle completion, restart/rerun behaviour, a short repeatability reference and an expert UI/UX review.

## Current conclusion

The Dutch node has **conditional T3.3 closure**.

- Startup, authentication, invalid-algorithm rejection and benchmark artifact validation passed.
- HAI two-slot admission, signed-link protection, technical completion and restart/rerun checks passed.
- The service generated synthesizer and benchmark artifacts, but the common orchestration handoff failed on the frozen baseline.
- The synthesizer artifact did not preserve graph topology in the pandapower representation.
- Timed-out HAI sessions did not automatically release their slots.
- The expert UI/UX review produced a mean score of 3.2/5; it was not a participant study.

The short timing data is an initial reference for later monitoring, not a Task 3.4 scalability result.

## Reading and running the package

- [Runbook and prerequisites](START-HERE.md)
- [Plain-language script guide](SCRIPT-GUIDE.md)
- [Reviewed test results](TEST-RESULTS-SUMMARY.md)
- [Detailed HAI tests](HAI-ADVANCED-TESTS.md)
- [Release notes](RELEASE-NOTES.md)
- [Shared developer notes](../DEVELOPER-NOTES.md)

Run the scripts only in the order documented in `START-HERE.md`, using the frozen source revision stated there.

