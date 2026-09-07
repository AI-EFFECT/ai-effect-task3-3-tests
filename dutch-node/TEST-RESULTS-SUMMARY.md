# Dutch Node Task 3.3 - Validated Results Summary

## Baseline

- Source: `https://github.com/paulban/ai-effect-wp3.git`
- Commit: `22fbb6eca71265a61bc1f0cee16b6d03f372d554`
- Submodules: pinned and clean
- Environment: Windows PowerShell 5.1, Docker Engine 28.5.1 and Compose 2.40.0
- Closure execution: 7-8 September 2026

## Results

| Area | Result | Evidence-based conclusion |
|---|---|---|
| Core startup | Pass | Orchestrator, three workers, Redis, synthesizer and benchmark started; service containers became healthy. |
| Authentication | Pass | Missing and invalid tokens returned `401`; the valid token reached the application. |
| Synthesizer workflow | Fail | Service artifact was retained, but the workflow failed at the common logical-format/DataReference boundary. |
| Synthesizer artifact | Fail | Graph had 213 edges; pandapower contained zero lines and zero transformers. |
| Benchmark workflow | Fail | Service executed and retained output, but the shared BenchmarkResult handoff failed. |
| Benchmark artifact | Pass | One episode, `grid2evaluate` backend and 16 populated KPI leaves were recorded. |
| Invalid algorithm | Pass with API observation | Input was rejected and no artifact was created; HTTP `200` carried an application-level failed status. |
| HAI startup | Pass | Required images and two-slot runtime started; proxy and service became healthy. |
| HAI capacity | Pass | Two sessions admitted; third safely refused at configured capacity. |
| HAI timeout/reclaim | Fail | Two 30-second sessions remained running after 50 seconds and blocked a replacement. |
| Signed proxy link | Pass | Valid link reached GUI with `200`; altered token returned `403`. |
| HAI technical lifecycle | Pass | Trace and survey accepted, output completed and both slots were released. |
| HAI service restart | Pass | Active session state and signed access survived control-service restart; clean rerun started. |
| Studio manifest | Supplementary fail | Blueprint is pipeline topology, not a service declaration; no replacement was fabricated. |
| Initial timing reference | Pass, non-scalability | Three complete runs per workload produced stable harness-level timings and resource snapshots. |
| Expert HAI UI/UX review | Findings recorded | Ten areas rated; mean 3.2/5, with low ratings for entry/task clarity and error recovery. |

## Overall Task 3.3 position

The Dutch node demonstrates service-level computation, authentication, retained
benchmark quality, bounded HAI admission, signed-link integrity, normal-session
completion and control-service restart resilience. It is not ready for an
unqualified end-to-end claim because shared handoff, synthesizer semantic-output
and timeout-reclaim defects remain.

## T3.4 handover

- Treat script-50 results only as initial harness-level reference values.
- Establish controlled workload, warm-up, repetition and resource-isolation
  conditions before defining a performance baseline.
- Measure service execution separately from polling and artifact collection.
- Monitor timeout frequency, reclaim latency, occupied-slot duration and
  effective capacity loss.
- Test increasing slot counts and concurrent workflow identities only after
  task/artifact isolation is confirmed.
- Track data/model-quality indicators separately from infrastructure metrics.

