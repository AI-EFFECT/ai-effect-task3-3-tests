# Supplementary Task 3.3 tests

This package closes the Task 3.3 elements that the September 2026 closure runs did not cover for the German, Dutch and Portuguese nodes. It adds security, restoration and reboot, third-party AI exchange and user-interface tests. The proposal lists all four under Task 3.3; the earlier suites tested functionality and recorded initial references.

[TEST-CATALOGUE.md](TEST-CATALOGUE.md) lists every test, its acceptance criterion and the elements that still depend on partners (MIMs, VILLASnode and the Portuguese sidecar).

## How it differs from the node suites

- **Cross-node.** One harness runs the same checks against the platform core and each node, so results can be compared across nodes. Containers, ports and volumes are discovered from each node's Compose files at run time.
- **A stand-in third-party vendor.** Scripts 20 and 30 build an independent two-service AI provider from the platform's own templates and common library at the frozen commit, onboard it with the platform's export generator and pass real node outputs to it. Because the vendor uses the concurrent template unchanged, script 31 also checks whether the Danish task-ID finding (DK-REL-02) affects every service built from that template.
- **Controlled restarts.** Restart tests run against the vendor pipeline, whose model step can be held for a set time, so each restart is known to happen while a task is running.
- **One extra result label.** `ERROR` marks a harness failure, so it can never be counted as a defect.

## Reading and running the package

- [Runbook and prerequisites](START-HERE.md)
- [Test catalogue and acceptance criteria](TEST-CATALOGUE.md)
- [Script guide](SCRIPT-GUIDE.md)
- [UX evaluation protocol](UX-EVALUATION-PROTOCOL.md)
- [Release notes](RELEASE-NOTES.md)
- [Shared developer notes](../DEVELOPER-NOTES.md)

## Current status

Version 0.1, not yet executed. The scripts pass the Windows PowerShell 5.1 parser. The vendor services were exercised in memory against the platform's template handlers: the authentication probe gives 401 for missing and invalid tokens and 422 for a valid one, and invalid inputs fail explicitly. A first full run on the frozen baselines is required before any result is reported.
