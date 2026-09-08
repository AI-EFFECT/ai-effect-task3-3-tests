# AI-EFFECT Task 3.3 test suites

This repository contains the repeatable test packages used to assess the German, Dutch and Portuguese AI-EFFECT nodes for Task 3.3. It is written for two audiences: teammates who need a quick picture of what was tested, and testers who need to reproduce the work and preserve evidence.

## What Task 3.3 covered

Task 3.3 checked whether the node software was ready for later TEF end-to-end validation. The suites therefore look at:

- core functionality and workflow orchestration;
- data and interface compatibility;
- authentication, access controls and safe failure behaviour;
- basic repeatability, efficiency and bounded-concurrency observations;
- restart, recovery and rerun behaviour; and
- the technical user experience where a user-facing interface exists.

The repository records passes, defects and blocked tests. A blocked test is useful evidence: it shows exactly which supplied dependency or interface prevented the test, without silently replacing the official baseline.

## Use cases at a glance

| Node | Use cases tested | Overall T3.3 position |
|---|---|---|
| [German node](german-node/README.md) | Orchestration and data exchange through the German data-provider, VILLASnode/chronics and output-formatting chain. | **Conditional closure.** Baseline, configuration, authentication and security checks were completed. The exact supplied VILLASnode image was unavailable, so VILLAS-dependent end-to-end execution remains blocked. |
| [Dutch node](dutch-node/README.md) | Synthetic power-grid data, AI benchmarking and Human–AI Interaction (HAI) session services. | **Conditional closure.** Most service-level and HAI controls worked, but shared handoff, synthesizer topology and HAI timeout-reclaim defects remain. |
| [Portuguese node](portugal-node/README.md) | A wind-energy pipeline covering data generation, loading, feature engineering and model training, plus the legacy sidecar integration route. | **Conditional closure.** The integrated four-stage workflow, restart/rerun and bounded-concurrency checks passed. The legacy sidecar route remains blocked by the supplied gRPC/HTTP interface mismatch. |

## Where to begin

Each node folder uses the same documentation pattern:

1. `README.md` — plain-language overview and current conclusion.
2. `START-HERE.md` — prerequisites, local paths and the exact run order.
3. `SCRIPT-GUIDE.md` — one-line purpose and interpretation for every script.
4. `TEST-RESULTS-SUMMARY.md` — reviewed findings and evidence references.
5. `RELEASE-NOTES.md` — package history and changes.
6. [`DEVELOPER-NOTES.md`](DEVELOPER-NOTES.md) — shared harness conventions, evidence rules and safe-change guidance.

Clone the repository, choose one node and follow its `START-HERE.md`. The suites are independent; do not mix settings or scripts between nodes.

```powershell
Set-Location C:\T33
git clone https://github.com/adarshsunil/ai-effect-task3-3-tests.git
```

## How to read the results

| Label | Meaning |
|---|---|
| `PASS` | The stated acceptance criteria were met for the frozen test baseline. |
| `DEFECT CONFIRMED` or `FAIL` | The test ran and reproduced a specific problem. Keep the evidence. |
| `BLOCKED` | A prerequisite or supplied interface prevented execution. This is not a pass or an untested omission. |
| `RECORDED` or `FINDINGS RECORDED` | Useful observations were captured, but the script deliberately makes no broader conformance claim. |

## Boundary with Task 3.4

Short timing runs and small concurrency checks in this repository establish reproducible technical references for Task 3.3. They are **not** scalability limits, long-term monitoring results, production service levels or Task 3.4 conclusions. Task 3.4 should reuse these workloads and evidence formats under controlled load levels and over the planned monitoring period.

## Safe use

- Use the exact source revision and local layout stated in the node runbook.
- Preserve evidence from failed and blocked runs as well as passes.
- Do not commit API keys, Docker credentials, local settings, evidence folders or participant data.
- Do not substitute unavailable images or change source fixtures when making an official baseline claim.

