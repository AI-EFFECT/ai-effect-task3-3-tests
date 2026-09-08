# AI-EFFECT Task 3.3 Test Suites

This repository contains repeatable Windows PowerShell test suites for the
AI-EFFECT Task 3.3 use cases. Each node folder states its source baseline,
execution procedure, expected findings and evidence boundary.

## Before you start

- This repository contains test automation only; node source code is external.
- Use the exact source commit and local layout stated in the node guide.
- Run scripts in the documented order and preserve failed or blocked results.
- Do not commit API keys, local settings, Docker credentials, evidence folders
  or participant data.
- Short timing references are not Task 3.4 scalability or production results.

## Node suites

| Node | Package status | Start here | Results |
|---|---|---|---|
| Dutch node | Released as v1.2 reproduction and closure-reference suite. Core services run, but shared handoff, synthesizer semantic-output and HAI timeout-reclaim defects remain. | [Dutch guide](dutch-node/START-HERE.md) | [Dutch results](dutch-node/TEST-RESULTS-SUMMARY.md) |
| German node | Released as v2.1 baseline and closure-gate suite. The exact Compose VILLASnode image is unavailable, so VILLAS-dependent end-to-end checks remain blocked. | [German guide](german-node/START-HERE.md) | [German results](german-node/TEST-RESULTS-SUMMARY.md) |
| Portugal node | Released as v1.2 conditional-closure suite. The integrated four-stage route, restart/rerun and two-workflow concurrency checks pass; the legacy-sidecar route is blocked by the supplied gRPC/HTTP mismatch. | [Portugal guide](portugal-node/START-HERE.md) | [Portugal results](portugal-node/TEST-RESULTS-SUMMARY.md) |

## Basic use

```powershell
Set-Location C:\T33
git clone https://github.com/adarshsunil/ai-effect-task3-3-tests.git
```

Then open the relevant node folder and follow its `START-HERE.md` exactly.
The suites are independent; do not mix scripts or settings between nodes.

## Repository structure

```text
dutch-node/     Dutch reproduction and closure-reference suite
german-node/    German baseline and dependency closure-gate suite
portugal-node/  Portugal integrated and conditional-sidecar closure suite
```

