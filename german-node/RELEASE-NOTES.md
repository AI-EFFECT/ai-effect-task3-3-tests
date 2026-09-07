# Release Notes - v2.1

This release contains the Germany-node dependency closure gate validated on 7
September 2026 against frozen source commit
`486ccc702bb2afca79fb7d31258d62ee0f94dbfc`.

## Closure gate

- `60-Check-VILLAS-Closure-Gate.ps1` resolves the image from the actual
  `villas-node` Compose service.
- It checks local availability without pulling or substituting an image.
- It records a timestamped `BLOCKED`, `READY_NOT_RUNNING` or `READY` result.
- It keeps expanded Compose configuration in memory so temporary keys are not
  written to evidence.

The configured VILLASnode image was unavailable from the supplied registry and
absent from the local Docker image store. The validated result is `BLOCKED`.

## Documentation confirmation - 8 September 2026

- Added `TEST-RESULTS-SUMMARY.md` to consolidate available passes, confirmed
  defects, blocked checks and the T3.4 handover boundary.
- Refined `START-HERE.md` so the conditional-closure position and safe run order
  are explicit.
- The evidence verdict and package version remain unchanged; no additional
  Germany execution is claimed by this documentation update.

## Boundary

This release does not claim VILLAS-dependent end-to-end, output-quality,
performance, recovery, concurrency or runtime-security results. Those require
the exact owner-approved runtime. Superseded local gate drafts, evidence,
settings and credentials are not included.

