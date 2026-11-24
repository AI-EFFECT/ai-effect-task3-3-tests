"""
Checks that invalid input fails safely and records how incomplete input is handled.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse

from _support import (COMPLETE_STATES, assert_baseline, collect_outputs, inline_reference, require_keys,
                      run_test, run_workflow, task_for, wait_http_ok)

REJECTION_CASES = [
    ("non-object-value", inline_reference(42), "JSON object or text prompt"),
    ("missing-file-reference", {"protocol": "file", "uri": "/data/t33-dk-missing/none.json", "format": "json"}, "not found"),
    ("service-unsupported-protocol", {"protocol": "s3", "uri": "s3://t33-dk/none.json", "format": "json"}, "Unsupported input protocol"),
]
SUBMISSION_REJECTION = ("orchestrator-unknown-protocol", {"protocol": "ftp", "uri": "t33-dk", "format": "json"})
OBSERVATION_CASES = [
    ("empty-configuration", inline_reference({})),
    ("unrecognised-supply", inline_reference({"supplies": ["999-X::Unknown"], "loads": ["716-D::Dumpload"]})),
]

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--timeout-seconds", type=int, default=300)
args = parser.parse_args()


def body(settings, evidence):
    assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    results = []

    for name, reference, expected_error in REJECTION_CASES:
        print(f"=== Rejection case: {name}")
        run = run_workflow(settings, [reference], args.timeout_seconds)
        evidence.save_text(f"{name}-workflow.json", run["workflow_text"] or run["submit_text"])
        evidence.save_text(f"{name}-tasks.json", run["tasks_text"])
        config_task = task_for(run["tasks"], "config_assistant") or {}
        downstream_completed = [s for s in ("topology_generator", "draw_topology")
                                if (task_for(run["tasks"], s) or {}).get("status") in COMPLETE_STATES]
        error = str(config_task.get("error") or "")
        ok = (run["workflow"].get("status") == "failed"
              and config_task.get("status") == "failed"
              and expected_error.lower() in error.lower()
              and not config_task.get("output_refs")
              and not downstream_completed)
        results.append({"case": name, "kind": "rejection", "workflow_id": run["workflow_id"],
                        "status": run["workflow"].get("status"), "config_status": config_task.get("status"),
                        "error": error, "downstream_completed": downstream_completed, "ok": ok})
        print(f"{'OK  ' if ok else 'FAIL'}  {name}: status={run['workflow'].get('status')} error={error}")

    name, reference = SUBMISSION_REJECTION
    print(f"=== Rejection case: {name}")
    run = run_workflow(settings, [reference], args.timeout_seconds)
    evidence.save_text(f"{name}-submit.txt", f"HTTP {run['submit_status']}\n{run['submit_text']}")
    ok = run["submit_status"] in (400, 422) and not run["workflow_id"] and "protocol" in run["submit_text"]
    results.append({"case": name, "kind": "rejection", "workflow_id": run["workflow_id"],
                    "status": f"HTTP {run['submit_status']}", "error": run["submit_text"][:300], "ok": ok})
    print(f"{'OK  ' if ok else 'FAIL'}  {name}: submission HTTP {run['submit_status']}")

    for name, reference in OBSERVATION_CASES:
        print(f"=== Observation case: {name}")
        run = run_workflow(settings, [reference], args.timeout_seconds)
        evidence.save_text(f"{name}-workflow.json", run["workflow_text"] or run["submit_text"])
        evidence.save_text(f"{name}-tasks.json", run["tasks_text"])
        config = (collect_outputs(run["tasks"])["config_assistant"]["data"] or {}) if run["tasks"] else {}
        run_config = config.get("run_config", {})
        results.append({"case": name, "kind": "observation", "workflow_id": run["workflow_id"],
                        "status": run["workflow"].get("status"), "valid": config.get("valid"),
                        "warnings": config.get("warnings"), "used_supplies": run_config.get("supplies"),
                        "used_loads": run_config.get("loads")})
        print(f"OBSERVED {name}: status={run['workflow'].get('status')} valid={config.get('valid')} "
              f"supplies={run_config.get('supplies')} warnings={config.get('warnings')}")

    evidence.save_json("invalid-input-results.json", results)
    rejections_ok = all(r["ok"] for r in results if r["kind"] == "rejection")
    fallbacks = [r["case"] for r in results if r["kind"] == "observation" and r["status"] in COMPLETE_STATES]

    if not rejections_ok:
        failed = [r["case"] for r in results if r["kind"] == "rejection" and not r["ok"]]
        return "FAIL", f"invalid input was not rejected safely for: {', '.join(failed)}. Preserve the evidence."
    message = "malformed, missing and unsupported inputs were refused at submission or failed explicitly with no output and no downstream completion."
    if fallbacks:
        message += (f" Observation: {', '.join(fallbacks)} completed with default terminals and valid=true, "
                    "only a warning showing the substitution. See DK-VAL-01.")
    return "PASS", message


if __name__ == "__main__":
    run_test("20-invalid-input", body)
