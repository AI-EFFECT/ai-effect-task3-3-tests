"""
Starts the orchestrator and Danish node services and generates the workflow export.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time

from _support import (OLLAMA_CONTAINER, PIPELINE, Blocked, assert_baseline, docker, health_urls,
                      require_keys, run_test, setting_path, wait_container, wait_http_ok)

parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
parser.add_argument("--timeout-seconds", type=int, default=1800,
                    help="Limit for builds and the Ollama model download (60-3600).")
parser.add_argument("--skip-ollama", action="store_true",
                    help="Do not prepare the Ollama model. Script 12 will then be blocked.")
args = parser.parse_args()


def compose_up(compose_file, extra, timeout):
    print(f"docker compose -f {compose_file} up -d --build {' '.join(extra)}")
    completed = docker("compose", "-f", str(compose_file), "up", "-d", "--build", *extra, timeout=timeout)
    print(completed.stdout[-4000:])
    if completed.returncode != 0:
        print(completed.stderr[-4000:])
        raise Blocked(f"docker compose up failed for {compose_file}. See run.txt.")


def find_orchestrator_api():
    names = docker("ps", "--format", "{{.Names}}", timeout=60).stdout.split()
    matches = [name for name in names if re.match(r"^orchestrator-api(-\d+)?$", name)]
    if not matches:
        raise Blocked("The orchestrator API container is not running.")
    return matches[0]


def body(settings, evidence):
    commit = assert_baseline(settings)
    require_keys()
    timings = {}

    if docker("network", "inspect", "ai-effect-services", timeout=60).returncode == 0:
        print("Using the existing shared Docker network: ai-effect-services")
    else:
        print("Creating the shared Docker network: ai-effect-services")
        if docker("network", "create", "ai-effect-services", timeout=60).returncode != 0:
            raise Blocked("Could not create the ai-effect-services Docker network.")

    started = time.monotonic()
    compose_up(setting_path(settings, "OrchestratorCompose"), [], args.timeout_seconds)
    api_container = find_orchestrator_api()
    wait_container(api_container)
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    timings["OrchestratorStartSeconds"] = round(time.monotonic() - started, 3)

    started = time.monotonic()
    compose_up(setting_path(settings, "DenmarkCompose"), ["--remove-orphans"], args.timeout_seconds)
    for step in PIPELINE:
        wait_container(step["container"])
    for service, url in health_urls(settings).items():
        wait_http_ok(url)
    timings["DanishServicesStartSeconds"] = round(time.monotonic() - started, 3)

    ollama_ready = False
    if args.skip_ollama:
        print("Skipping Ollama model preparation by request.")
    else:
        model = settings["OllamaModel"]
        started = time.monotonic()
        if docker("exec", OLLAMA_CONTAINER, "ollama", "show", model, timeout=120).returncode == 0:
            print(f"Ollama model is already present: {model}")
            ollama_ready = True
        else:
            print(f"Downloading local Ollama model: {model}")
            pulled = docker("exec", OLLAMA_CONTAINER, "ollama", "pull", model, timeout=args.timeout_seconds)
            print(pulled.stdout[-2000:] or pulled.stderr[-2000:])
            ollama_ready = pulled.returncode == 0
        timings["OllamaPrepareSeconds"] = round(time.monotonic() - started, 3)

    denmark_root = setting_path(settings, "DenmarkRoot")
    generator = setting_path(settings, "RepositoryRoot") / "scripts" / "onboarding-export-generator.py"
    print(f"Generating the onboarding export with {generator}")
    generated = subprocess.run([sys.executable, str(generator), str(denmark_root), "export", "--overwrite", "--zip"],
                               cwd=str(denmark_root), capture_output=True, text=True, encoding="utf-8", errors="replace")
    evidence.save_text("export-generator.txt", generated.stdout + generated.stderr)
    blueprint = denmark_root / "export" / "blueprint.json"
    dockerinfo = denmark_root / "export" / "dockerinfo.json"
    if generated.returncode != 0 or not blueprint.exists() or not dockerinfo.exists():
        raise Blocked("The onboarding export generator did not produce blueprint.json and dockerinfo.json.")
    evidence.save_text("blueprint.json", blueprint.read_text(encoding="utf-8"))
    evidence.save_text("dockerinfo.json", dockerinfo.read_text(encoding="utf-8"))

    inventory = docker("ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}", timeout=60).stdout
    evidence.save_text("container-inventory.tsv", "name\timage\tstatus\n" + inventory)
    evidence.save_json("summary.json", {
        "commit": commit,
        "orchestrator_api_container": api_container,
        "timings": timings,
        "ollama_model": settings["OllamaModel"],
        "ollama_ready": ollama_ready,
        "export": str(blueprint.parent),
    })

    message = ("orchestrator and Danish pipeline services are healthy and the workflow export was generated. "
               "Startup times include any image builds, so they are cold-start references only.")
    if not ollama_ready:
        message += " The Ollama model is not ready, so script 12 will be blocked."
    return "PASS", message


if __name__ == "__main__":
    run_test("01-start-services", body)
