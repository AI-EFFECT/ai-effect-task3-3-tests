"""
Provides shared settings, evidence, HTTP, orchestrator and container helpers for the Danish test scripts.

Part of the AI-EFFECT Task 3.3 Danish node test package. It centralises behaviour used by the executable tests.

This is an internal helper file loaded by other scripts; do not run it directly.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

NODE_DIR = Path(__file__).resolve().parent
FIXTURE_PATH = NODE_DIR / "fixtures" / "chp_dumploads.json"

REQUIRED_SETTINGS = [
    "RepositoryRoot", "DenmarkRoot", "EvidenceRoot", "ExpectedCommit",
    "OrchestratorUrl", "OrchestratorCompose", "DenmarkCompose", "OllamaModel",
    "ConfigAssistantUrl", "TopologyGeneratorUrl", "DrawTopologyUrl",
]

# The three orchestrated services, in pipeline order.
PIPELINE = [
    {"service": "config_assistant", "method": "BuildRunConfig", "container": "dk-config-assistant", "url_setting": "ConfigAssistantUrl"},
    {"service": "topology_generator", "method": "GenerateTopology", "container": "dk-topology-generator", "url_setting": "TopologyGeneratorUrl"},
    {"service": "draw_topology", "method": "RenderTopologies", "container": "dk-draw-topology", "url_setting": "DrawTopologyUrl"},
]
SERVICE_CONTAINERS = [step["container"] for step in PIPELINE]
OLLAMA_CONTAINER = "dk-ollama"
DONE_STATES = ("complete", "completed", "failed")
COMPLETE_STATES = ("complete", "completed")


class Blocked(Exception):
    """A prerequisite or supplied interface prevented the test."""


# Settings and frozen-source checks
def _find_powershell() -> str | None:
    for name in ("pwsh", "powershell"):
        if shutil.which(name):
            return name
    return None


def _parse_flat_psd1(text: str) -> dict:
    """Fallback reader for the flat Key = 'value' settings files used by this suite."""
    settings = {}
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        match = re.match(r"^([A-Za-z0-9_]+)\s*=\s*(['\"])(.*)\2\s*;?$", line)
        if match:
            settings[match.group(1)] = match.group(3)
    return settings


def read_settings() -> dict:
    path = NODE_DIR / "Test-Settings.psd1"
    if not path.exists():
        raise SystemExit("Create Test-Settings.psd1 by copying Test-Settings.psd1.example.")
    powershell = _find_powershell()
    if powershell:
        command = [powershell, "-NoProfile", "-Command",
                   f"Import-PowerShellDataFile -LiteralPath '{path}' | ConvertTo-Json -Depth 10"]
        completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if completed.returncode != 0:
            raise SystemExit(f"PowerShell could not read Test-Settings.psd1: {completed.stderr.strip()}")
        settings = json.loads(completed.stdout)
    else:
        settings = _parse_flat_psd1(path.read_text(encoding="utf-8-sig"))
    missing = [name for name in REQUIRED_SETTINGS if not str(settings.get(name, "")).strip()]
    if missing:
        raise SystemExit(f"Test-Settings.psd1 is missing: {', '.join(missing)}")
    return settings


def setting_path(settings: dict, name: str) -> Path:
    return Path(os.path.expanduser(settings[name]))


def assert_baseline(settings: dict) -> str:
    repo = setting_path(settings, "RepositoryRoot")
    head = run_command(["git", "-C", str(repo), "rev-parse", "HEAD"])
    actual = head.stdout.strip()
    if head.returncode != 0:
        raise Blocked(f"Could not read the source commit in {repo}: {head.stderr.strip()}")
    if actual != settings["ExpectedCommit"]:
        raise Blocked(f"Unexpected source commit: {actual}. Expected {settings['ExpectedCommit']}.")
    dirty = [line for line in run_command(["git", "-C", str(repo), "status", "--porcelain"]).stdout.splitlines() if line.strip()]
    if dirty:
        raise Blocked("Repository is not clean. Stop without testing.")
    return actual


# Runtime credentials
def require_keys() -> None:
    for name in ("ORCHESTRATOR_API_KEY", "SERVICE_API_KEY"):
        if not os.environ.get(name, "").strip():
            raise Blocked(f"{name} is not set in this terminal.")


def bearer(key: str | None) -> dict:
    return {"Authorization": f"Bearer {key}"} if key else {}


def orchestrator_headers() -> dict:
    return bearer(os.environ.get("ORCHESTRATOR_API_KEY"))


# Evidence capture and transcript lifecycle
class _Tee:
    def __init__(self, console, file):
        self.console = console
        self.file = file

    def write(self, text):
        self.console.write(text)
        self.file.write(text)

    def flush(self):
        self.console.flush()
        self.file.flush()


class Evidence:
    """Timestamped evidence folder with a run.txt transcript, like New-EvidenceFolder plus Start-Transcript."""

    def __init__(self, settings: dict, label: str):
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.path = setting_path(settings, "EvidenceRoot") / f"{stamp}-{label}"
        self.path.mkdir(parents=True, exist_ok=False)
        self.label = label

    def __enter__(self):
        self._file = open(self.path / "run.txt", "w", encoding="utf-8")
        self._stdout, self._stderr = sys.stdout, sys.stderr
        sys.stdout = _Tee(self._stdout, self._file)
        sys.stderr = _Tee(self._stderr, self._file)
        print(f"Transcript started: {self.path / 'run.txt'}")
        print(f"Started at {now_iso()} on {sys.platform}, Python {sys.version.split()[0]}")
        return self

    def __exit__(self, *exc):
        print(f"Transcript stopped at {now_iso()}")
        sys.stdout, sys.stderr = self._stdout, self._stderr
        self._file.close()

    def file(self, name: str) -> Path:
        return self.path / name

    def save_text(self, name: str, content: str) -> Path:
        target = self.path / name
        target.write_text(content, encoding="utf-8")
        return target

    def save_json(self, name: str, data) -> Path:
        return self.save_text(name, json.dumps(data, indent=2, default=str))


def run_test(label: str, body) -> None:
    """Run one test body inside an evidence folder and print exactly one RESULT line."""
    settings = read_settings()
    with Evidence(settings, label) as evidence:
        try:
            verdict, message = body(settings, evidence)
        except Blocked as exc:
            verdict, message = "BLOCKED", str(exc)
        except Exception as exc:  # unexpected harness or service error: keep the evidence
            traceback.print_exc()
            verdict, message = "FAIL", f"unexpected error: {exc}. Preserve the evidence folder."
        print(f"RESULT: {verdict} - {message}")
    sys.exit(0 if verdict in ("PASS", "RECORDED", "FINDINGS RECORDED") else 1)


# HTTP helpers
def http(method: str, url: str, headers: dict | None = None, body=None, timeout: float = 30) -> tuple[int, str]:
    data = None
    request_headers = dict(headers or {})
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(url, data=data, method=method, headers=request_headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as exc:
        return 0, f"connection error: {exc}"


def wait_http_ok(url: str, timeout_seconds: int = 180) -> float:
    started = time.monotonic()
    deadline = started + timeout_seconds
    while time.monotonic() < deadline:
        status, _ = http("GET", url, timeout=5)
        if status == 200:
            print(f"HTTP health check passed: {url}")
            return round(time.monotonic() - started, 3)
        print(f"Waiting for HTTP health check: {url}")
        time.sleep(3)
    raise Blocked(f"HTTP health check did not return 200 within {timeout_seconds} seconds: {url}")


def health_urls(settings: dict) -> dict:
    return {step["service"]: settings[step["url_setting"]].rstrip("/") + "/health" for step in PIPELINE}


# Inline references, fixtures and the exported workflow definition
def inline_reference(value) -> dict:
    payload = json.dumps(value, separators=(",", ":")).encode("utf-8")
    return {"protocol": "inline", "uri": base64.b64encode(payload).decode("ascii"), "format": "json"}


def load_fixture() -> tuple[dict, str]:
    raw = FIXTURE_PATH.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest().upper()


def load_export(settings: dict) -> tuple[dict, dict]:
    export = setting_path(settings, "DenmarkRoot") / "export"
    blueprint, dockerinfo = export / "blueprint.json", export / "dockerinfo.json"
    if not blueprint.exists() or not dockerinfo.exists():
        raise Blocked("Exported workflow definition is missing. Run 01_start_services.py first.")
    return json.loads(blueprint.read_text(encoding="utf-8")), json.loads(dockerinfo.read_text(encoding="utf-8"))


# Orchestrator workflow helpers
def submit_workflow(settings: dict, inputs: list, blueprint: dict, dockerinfo: dict) -> tuple[int, str, str | None]:
    body = {
        "blueprint": blueprint,
        "dockerinfo": dockerinfo,
        "inputs": inputs,
        "services_api_key": os.environ.get("SERVICE_API_KEY"),
    }
    status, content = http("POST", f"{settings['OrchestratorUrl']}/workflows", orchestrator_headers(), body)
    workflow_id = None
    if status in (200, 201, 202):
        try:
            workflow_id = json.loads(content).get("workflow_id")
        except json.JSONDecodeError:
            workflow_id = None
    return status, content, workflow_id


def get_workflow(settings: dict, workflow_id: str) -> tuple[dict, dict, str, str]:
    base = f"{settings['OrchestratorUrl']}/workflows/{workflow_id}"
    _, workflow_text = http("GET", base, orchestrator_headers())
    _, tasks_text = http("GET", f"{base}/tasks", orchestrator_headers())
    return _json_or_empty(workflow_text), _json_or_empty(tasks_text), workflow_text, tasks_text


def wait_workflow(settings: dict, workflow_id: str, timeout_seconds: int, poll_seconds: float = 2, on_poll=None):
    deadline = time.monotonic() + timeout_seconds
    while True:
        time.sleep(poll_seconds)
        workflow, tasks, workflow_text, tasks_text = get_workflow(settings, workflow_id)
        if on_poll:
            on_poll()
        status = workflow.get("status", "unknown")
        print(f"{now_iso()} workflow={workflow_id} status={status}")
        if status in DONE_STATES or time.monotonic() >= deadline:
            if status not in DONE_STATES:
                workflow["status"] = "timeout"
            return workflow, tasks, workflow_text, tasks_text


def run_workflow(settings: dict, inputs: list, timeout_seconds: int, poll_seconds: float = 2, on_poll=None) -> dict:
    """Submit one workflow, wait for it and return everything needed for evidence."""
    blueprint, dockerinfo = load_export(settings)
    started = time.monotonic()
    submit_status, submit_text, workflow_id = submit_workflow(settings, inputs, blueprint, dockerinfo)
    result = {"submit_status": submit_status, "submit_text": submit_text, "workflow_id": workflow_id,
              "workflow": {}, "tasks": {}, "workflow_text": "", "tasks_text": "", "client_seconds": None}
    if not workflow_id:
        print(f"Workflow submission returned HTTP {submit_status} without a workflow_id.")
        return result
    workflow, tasks, workflow_text, tasks_text = wait_workflow(settings, workflow_id, timeout_seconds, poll_seconds, on_poll)
    result.update(workflow=workflow, tasks=tasks, workflow_text=workflow_text, tasks_text=tasks_text,
                  client_seconds=round(time.monotonic() - started, 3))
    return result


def collect_outputs(tasks: dict) -> dict:
    """Read each step's JSON output from the shared volume. Missing outputs are returned as None."""
    outputs = {}
    for step in PIPELINE:
        task = task_for(tasks, step["service"])
        refs = (task or {}).get("output_refs") or []
        uri = refs[0].get("uri") if refs else None
        text = read_volume_file(step["container"], uri) if uri else None
        outputs[step["service"]] = {"uri": uri, "text": text, "data": _json_or_none(text)}
    return outputs


