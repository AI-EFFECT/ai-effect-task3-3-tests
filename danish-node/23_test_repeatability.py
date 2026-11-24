"""
Repeats the structured workflow and records duration, output structure, hashes and resource samples.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse
import statistics

from _support import (COMPLETE_STATES, add_resource_samples, assert_baseline, collect_outputs, inline_reference,
                      load_fixture, orchestrator_timing, require_keys, run_test, run_workflow, topology_fingerprint,
                      validate_outputs, wait_http_ok, write_csv)

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--repetitions", type=int, default=3, choices=range(2, 6), metavar="2-5")
parser.add_argument("--timeout-seconds", type=int, default=600)
args = parser.parse_args()


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    config, fixture_hash = load_fixture()

    stats_path = evidence.file("resource-samples.tsv")
    stats_path.write_text("timestamp\titeration\tphase\tcontainer\tCPU\tMemoryUsage\tMemoryPercent\tPIDs\n", encoding="utf-8")

    measurements = []
    for iteration in range(1, args.repetitions + 1):
        print(f"=== Danish repeatability run {iteration} of {args.repetitions} ===")
        add_resource_samples(stats_path, [iteration, "before"])
        run = run_workflow(settings, [inline_reference(config)], args.timeout_seconds,
                           on_poll=lambda i=iteration: add_resource_samples(stats_path, [i, "running"]))
        add_resource_samples(stats_path, [iteration, "after"])
        evidence.save_text(f"run-{iteration}-workflow.json", run["workflow_text"] or run["submit_text"])
        evidence.save_text(f"run-{iteration}-tasks.json", run["tasks_text"])

        outputs = collect_outputs(run["tasks"]) if run["workflow_id"] else {}
        if outputs.get("topology_generator", {}).get("text"):
            evidence.save_text(f"run-{iteration}-topology-output.json", outputs["topology_generator"]["text"])
        checks = validate_outputs(outputs, config, run["workflow_id"]) if outputs else []
        topology = (outputs.get("topology_generator", {}).get("data") or {})
        render = (outputs.get("draw_topology", {}).get("data") or {})
        timing = orchestrator_timing(run["workflow"], run["tasks"])
        measurements.append({
            "Iteration": iteration,
            "WorkflowId": run["workflow_id"],
            "Status": run["workflow"].get("status"),
            "DurationSeconds": run["client_seconds"],
            "TopologyCount": topology.get("topology_count"),
            "DrawingCount": render.get("drawing_count"),
            "RecommendedNetwork": (topology.get("recommended_network") or {}).get("signature"),
            "OutputSha256": topology_fingerprint(outputs),
            "ChecksPassed": bool(checks) and all(c["ok"] for c in checks),
            "DeliverySeconds": timing.get("DeliverySeconds"),
            "BuildRunConfigSeconds": timing.get("BuildRunConfigSeconds"),
            "GenerateTopologySeconds": timing.get("GenerateTopologySeconds"),
            "RenderTopologiesSeconds": timing.get("RenderTopologiesSeconds"),
        })

    write_csv(evidence.file("measurements.csv"), measurements)
    evidence.save_json("measurements.json", measurements)
    completed = [m for m in measurements if m["Status"] in COMPLETE_STATES]
    durations = [m["DurationSeconds"] for m in measurements if m["DurationSeconds"] is not None]
    structure = {(m["TopologyCount"], m["DrawingCount"], m["RecommendedNetwork"]) for m in completed}
    hashes = {m["OutputSha256"] for m in completed}
    summary = {
        "Commit": commit,
        "FixtureSha256": fixture_hash,
        "Runs": len(measurements),
        "Completed": len(completed),
        "MinimumSeconds": round(min(durations), 3) if durations else None,
        "MeanSeconds": round(statistics.mean(durations), 3) if durations else None,
        "MaximumSeconds": round(max(durations), 3) if durations else None,
        "StableOutputStructure": len(structure) == 1 and len(completed) == len(measurements),
        "IdenticalCandidateNetworks": len(hashes) == 1 and len(completed) == len(measurements),
        "AllSemanticChecksPassed": all(m["ChecksPassed"] for m in measurements),
    }
    evidence.save_json("summary.json", summary)
    print(summary)

    if summary["StableOutputStructure"] and summary["AllSemanticChecksPassed"]:
        identical = "identical" if summary["IdenticalCandidateNetworks"] else "different"
        return "PASS", (f"{len(completed)} repeated workflows completed with a stable, valid output structure and "
                        f"{identical} candidate networks; mean {summary['MeanSeconds']} s. "
                        "Timing and resource evidence is an initial technical reference only.")
    return "FINDINGS RECORDED", "completion, output structure or semantic checks differed across repeated runs. Preserve all evidence."


if __name__ == "__main__":
    run_test("23-repeatability-performance-reference", body)
