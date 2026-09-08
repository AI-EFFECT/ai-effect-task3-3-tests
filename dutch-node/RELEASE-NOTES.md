# Release Notes - v1.2

This release adds the final Dutch-node Task 3.3 closure checks validated on 8
September 2026 against source commit
`22fbb6eca71265a61bc1f0cee16b6d03f372d554`.

## Added

- `50-Measure-Dutch-Reference.ps1` repeats the released synthesizer and
  benchmark checks three times by default and records wall-clock duration plus
  container resource snapshots.
- Script 50 validates each child evidence folder, required artifacts and result
  marker. Child process exit code is retained as diagnostic metadata rather
  than used as the functional verdict.
- `51-Record-HAI-UX-Review.ps1` creates a labelled review session, copies its
  signed URL to the clipboard without recording the token, collects ten expert
  heuristic ratings and cleans the session.
- `TEST-RESULTS-SUMMARY.md` separates passes, defects, supplementary findings
  and T3.4 handover items.

## Validated closure results

- Three synthesizer runs produced complete evidence with mean harness duration
  `16.740 s` and range `16.683-16.796 s`.
- Three benchmark runs produced complete evidence with mean harness duration
  `16.828 s` and range `16.769-16.885 s`.
- These measurements include orchestration polling and artifact collection and
  are initial technical references only, not scalability results.
- The expert HAI review rated all ten areas, with mean `3.2/5`; entry/task
  clarity and error recovery received ratings of `2/5`.

## Findings retained

- Shared workflow logical-format/DataReference handoff failure.
- Synthesizer semantic-output loss in the pandapower representation.
- HAI timeout-reclaim failure, despite correct cleanup after normal completion.
- Repeated synthesizer and benchmark runs reported stable task identifiers;
  investigate artifact isolation/overwrite behaviour before concurrent use.
- The UI/UX notes are an expert heuristic record, not participant evidence;
  brief or internally inconsistent comments require clarification in the formal
  deliverable narrative rather than retrospective alteration of raw evidence.

Superseded local harness attempts and credential-mismatch measurements are not
part of this release. Evidence, settings and credentials are not committed.

## Earlier release

Version 1.1 added the explicit PowerGrid simulator-image prerequisite and the
self-contained HAI startup path. Version 1.0 introduced the corrected artifact
validator and advanced HAI capacity, security, lifecycle and restart checks.

## Documentation and handover pass — 2026-09-08

- Added a node-level `README.md` with a plain-language use-case overview, tested scope, current conclusion and documentation map.
- Added `SCRIPT-GUIDE.md` covering every PowerShell file in this node package.
- Added PowerShell comment-based help to every script and helper in this folder.
- Clarified defect, blocked-test and Task 3.4 boundaries for teammates and reviewers.
- No executable test statements, acceptance criteria or recorded T3.3 conclusions were changed in this pass.
- A follow-up developer-readability pass added section comments to complex helper and control-flow scripts; executable statements remain unchanged.