def validate_outputs(outputs: dict, request: dict, workflow_id: str) -> list[dict]:
    """Semantic checks on the three Danish outputs for a structured run configuration."""
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})

    config = outputs["config_assistant"]["data"] or {}
    topology = outputs["topology_generator"]["data"] or {}
    render = outputs["draw_topology"]["data"] or {}
    for step in PIPELINE:
        uri = outputs[step["service"]]["uri"] or ""
        check(f"{step['service']} output retained", outputs[step["service"]]["data"] is not None, uri)
        check(f"{step['service']} output belongs to this workflow", uri.startswith(f"/data/{workflow_id}/"), uri)

    run_config = config.get("run_config", {})
    check("config marked valid", config.get("valid") is True, str(config.get("valid")))
    check("config has no warnings", config.get("warnings") == [], str(config.get("warnings")))
    check("config supplies match request", run_config.get("supplies") == request.get("supplies"), str(run_config.get("supplies")))
    check("config loads match request", run_config.get("loads") == request.get("loads"), str(run_config.get("loads")))

    networks = topology.get("networks") or []
    count = topology.get("topology_count") or 0
    signatures = [n.get("signature") for n in networks]
    recommended = (topology.get("recommended_network") or {}).get("signature")
    check("at least one topology generated", count > 0, str(count))
    check("network list matches topology_count", len(networks) == count, f"{len(networks)} networks")
    check("recommended network is one of the candidates", recommended in signatures, str(recommended))
    check("every network uses the requested supplies",
          all(set(n.get("supplies", [])) == set(request.get("supplies", [])) for n in networks) and bool(networks), "")
    check("every network uses the requested loads",
          all(set(n.get("loads", [])) == set(request.get("loads", [])) for n in networks) and bool(networks), "")

    drawings = render.get("drawings") or []
    check("drawing_count matches topology_count", render.get("drawing_count") == count, str(render.get("drawing_count")))
    check("drawing list matches drawing_count", len(drawings) == render.get("drawing_count"), f"{len(drawings)} drawings")
    check("every drawing belongs to this workflow",
          all(str(d.get("uri", "")).startswith(f"/data/{workflow_id}/") for d in drawings) and bool(drawings), "")
    return checks


