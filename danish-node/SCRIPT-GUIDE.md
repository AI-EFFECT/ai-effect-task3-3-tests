# Danish node script guide

| Script | Purpose and interpretation |
|---|---|
| `_support.py` | Shared library for settings, evidence, HTTP, orchestrator and container helpers. Do not run directly. |
| `00_preflight.py` | Records frozen source, Docker, Compose, required paths and keys. `BLOCKED` lists what to fix. |
| `01_start_services.py` | Starts the supplied orchestrator and Danish stacks, prepares the Ollama model and generates the workflow export. Startup times are cold-start references only. |
| `02_test_authentication.py` | Orchestrator must return `401` for missing and invalid tokens and reach the application with the valid token. Danish control endpoints are probed directly; any answer other than `401` is `DEFECT CONFIRMED`. |
| `10_test_workflow.py` | Runs the frozen structured request through all three steps and retains every output. A completed status alone is not a semantic pass; run script 11. |
| `11_validate_outputs.py` | Checks the newest script 10 evidence: request reflected without warnings, valid candidate topologies, one drawing per topology, real SVG files and outputs belonging to the same workflow. |
| `12_test_prompt_workflow.py` | Sends the same free-text request through Ollama over several rounds (default 5). Checks the extracted terminals, the warnings and that unmentioned settings stay at the service defaults. `DEFECT CONFIRMED` means the model guessed settings or a workflow failed; results are counted across rounds because LLM output is not deterministic. |
| `20_test_invalid_input.py` | Malformed, missing and unsupported inputs must fail explicitly with no output. Empty and unrecognised terminals are recorded as observations. |
| `23_test_repeatability.py` | Repeats the structured workload 2 to 5 times and records durations, output structure, hashes and container resources. Not load testing. |
| `24_test_restart_and_rerun.py` | Restarts the three Danish containers between runs and checks recovery time, volume retention and a valid rerun. Does not cover a restart during a run. |
| `25_test_bounded_concurrency.py` | Runs two overlapping workflows over several rounds and checks each output belongs to its own workflow. `DEFECT CONFIRMED` means outputs were exchanged between workflows. Not a capacity limit. |
| `99_collect_closeout.py` | Saves the baseline, fixture hash, export metadata, runtime inventory and an index of all evidence folders with their results. |
| `fixtures/chp_dumploads.json` | Frozen structured request, taken from the supplied `submit-workflow.sh`. Its SHA-256 is recorded by scripts 10, 23 and 99. |
