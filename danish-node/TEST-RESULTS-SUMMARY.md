# Danish Node Task 3.3 - Validated Results Summary

## Baseline

- Source: `https://github.com/AI-EFFECT/ai-effect-wp3.git`, folder `use-cases/denmark-node`
- Commit: `e8914565e966a2d78879c314f980574769d31b87`
- Fixture: `fixtures/chp_dumploads.json`, SHA-256 `FB5B7053BD8DFFCBD8398EA664CA5C79D742DA899C71A89051B0994CDA5542F4`
- Ollama model: `qwen2.5:1.5b`
- Environment: Windows, Docker Engine 29.9.3, Compose 5.7.1, Python 3.12.10, settings read by Windows PowerShell
- Closure execution: 23 and 24 November 2026, full suite run four times

## Results

| Area | Result | Evidence-based conclusion |
|---|---|---|
| Preflight | Pass | Frozen source clean; Docker, Compose, paths and keys recorded. |
| Startup and export | Pass | Orchestrator and three Danish services became healthy; all `/health` endpoints returned `200`; workflow export generated; Ollama model present. |
| Authentication | Defect confirmed | Orchestrator returned `401` for missing and invalid tokens and reached the application (`404`) with the valid token. All three Danish control endpoints returned `404` instead of `401` without a valid token (DK-SEC-01). |
| Structured workflow | Pass | BuildRunConfig, GenerateTopology and RenderTopologies completed; all outputs retained on the shared volume. |
| Output validation | Pass | Request reflected with no warnings; 20 candidate topologies, all using the requested supplies and loads; the recommended network among them; 20 valid SVG drawings; every output in the workflow's own folder. |
| Prompt workflow | Defect confirmed | The same prompt was run 15 times. When converting the prompt to JSON, the model added settings the prompt did not mention in 15 of 15 runs, so the service defaults were never used. In 1 run it set `allow_hx: false`; with no heat exchanger no topology connects the requested terminals, and the workflow failed with "no feasible topology found" (DK-LLM-01). The terminals were correct in every run, twice only through the default fallback. The LLM step took about 6 to 11 s in the runs where it was timed. |
| Invalid input | Pass with observation | Non-object input, missing file and service-unsupported protocol failed explicitly with no output; an unknown protocol was refused at submission with HTTP `400`. Empty and unrecognised terminals completed with default terminals and `valid: true` (DK-VAL-01). Follow-up checks showed misspelt names are also dropped, sometimes with no warning. |
| Repeatability/reference | Pass | Three runs per execution completed with identical candidate networks. Mean durations 8.5, 10.7, 14.0 and 9.9 s across the four executions, including resource sampling; the first run was slowest. |
| Restart and rerun | Pass | Three Danish containers recovered in 5.2 to 5.5 s; the earlier output was retained unchanged; a new workflow completed with valid outputs. |
| Bounded concurrency | Defect confirmed | Across five executions, two overlapping workflows returned each other's outputs in 3, 1, 3, 3 and 1 of 3 rounds while reporting completion. In one execution, one workflow per round failed instead in 2 of 3 rounds with "Task not complete". Identical task IDs were used across all workflows (DK-REL-02). |
| Close-out | Pass | Baseline, fixture hash, export metadata, runtime inventory and an index of evidence folders saved. |

## Overall Task 3.3 position

The Danish node demonstrates orchestrator authentication, a correct structured workflow, safe rejection of malformed input, repeatable output and restart recovery with data retained. It is not ready for an unqualified end-to-end claim because unauthenticated service access, output exchange between overlapping workflows, silent fallback to default terminals and guessed settings on the prompt route remain.

The evidence does not establish production performance, capacity limits, the Danish web UI, or services added after the frozen commit or deployed only on the hosted platform.

## T3.4 handover

- A fix for DK-REL-02 is in progress as part of the WP3 orchestrator reliability work; rerun script 25 before any parallel or load measurement.
- Treat the 8.5-second mean, 5.3-second recovery and 10.3-second LLM step (Windows) as initial references only.
- Measure structured and prompt workloads separately; the prompt route adds non-deterministic LLM time and guessed settings (DK-LLM-01).
- Separate cold image build and model download, queueing, service execution and polling time; tasks expose only `created_at` and `updated_at`.
- Sample resources without slowing the timed workflow, and keep the script 11 output checks alongside every timing run.
- On the hosted platform, check service authentication (DK-SEC-01), Ollama availability and services added after the frozen commit.
- Use prompts with non-default terminals and record each request and its extracted settings, so fallbacks (DK-VAL-01) and guesses (DK-LLM-01) can be detected.