def task_for(tasks: dict, service: str) -> dict | None:
    for task in tasks.get("tasks", []):
        if str(task.get("node_key", "")).startswith(f"{service}1:"):
            return task
    return None


def incomplete_tasks(tasks: dict) -> int:
    all_tasks = tasks.get("tasks", [])
    if not all_tasks:
        return -1
    return len([t for t in all_tasks if t.get("status") not in COMPLETE_STATES])


def orchestrator_timing(workflow: dict, tasks: dict) -> dict:
    """Times recorded by the orchestrator. Tasks only expose created_at and updated_at."""
    timing = {"DeliverySeconds": None}
    created = parse_iso(workflow.get("created_at"))
    previous = created
    last = None
    for step in PIPELINE:
        task = task_for(tasks, step["service"])
        updated = parse_iso(task.get("updated_at")) if task else None
        key = f"{step['method']}Seconds"
        timing[key] = round((updated - previous).total_seconds(), 3) if updated and previous else None
        previous = updated or previous
        last = updated or last
    if created and last:
        timing["DeliverySeconds"] = round((last - created).total_seconds(), 3)
    return timing


# Container helpers
def run_command(command: list[str], timeout: int = 600) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    except FileNotFoundError:
        return subprocess.CompletedProcess(command, 127, "", f"{command[0]} was not found")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(command, 124, "", f"{command[0]} timed out after {timeout} s")


