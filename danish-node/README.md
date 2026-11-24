# Danish node: Task 3.3

## Use-case overview

The Danish package covers the configuration and topology pipeline for district-heating networks on the embedded SYSLAB model:

- **Config Assistant (`BuildRunConfig`):** turns a structured request or a free-text prompt into a normalised run configuration. Free text is parsed by a local Ollama model.
- **Topology Generator (`GenerateTopology`):** enumerates feasible SYSLAB network topologies and recommends one.
- **Draw Topology (`RenderTopologies`):** renders each candidate topology as an SVG for review.

The three services exchange payloads as JSON files on the shared Docker volume `denmark-node-data`; the orchestrator only forwards file references. The `web_ui` and Ollama containers are auxiliary and are not orchestrator nodes.

Unlike the other node packages, this suite is written in Python. It follows the same harness pattern, settings file format, environment variables, evidence layout and result language as the PowerShell suites (see [DEVELOPER-NOTES.md](../DEVELOPER-NOTES.md)).

## What is tested

The suite checks preflight and startup, orchestrator and service authentication, the structured workflow end to end, the meaning of its outputs, the free-text prompt route, invalid and incomplete input, repeatability, restart and rerun, bounded two-workflow concurrency and close-out evidence.

## Current conclusion

The Danish node has **conditional T3.3 closure**.

- Startup, orchestrator authentication, the structured workflow, output validation, invalid-input rejection, repeatability and restart/rerun passed.
- **Danish control endpoints accept unauthenticated calls as supplied** (DK-SEC-01).
- **Overlapping workflows can silently return each other's outputs, or fail**, because task IDs repeat across workflows (DK-REL-02).
- Empty, unrecognised or misspelt terminals are dropped or replaced by defaults while still reported as valid (DK-VAL-01).
- **On the prompt route, the model guesses settings the user did not mention**, so the same request can give different results or fail (DK-LLM-01).

The suite was run in full on Windows, four times, with matching verdicts. Services added to the Danish node after commit `e8914565e966a2d78879c314f980574769d31b87`, or deployed only on the hosted platform, are outside this baseline. The short timing data is an initial reference for later monitoring, not a Task 3.4 scalability result.

## Reading and running the package

- [Runbook and prerequisites](START-HERE.md)
- [Plain-language script guide](SCRIPT-GUIDE.md)
- [Reviewed test results](TEST-RESULTS-SUMMARY.md)
- [Known findings](KNOWN-FINDINGS.md)
- [Release notes](RELEASE-NOTES.md)
- [Shared developer notes](../DEVELOPER-NOTES.md)

Run the scripts only in the order documented in `START-HERE.md`, using the frozen source revision stated there.
