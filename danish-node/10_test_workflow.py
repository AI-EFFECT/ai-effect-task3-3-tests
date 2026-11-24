"""
Runs the structured Danish workflow end to end and retains its outputs.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse

from _support import (COMPLETE_STATES, assert_baseline, collect_outputs, incomplete_tasks, inline_reference,
                      load_fixture, orchestrator_timing, require_keys, run_test, run_workflow, wait_http_ok)

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--timeout-seconds", type=int, default=600)
args = parser.parse_args()


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")

    config, fixture_hash = load_fixture()
    print(f"Fixture chp_dumploads.json SHA-256 {fixture_hash}")
    evidence.save_json("request-config.json", config)

    run = run_workflow(settings, [inline_reference(config)], args.timeout_seconds)
    evidence.save_text("submit.json", run["submit_text"])
    if not run["workflow_id"]:
        return "FAIL", f"workflow submission returned HTTP {run['submit_status']} without a workflow_id."
    evidence.save_text("workflow.json", run["workflow_text"])
    evidence.save_text("tasks.json", run["tasks_text"])

    outputs = collect_outputs(run["tasks"])
    for name, file_name in (("config_assistant", "config-output.json"),
                            ("topology_generator", "topology-output.json"),
                            ("draw_topology", "render-output.json")):
        if outputs[name]["text"]:
            evidence.save_text(file_name, outputs[name]["text"])

    status = run["workflow"].get("status")
    not_completed = incomplete_tasks(run["tasks"])
    evidence.save_json("summary.json", {
        "commit": commit,
        "fixture_sha256": fixture_hash,
        "workflow_id": run["workflow_id"],
        "status": status,
        "non_completed_tasks": not_completed,
        "client_seconds": run["client_seconds"],
        "orchestrator_timing": orchestrator_timing(run["workflow"], run["tasks"]),
        "outputs_retained": {name: value["text"] is not None for name, value in outputs.items()},
    })

    if status in COMPLETE_STATES and not_completed == 0 and all(v["text"] for v in outputs.values()):
        return "PASS", ("all three Danish steps completed and their outputs were retained. "
                        "Run 11_validate_outputs.py for the semantic checks.")
    error = run["workflow"].get("error") or "see tasks.json"
    return "FAIL", f"workflow ended as {status} with {not_completed} non-completed tasks: {error}"


if __name__ == "__main__":
    run_test("10-structured-workflow", body)
