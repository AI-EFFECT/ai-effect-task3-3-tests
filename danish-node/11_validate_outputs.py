"""
Validates the run configuration, topologies and drawings retained by script 10.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import json

from _support import Blocked, read_volume_file, run_test, setting_path, task_for, validate_outputs

FILES = {"config_assistant": "config-output.json",
         "topology_generator": "topology-output.json",
         "draw_topology": "render-output.json"}


def latest_workflow_evidence(settings):
    root = setting_path(settings, "EvidenceRoot")
    folders = sorted((p for p in root.glob("*-10-structured-workflow") if (p / "summary.json").exists()),
                     key=lambda p: p.name, reverse=True)
    if not folders:
        raise Blocked("No evidence from 10_test_workflow.py was found. Run script 10 first.")
    return folders[0]


def body(settings, evidence):
    source = latest_workflow_evidence(settings)
    print(f"Validating evidence from {source}")
    summary = json.loads((source / "summary.json").read_text(encoding="utf-8"))
    request = json.loads((source / "request-config.json").read_text(encoding="utf-8"))
    tasks = json.loads((source / "tasks.json").read_text(encoding="utf-8"))
    workflow_id = summary["workflow_id"]

    outputs = {}
    for service, file_name in FILES.items():
        path = source / file_name
        text = path.read_text(encoding="utf-8") if path.exists() else None
        task = task_for(tasks, service) or {}
        refs = task.get("output_refs") or []
        outputs[service] = {"uri": refs[0].get("uri") if refs else None, "text": text,
                            "data": json.loads(text) if text else None}

    checks = validate_outputs(outputs, request, workflow_id)

    drawings = (outputs["draw_topology"]["data"] or {}).get("drawings") or []
    svg_folder = evidence.file("svg")
    svg_folder.mkdir()
    valid_svgs = 0
    for drawing in drawings:
        content = read_volume_file("dk-draw-topology", drawing.get("uri", ""))
        if content and content.lstrip().startswith(("<svg", "<?xml")):
            valid_svgs += 1
            (svg_folder / f"network_{int(drawing.get('network_index', 0)):03d}.svg").write_text(content, encoding="utf-8")
    checks.append({"check": "every referenced SVG exists and is an SVG", "ok": valid_svgs == len(drawings) and valid_svgs > 0,
                   "detail": f"{valid_svgs} of {len(drawings)}"})

    for item in checks:
        print(f"{'OK  ' if item['ok'] else 'FAIL'}  {item['check']}: {item['detail']}")
    topology = outputs["topology_generator"]["data"] or {}
    evidence.save_json("summary.json", {
        "source_evidence": str(source),
        "workflow_id": workflow_id,
        "topology_count": topology.get("topology_count"),
        "recommended_network": (topology.get("recommended_network") or {}).get("signature"),
        "valid_svgs": valid_svgs,
        "checks": checks,
    })

    failed = [c["check"] for c in checks if not c["ok"]]
    if failed:
        return "FAIL", f"{len(failed)} output check(s) failed: {'; '.join(failed)}."
    return "PASS", (f"run configuration, {topology.get('topology_count')} topology candidates and "
                    f"{valid_svgs} SVG drawings are consistent with the request and belong to workflow {workflow_id}.")


if __name__ == "__main__":
    run_test("11-validate-outputs", body)
