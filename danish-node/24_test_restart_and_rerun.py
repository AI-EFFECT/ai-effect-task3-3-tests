"""
Restarts the Danish services between runs and checks recovery, data retention and a clean rerun.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse
import time

from _support import (COMPLETE_STATES, SERVICE_CONTAINERS, Blocked, assert_baseline, collect_outputs, docker,
                      health_urls, inline_reference, load_fixture, read_volume_file, require_keys, run_test,
                      run_workflow, sha256_text, validate_outputs, wait_http_ok)

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--timeout-seconds", type=int, default=600)
args = parser.parse_args()


def run_and_check(settings, evidence, label, config):
    run = run_workflow(settings, [inline_reference(config)], args.timeout_seconds)
    evidence.save_text(f"{label}-workflow.json", run["workflow_text"] or run["submit_text"])
    evidence.save_text(f"{label}-tasks.json", run["tasks_text"])
    outputs = collect_outputs(run["tasks"]) if run["workflow_id"] else {}
    checks = validate_outputs(outputs, config, run["workflow_id"]) if outputs else []
    ok = run["workflow"].get("status") in COMPLETE_STATES and bool(checks) and all(c["ok"] for c in checks)
    print(f"{label}: workflow={run['workflow_id']} status={run['workflow'].get('status')} checks_ok={ok}")
    return run, outputs, ok


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    config, _ = load_fixture()

    print("=== Run before restart")
    before, before_outputs, before_ok = run_and_check(settings, evidence, "before-restart", config)
    if not before_ok:
        raise Blocked("The workflow before the restart did not complete with valid outputs, so recovery cannot be judged.")
    retained_uri = before_outputs["topology_generator"]["uri"]
    retained_hash = sha256_text(before_outputs["topology_generator"]["text"])

    print(f"=== Restarting {', '.join(SERVICE_CONTAINERS)}")
    started = time.monotonic()
    restarted = docker("restart", *SERVICE_CONTAINERS, timeout=300)
    evidence.save_text("docker-restart.txt", restarted.stdout + restarted.stderr)
    if restarted.returncode != 0:
        return "FAIL", "docker restart of the Danish pipeline containers failed. See docker-restart.txt."
    for url in health_urls(settings).values():
        wait_http_ok(url, timeout_seconds=300)
    recovery_seconds = round(time.monotonic() - started, 3)
    print(f"All Danish pipeline services recovered in {recovery_seconds} s")

    after_text = read_volume_file("dk-topology-generator", retained_uri)
    volume_retained = after_text is not None and sha256_text(after_text) == retained_hash
    print(f"Earlier output {retained_uri} retained unchanged: {volume_retained}")

    print("=== Run after restart")
    after, _, after_ok = run_and_check(settings, evidence, "after-restart", config)

    evidence.save_json("summary.json", {
        "commit": commit,
        "restarted_containers": SERVICE_CONTAINERS,
        "recovery_seconds": recovery_seconds,
        "retained_output": retained_uri,
        "volume_retained": volume_retained,
        "before_workflow": before["workflow_id"],
        "after_workflow": after["workflow_id"],
        "after_restart_ok": after_ok,
    })

    if volume_retained and after_ok:
        return "PASS", (f"three Danish containers recovered in {recovery_seconds} s, the earlier output was retained "
                        "on the shared volume and a new workflow completed with valid outputs. "
                        "No recovery-time requirement was defined, so this is a reference value.")
    problems = [p for p, bad in (("earlier output not retained", not volume_retained),
                                 ("rerun did not complete with valid outputs", not after_ok)) if bad]
    return "FAIL", f"restart and rerun problems: {'; '.join(problems)}."


if __name__ == "__main__":
    run_test("24-restart-and-rerun", body)
