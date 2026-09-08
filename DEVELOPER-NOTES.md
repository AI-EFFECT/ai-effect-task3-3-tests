# Developer notes

This document explains how the Task 3.3 test packages are organised and how to change them without weakening the evidence trail. It complements the node runbooks; it is not a replacement for their exact commands and prerequisites.

## Test-harness pattern

Most executable scripts follow the same sequence:

1. Load the node's shared support file.
2. Read `Test-Settings.psd1` and verify the frozen source revision.
3. Check required secrets, files, containers and endpoints.
4. Create a timestamped evidence directory and start a transcript.
5. perform one clearly bounded test action;
6. save raw responses and a machine-readable summary; and
7. print a scoped result before stopping the transcript.

`_Support.ps1` and `HAI-Support.ps1` are libraries loaded by other scripts. They are not standalone tests.

## Settings and secrets

Each node provides `Test-Settings.psd1.example`. Copy it to `Test-Settings.psd1` and adapt only the local paths described in `START-HERE.md`. The real settings file is intentionally excluded from version control.

API keys are read from temporary environment variables. Scripts must never print, save or commit those values. Compose configuration may contain interpolated secrets, so save only the explicitly reviewed configuration extracts used by the suite.

## Evidence and verdicts

The timestamped evidence folder is part of the test result. Keep raw requests or responses, transcripts, container inventories and summary files together.

Do not infer the verdict from a process exit code alone. Some tests intentionally retain useful service artifacts after a known orchestration-boundary failure. Read the script's final `RESULT:` line and its structured summary in the context of the acceptance criteria documented for that test.

The common result language is:

- `PASS` — the stated acceptance criteria were met.
- `DEFECT CONFIRMED` or `FAIL` — execution reproduced a defined problem.
- `BLOCKED` — a prerequisite or supplied interface prevented the test.
- `RECORDED` or `FINDINGS RECORDED` — evidence was collected without a broader conformance claim.

Never convert a blocked result into a pass by replacing an official dependency, editing the source fixture or bypassing a compatibility gate.

## Frozen baselines

The suites verify exact source commits because results are meaningful only against known code and configuration. If a node revision changes:

1. create a new package version;
2. update the expected revision and release notes;
3. rerun affected tests; and
4. publish new evidence rather than reusing the earlier conclusion.

Comment-only edits do not change test logic, but they do change file hashes. Record such edits as documentation changes, as done in the node release notes.

## Adding or changing a test

A new test should have:

- a unique numeric prefix and evidence label;
- comment-based help explaining purpose and limits;
- explicit prerequisites and bounded timeouts;
- a clear acceptance condition and final result message;
- raw and structured evidence that does not expose secrets; and
- an entry in the node's `SCRIPT-GUIDE.md` and `RELEASE-NOTES.md`.

Keep tests reproducible and non-destructive. Any reset or cleanup operation must validate a test-owned marker or exact container/volume name before changing local state.

## T3.3 and T3.4

The repeatability, restart and small concurrency scripts provide starting workloads and evidence formats for Task 3.4. Their measurements remain Task 3.3 technical references. Capacity limits, sustained-load behaviour, long-term resource trends, production SLAs and optimisation conclusions require the controlled monitoring programme defined for Task 3.4.

