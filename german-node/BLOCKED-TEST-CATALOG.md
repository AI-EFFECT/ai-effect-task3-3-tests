# Blocked Test Catalogue

The following checks remain part of the Germany Task 3.3 scope but cannot be repeated on the frozen baseline until the German/VILLAS owner provides a retrievable immutable VILLASnode image or an unchanged documented build route.

| Test area | Earlier baseline finding | Release condition |
|---|---|---|
| End-to-end workflow | Workflow completion could conceal incomplete output | Exact VILLAS runtime available |
| Chronics output quality | Header-only production files and incomplete outputs could be accepted | Node confirms semantic output contract |
| Repeat and recovery | VILLAS restart could hang after a run | Exact runtime available |
| Concurrent workflows | Shared lifecycle and task-ID isolation risk | Exact runtime plus defined concurrency model |
| Formatter negative fixture | Header-only/partial output was accepted on the old baseline | Confirmed service fixture contract |
| VILLAS network and privilege review | Broad internal control-plane exposure and privileged deployment were observed | Running VILLAS container |
| Resource sample | Earlier sample was operational only | A valid end-to-end workload |

When the release condition is met, create a separate regression package and record the new source, image digest, configuration, and evidence. Do not overwrite the 2 September 2026 baseline evidence.
