"""
Checks the free-text prompt workflow through the local Ollama model over several rounds.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse

from _support import (COMPLETE_STATES, OLLAMA_CONTAINER, Blocked, assert_baseline, collect_outputs, container_state,
                      docker, incomplete_tasks, inline_reference, orchestrator_timing, require_keys, run_test,
                      run_workflow, wait_http_ok, write_csv)

PROMPT = "Use the CHP at 310-D as supply, feed the dumpload at 716-D."
EXPECTED_SUPPLIES = ["310-D::CHP"]
EXPECTED_LOADS = ["716-D::Dumpload"]
# Settings the prompt does not mention. The config assistant fills omitted fields
# from MINIMAL_CONFIG in services/config_assistant/service.py.
UNMENTIONED_DEFAULTS = {"allow_hx": True, "allow_bypass": False, "max_extra_pipes": 1, "load_topology": "any"}

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--rounds", type=int, default=5, choices=range(1, 11), metavar="1-10")
parser.add_argument("--timeout-seconds", type=int, default=900)
args = parser.parse_args()


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")

    if container_state(OLLAMA_CONTAINER) not in ("running", "healthy"):
        raise Blocked(f"{OLLAMA_CONTAINER} is not running. Start it with 01_start_services.py.")
    if docker("exec", OLLAMA_CONTAINER, "ollama", "show", settings["OllamaModel"], timeout=120).returncode != 0:
        raise Blocked(f"Ollama model {settings['OllamaModel']} is not available. Run 01_start_services.py without --skip-ollama.")

    evidence.save_text("prompt.txt", PROMPT)
    rows = []
    for round_no in range(1, args.rounds + 1):
        print(f"=== Prompt round {round_no} of {args.rounds} ===")
        run = run_workflow(settings, [inline_reference(PROMPT)], args.timeout_seconds)
        evidence.save_text(f"round-{round_no}-submit.json", run["submit_text"])
        if not run["workflow_id"]:
            return "FAIL", f"round {round_no} submission returned HTTP {run['submit_status']} without a workflow_id."
        evidence.save_text(f"round-{round_no}-workflow.json", run["workflow_text"])
        evidence.save_text(f"round-{round_no}-tasks.json", run["tasks_text"])

        outputs = collect_outputs(run["tasks"])
        if outputs["config_assistant"]["text"]:
            evidence.save_text(f"round-{round_no}-config-output.json", outputs["config_assistant"]["text"])
        config = outputs["config_assistant"]["data"] or {}
        run_config = config.get("run_config", {})
        status = run["workflow"].get("status")
        changed = {key: run_config.get(key) for key, value in UNMENTIONED_DEFAULTS.items() if run_config.get(key) != value}
        timing = orchestrator_timing(run["workflow"], run["tasks"])
        row = {
            "Round": round_no,
            "WorkflowId": run["workflow_id"],
            "Status": status,
            "NonCompletedTasks": incomplete_tasks(run["tasks"]),
            "Error": str(run["workflow"].get("error") or ""),
            "Supplies": " ".join(run_config.get("supplies") or []),
            "Loads": " ".join(run_config.get("loads") or []),
            "TerminalsMatch": run_config.get("supplies") == EXPECTED_SUPPLIES and run_config.get("loads") == EXPECTED_LOADS,
            "Warnings": " | ".join(config.get("warnings") or []),
            "AllowHx": run_config.get("allow_hx"),
            "AllowBypass": run_config.get("allow_bypass"),
            "MaxExtraPipes": run_config.get("max_extra_pipes"),
            "LoadTopology": run_config.get("load_topology"),
            "UnrequestedSettingsChanged": bool(changed),
            "BuildRunConfigSeconds": timing.get("BuildRunConfigSeconds"),
            "ClientSeconds": run["client_seconds"],
        }
        rows.append(row)
        print(f"status={status} supplies={run_config.get('supplies')} loads={run_config.get('loads')} "
              f"warnings={config.get('warnings')} changed_unrequested={changed or 'none'}")

    write_csv(evidence.file("prompt-rounds.csv"), rows)
    evidence.save_json("prompt-rounds.json", rows)
    failed = [r["Round"] for r in rows if r["Status"] not in COMPLETE_STATES]
    invented = [r["Round"] for r in rows if r["UnrequestedSettingsChanged"]]
    terminal_issues = [r["Round"] for r in rows if r["Status"] in COMPLETE_STATES and (not r["TerminalsMatch"] or r["Warnings"])]
    summary = {
        "commit": commit,
        "ollama_model": settings["OllamaModel"],
        "prompt": PROMPT,
        "rounds": args.rounds,
        "unmentioned_defaults": UNMENTIONED_DEFAULTS,
        "rounds_failed": failed,
        "rounds_with_unrequested_settings": invented,
        "rounds_with_terminal_fallback_or_warnings": terminal_issues,
    }
    evidence.save_json("summary.json", summary)
    print(summary)

    if failed or invented:
        return "DEFECT CONFIRMED", (f"the model changed settings the prompt did not mention in {len(invented)} of "
                                    f"{args.rounds} rounds, and {len(failed)} of {args.rounds} workflows failed. "
                                    "See prompt-rounds.csv and DK-LLM-01.")
    if terminal_issues:
        return "FINDINGS RECORDED", (f"{len(terminal_issues)} of {args.rounds} rounds completed with substituted terminals "
                                     "or warnings. See prompt-rounds.csv.")
    return "PASS", (f"all {args.rounds} rounds extracted the requested terminals with no warnings and left unmentioned "
                    "settings to the service defaults.")


if __name__ == "__main__":
    run_test("12-prompt-workflow", body)