def docker(*args: str, timeout: int = 600) -> subprocess.CompletedProcess:
    return run_command(["docker", *args], timeout=timeout)


def read_volume_file(container: str, uri: str) -> str | None:
    """Read a file DataReference from the shared denmark-node-data volume."""
    completed = docker("exec", container, "cat", uri, timeout=60)
    return completed.stdout if completed.returncode == 0 else None


def container_state(name: str) -> str:
    completed = docker("inspect", name, "--format",
                       "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}", timeout=30)
    return completed.stdout.strip() if completed.returncode == 0 else "missing"


def wait_container(name: str, timeout_seconds: int = 300) -> str:
    """Wait until a container is healthy or running, like Wait-T33Container."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        state = container_state(name)
        if state in ("healthy", "running"):
            print(f"Container {name} is {state}")
            return state
        print(f"Waiting for {name}; state={state}")
        time.sleep(5)
    raise Blocked(f"Container {name} did not become healthy/running within {timeout_seconds} seconds.")


def add_resource_samples(path: Path, prefix: list) -> None:
    """Append one docker stats snapshot per Danish or orchestrator container to a TSV file."""
    completed = docker("stats", "--no-stream", "--format",
                       "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}", timeout=60)
    timestamp = now_iso()
    with open(path, "a", encoding="utf-8") as handle:
        if completed.returncode != 0:
            handle.write("\t".join([timestamp, *map(str, prefix), "DOCKER_STATS_FAILED"]) + "\n")
            return
        for row in completed.stdout.splitlines():
            if re.search(r"orchestrator|dk-", row):
                handle.write("\t".join([timestamp, *map(str, prefix), row]) + "\n")


# Small utilities
def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def parse_iso(value) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def write_csv(path: Path, rows: list[dict]) -> None:
    """Write rows like Export-Csv -NoTypeInformation -Encoding utf8: quoted fields, UTF-8 with BOM."""
    import csv
    if not rows:
        path.write_text("", encoding="utf-8-sig")
        return
    with open(path, "w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()), quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(rows)


def topology_fingerprint(outputs: dict) -> str:
    """Hash of the generated candidate networks, used to compare repeated runs."""
    networks = (outputs.get("topology_generator", {}).get("data") or {}).get("networks")
    if networks is None:
        return ""
    return sha256_text(json.dumps(networks, sort_keys=True, separators=(",", ":")))


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest().upper()


def _json_or_none(text):
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def _json_or_empty(text: str) -> dict:
    try:
        value = json.loads(text)
        return value if isinstance(value, dict) else {"value": value}
    except (json.JSONDecodeError, TypeError):
        return {}
