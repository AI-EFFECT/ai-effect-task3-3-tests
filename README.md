# AI-EFFECT Task 3.3 Test Suites

This repository contains repeatable Windows PowerShell test suites for the AI-EFFECT Task 3.3 use cases.

Each node folder is self-contained. It includes the test scripts, setup instructions, expected baseline results, and release notes needed to repeat the checks locally.

## Before you start

- This repository contains test automation only. It does not contain the node source code.
- Each suite states the exact source baseline and local folder layout it expects.
- Read the node's **START-HERE** guide before running any script.
- Do not commit API keys, local settings files, Docker credentials, evidence folders, or participant data.
- A failed test can be a known, documented finding. Read the node-specific release notes before recording it as a new issue.

## Node suites

| Node | Package status | Start here |
|---|---|---|
| Dutch node | Released | [Dutch-node guide](dutch-node/START-HERE.md) |
| German node | Released as a baseline evidence suite. VILLASnode-dependent end-to-end checks remain blocked by the unavailable supplied image. | [Germany-node guide](german-node/START-HERE.md) |
| Portugal node | Released as a conditional-closure evidence suite. The integrated route is validated; the legacy-sidecar route is blocked by the supplied gRPC/HTTP interface mismatch. | [Portugal-node guide](portugal-node/START-HERE.md) |
| Node 4 | Planned | — |

## Basic use

```powershell
Set-Location C:\T33
git clone https://github.com/adarshsunil/ai-effect-task3-3-tests.git
```

Then open the relevant node folder in VS Code and follow its **START-HERE.md** file exactly.

## Repository structure

```text
dutch-node/     Dutch-node Task 3.3 suite
german-node/    Germany-node Task 3.3 baseline evidence suite
portugal-node/  Portugal-node Task 3.3 reproduction suite
```

The suites are intentionally independent. Do not mix scripts or local settings from different nodes.
