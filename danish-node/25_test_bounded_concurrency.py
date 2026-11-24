"""
Runs two overlapping Danish workflows as a bounded concurrency smoke test.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse
import time

from _support import (COMPLETE_STATES, DONE_STATES, add_resource_samples, assert_baseline, collect_outputs,
                      get_workflow, inline_reference, load_export, load_fixture, now_iso, require_keys, run_test,
                      submit_workflow, validate_outputs, wait_http_ok, write_csv)

PARALLEL_WORKFLOWS = 2

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--rounds", type=int, default=3, choices=range(1, 11), metavar="1-10")
parser.add_argument("--timeout-seconds", type=int, default=1200)
args = parser.parse_args()


def run_round(settings, evidence, round_no, config, blueprint, dockerinfo, stats_path):
    items = []
    for index in range(1, PARALLEL_WORKFLOWS + 1):
        started = time.monotonic()
        status, content, workflow_id = submit_workflow(settings, [inline_reference(config)], blueprint, dockerinfo)
        evidence.save_text(f"round-{round_no}-workflow-{index}-submit.json", content)
        if not workflow_id:
            raise RuntimeError(f"round {round_no} workflow {index} submission returned HTTP {status} without a workflow_id.")
        items.append({"index": index, "workflow_id": workflow_id, "started": started,
                      "started_at": now_iso(), "status": "submitted", "finished": None, "tasks": {}, "workflow": {}})

    deadline = time.monotonic() + args.timeout_seconds
    while any(i["status"] not in DONE_STATES for i in items) and time.monotonic() < deadline:
        time.sleep(2)
        for item in [i for i in items if i["status"] not in DONE_STATES]:
            workflow, tasks, workflow_text, tasks_text = get_workflow(settings, item["workflow_id"])
            item.update(status=workflow.get("status", "unknown"), workflow=workflow, tasks=tasks)
            evidence.save_text(f"round-{round_no}-workflow-{item['index']}-workflow.json", workflow_text)
            evidence.save_text(f"round-{round_no}-workflow-{item['index']}-tasks.json", tasks_text)
            if item["status"] in DONE_STATES:
                item["finished"] = time.monotonic()
            print(f"{now_iso()} round={round_no} workflow={item['index']} id={item['workflow_id']} status={item['status']}")
        add_resource_samples(stats_path, [round_no])

    results = []
    for item in items:
        if item["status"] not in DONE_STATES:
            item["status"], item["finished"] = "timeout", time.monotonic()
        outputs = collect_outputs(item["tasks"]) if item["tasks"] else {}
        checks = validate_outputs(outputs, config, item["workflow_id"]) if outputs else []
        failed_checks = [c["check"] for c in checks if not c["ok"]]
        task_ids = sorted(t.get("task_id") for t in item["tasks"].get("tasks", []))
        results.append({
            "Round": round_no,
            "Index": item["index"],
            "WorkflowId": item["workflow_id"],
            "Status": item["status"],
            "StartedAt": item["started_at"],
            "DurationSeconds": round(item["finished"] - item["started"], 3),
            "NonCompletedTasks": len([t for t in item["tasks"].get("tasks", []) if t.get("status") not in COMPLETE_STATES]),
            "TopologyCount": (outputs.get("topology_generator", {}).get("data") or {}).get("topology_count"),
            "ChecksPassed": bool(checks) and not failed_checks,
            "FailedChecks": "; ".join(failed_checks),
            "TaskIds": " ".join(task_ids),
        })
    return results


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    config, _ = load_fixture()
    blueprint, dockerinfo = load_export(settings)

    stats_path = evidence.file("resource-samples.tsv")
    stats_path.write_text("timestamp\tround\tcontainer\tCPU\tMemoryUsage\tMemoryPercent\tPIDs\n", encoding="utf-8")
    results = []
    for round_no in range(1, args.rounds + 1):
        print(f"=== Concurrency round {round_no} of {args.rounds}: {PARALLEL_WORKFLOWS} overlapping workflows ===")
        results += run_round(settings, evidence, round_no, config, blueprint, dockerinfo, stats_path)

    write_csv(evidence.file("concurrency-results.csv"), results)
    evidence.save_json("concurrency-results.json", results)
    shared_task_ids = len({r["TaskIds"] for r in results}) == 1
    mixed_rounds = sorted({r["Round"] for r in results if "belongs to this workflow" in r["FailedChecks"]})
    evidence.save_json("summary.json", {"commit": commit, "parallel_workflows": PARALLEL_WORKFLOWS,
                                        "rounds": args.rounds, "rounds_with_mixed_outputs": mixed_rounds,
                                        "same_task_ids_across_workflows": shared_task_ids, "results": results})
    print(f"Same task IDs reused across all workflows: {shared_task_ids}")
    print(f"Rounds with mixed outputs: {mixed_rounds or 'none'}")

    note = " All workflows used the same task IDs (see DK-REL-02)." if shared_task_ids else ""
    if mixed_rounds:
        return "DEFECT CONFIRMED", (f"overlapping workflows returned each other's outputs in {len(mixed_rounds)} of "
                                    f"{args.rounds} rounds. Do not increase concurrency; preserve the evidence.{note}")
    if all(r["Status"] in COMPLETE_STATES and r["ChecksPassed"] for r in results):
        return "PASS", (f"{args.rounds} rounds of two overlapping Danish workflows completed with valid, separate "
                        f"outputs. This is a bounded concurrency smoke test, not a capacity limit.{note}")
    return "FINDINGS RECORDED", ("one or more overlapping workflows failed, timed out or produced invalid output. "
                                 f"Do not increase concurrency; preserve the evidence.{note}")


if __name__ == "__main__":
    run_test("25-bounded-concurrency", body)
