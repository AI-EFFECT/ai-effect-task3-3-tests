"""Stand-in third-party model service for the T3.3 external-exchange tests.

Built on the platform's concurrent template: handler.py and common/ are copied
from the frozen AI-EFFECT commit by 20-Prepare-Vendor-Pipeline.ps1, so any
task-tracking behaviour of that template is exercised unchanged.

FitBaseline reads the ingest document and, for each numeric column, fits a
naive and a least-squares linear-trend baseline. The optional delay_seconds
parameter keeps the task running so restart tests can act mid-task.
"""

import json
import math
import os
import time
from pathlib import Path

from handler import ExecuteRequest, ExecuteResponse, TaskManager, run, run_in_background, task_manager

DATA_DIR = Path(os.environ.get("VENDOR_DATA_DIR", "/vendor-data"))
MAX_DELAY_SECONDS = 600


def _fit(values: list[float]) -> dict:
    n = len(values)
    mean = sum(values) / n
    std = math.sqrt(sum((v - mean) ** 2 for v in values) / n)
    slope = 0.0
    if n > 1:
        x_mean = (n - 1) / 2
        denominator = sum((i - x_mean) ** 2 for i in range(n))
        slope = sum((i - x_mean) * (v - mean) for i, v in enumerate(values)) / denominator
    intercept = mean - slope * (n - 1) / 2
    return {"n": n, "mean": mean, "std": std, "last": values[-1], "slope": slope, "next_forecast": intercept + slope * n}


def _work(task_id: str, request: ExecuteRequest, manager: TaskManager) -> None:
    try:
        delay = max(0, min(int(request.parameters.get("delay_seconds", 0) or 0), MAX_DELAY_SECONDS))
        for second in range(delay):
            time.sleep(1)
            manager.update_progress(task_id, int(90 * (second + 1) / delay))
        if not request.inputs:
            raise ValueError("no input reference supplied")
        reference = request.inputs[0]
        if reference.get("protocol") != "file":
            raise ValueError(f"Unsupported input protocol: {reference.get('protocol')}")
        ingest = json.loads(Path(reference["uri"]).read_text(encoding="utf-8"))
        models = {column: _fit(values) for column, values in ingest.get("series", {}).items() if values}
        document = {
            "generated_by": "vendor_model",
            "workflow_id": request.workflow_id,
            "task_id": task_id,
            "marker": str(request.parameters.get("marker", "")),
            "ingest_marker": ingest.get("marker"),
            "source_workflow_id": ingest.get("workflow_id"),
            "source_sha256": ingest.get("source", {}).get("sha256"),
            "records": ingest.get("profile", {}).get("records"),
            "model": "per-column naive and linear-trend baseline",
            "models": models,
        }
        output_dir = DATA_DIR / request.workflow_id
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / f"{task_id}.json"
        output_path.write_text(json.dumps(document), encoding="utf-8")
        manager.complete_task(task_id, {"protocol": "file", "uri": str(output_path), "format": "json"})
    except Exception as exc:  # noqa: BLE001 - reported to the orchestrator as a task failure
        manager.fail_task(task_id, str(exc))


def execute_FitBaseline(request: ExecuteRequest) -> ExecuteResponse:
    task_manager.register_task(request.task_id, request)
    run_in_background(request.task_id, _work, request)
    return ExecuteResponse(status="running", task_id=request.task_id)


if __name__ == "__main__":
    import sys

    run(sys.modules[__name__])
