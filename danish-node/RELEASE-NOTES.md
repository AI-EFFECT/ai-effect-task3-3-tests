# Danish node release notes

## v1.5 - 24 November 2026

- Script descriptions shortened to the same three-part form as the other node packages. The detail for each script remains in SCRIPT-GUIDE.md. No change to test behaviour.

## v1.4 - 24 November 2026 (documentation only)

- DK-REL-02: added the second effect, a workflow failing with "Task not complete", and the results of five executions.
- DK-LLM-01: extended to 15 runs; noted that the guessed `load_topology` has no effect with a single load, and that the settings which change the result are `allow_hx`, `max_extra_pipes` and `allow_bypass`.
- Results updated for the fourth full Windows execution.

## v1.3 - 24 November 2026

- Script 12 now runs the prompt over several rounds (default 5) and checks that settings the prompt does not mention stay at the service defaults. Earlier versions checked only the terminals, so they could pass runs with guessed settings.
- Added DK-LLM-01: the model guessed unmentioned settings in 5 of 5 Windows runs, and 1 run failed. Prompt workflow result changed from Pass to Defect confirmed.
- Overall position and T3.4 handover shortened to match the other nodes.
- Results and findings now cite the Windows runs only. DK-LLM-01 evidence extended to 10 runs, with the `allow_hx: false` cause confirmed.

## v1.2 - 24 November 2026 (documentation only)

- DK-VAL-01 widened: misspelt and lowercase terminal names are dropped, sometimes with no warning; nothing downstream reads `valid`. Live portal examples added.
- Added observations on ambiguous prompts, how Ollama is started and the timeout, and the baseline scope.
- DK-REL-02: recorded the planned fix within the WP3 orchestrator reliability work.
- T3.4 handover: Windows reference values, new and hosted-only services, hosted security and Ollama checks, prompt-route records.
- No script changes.

## v1.1 - 23 November 2026

- Windows fix: command output is now read as UTF-8 with replacement of unreadable characters. Windows Python defaults to cp1252, which crashed script 01 while reading Docker build output. The failed run is retained as evidence.
- Full suite confirmed on Windows (Docker Engine 29.9.3, Compose 5.7.1, Python 3.12.10), with settings read by Windows PowerShell. All verdicts matched the macOS run; DK-REL-02 occurred in 3 of 3 rounds.

## v1.0 - 23 November 2026

- Closure run on Docker (macOS, Docker Engine 29.8.2, Compose 5.5.1) for frozen commit `e8914565e966a2d78879c314f980574769d31b87`.
- Confirmed DK-SEC-01 and DK-REL-02 and recorded DK-VAL-01. Prompt workflow exercised with `qwen2.5:1.5b`.
- Runbook keys now generated as random temporary values, using the same method as the other node runbooks, and removed after the run.

## v0.1 - 23 November 2026 (pre-release)

- Added the Danish node package for frozen commit `e8914565e966a2d78879c314f980574769d31b87`.
- Python suite following the shared harness pattern: `Test-Settings.psd1` settings, `ORCHESTRATOR_API_KEY` and `SERVICE_API_KEY` environment variables, timestamped evidence folders with `run.txt`, structured summaries and the common `RESULT:` language.
- Scripts 00, 01, 02, 10, 11, 12, 20, 23, 24, 25 and 99, plus the frozen `chp_dumploads.json` fixture.
- Script 20 separates orchestrator-level rejection of unknown protocols from service-level rejection.
- Script 25 repeats the two-workflow overlap over several rounds, because the output exchange in DK-REL-02 is timing-dependent.
- Pre-release validation against native processes recorded DK-SEC-01, DK-REL-02 and DK-VAL-01.
