# Blocked Test Catalogue

The following checks remain part of the Germany Task 3.3 scope but cannot be
repeated on the frozen baseline until the German/VILLAS owner provides a
retrievable immutable VILLASnode image or an unchanged documented build route.

## Closure-gate confirmation - 7 September 2026

The v2.1 closure run resolved the image from the Compose service explicitly
named `villas-node`. Its configured image is:

```text
registry.git.rwth-aachen.de/acs/public/villas/node:hook-timeseries-chronix-conversion
```

The registry returned `not found`, and that exact reference was not available
in the local Docker image store. No substitute image, source modification or
test-only wrapper was used. The locally built
`germany-node-villas-chronics:latest` image belongs to the adapter service and
is not the missing VILLASnode runtime.

| Test area | Earlier baseline finding | Release condition |
|---|---|---|
| End-to-end workflow | Workflow completion could conceal incomplete output | Exact VILLAS runtime available |
| Chronics output quality | Header-only production files and incomplete outputs could be accepted | Exact runtime plus confirmed semantic output contract |
| Repeat and recovery | VILLAS restart could hang after a run | Exact runtime plus owner-approved recovery rule |
| Concurrent workflows | Shared lifecycle and task-ID isolation risk | Exact runtime plus defined concurrency model |
| Formatter negative fixture | Header-only or partial output was accepted on the old baseline | Confirmed service fixture contract |
| VILLAS network and privilege review | Broad internal control-plane exposure and privileged deployment were observed | Running exact VILLAS container |
| Resource and timing reference | Earlier sample was operational only and used a ten-row workload | Valid E2E workload and exact runtime |

When the release condition is met, create a separate regression package and
record the new source revision, image digest, configuration and evidence. Do
not overwrite the September 2026 baseline evidence.

