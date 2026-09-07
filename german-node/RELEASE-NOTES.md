# Release Notes - v2.1

This release adds the Germany-node dependency closure gate executed against the
frozen AI-EFFECT baseline
`486ccc702bb2afca79fb7d31258d62ee0f94dbfc` on 7 September 2026.

## Added

- `60-Check-VILLAS-Closure-Gate.ps1` resolves the image from the actual
  `villas-node` Compose service.
- It records the selected service/image pair, checks local availability without
  pulling an image, and writes a timestamped `BLOCKED`, `READY_NOT_RUNNING` or
  `READY` result.
- It keeps full expanded Compose configuration in memory so temporary service
  keys are not written to evidence.

## Recorded result

The configured VILLASnode image was unavailable both from the supplied registry
reference and from the local Docker image store. The result is `BLOCKED`. The
orchestrator and the three German adapter services remain separately testable.

## Boundary

The release does not include or claim a VILLAS-dependent end-to-end,
performance, recovery or concurrency result. Those checks require the exact
owner-approved VILLASnode runtime. Only the final exercised closure-gate script
is included; superseded local harness drafts are not part of this release.

