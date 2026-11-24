"""
Records the frozen source, tools, paths and keys before any Danish test runs.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import os
import platform

from _support import docker, run_command, run_test, setting_path


def body(settings, evidence):
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": ok, "detail": detail})
        print(f"{'OK  ' if ok else 'FAIL'}  {name}: {detail}")

    for key in ("RepositoryRoot", "DenmarkRoot", "OrchestratorCompose", "DenmarkCompose"):
        path = setting_path(settings, key)
        check(f"path {key}", path.exists(), str(path))

    generator = setting_path(settings, "RepositoryRoot") / "scripts" / "onboarding-export-generator.py"
    check("onboarding export generator", generator.exists(), str(generator))

    repo = setting_path(settings, "RepositoryRoot")
    head = run_command(["git", "-C", str(repo), "rev-parse", "HEAD"])
    actual = head.stdout.strip()
    check("source commit", actual == settings["ExpectedCommit"],
          f"found {actual or head.stderr.strip()}, expected {settings['ExpectedCommit']}")

    status = run_command(["git", "-C", str(repo), "status", "--porcelain"])
    changed = [line for line in status.stdout.splitlines() if line.strip()]
    check("clean working tree", status.returncode == 0 and not changed,
          "clean" if not changed else f"{len(changed)} changed files")

    engine = docker("version", "--format", "{{.Server.Version}}", timeout=60)
    check("docker engine running", engine.returncode == 0, engine.stdout.strip() or engine.stderr.strip())

    compose = docker("compose", "version", "--short", timeout=60)
    check("docker compose available", compose.returncode == 0, compose.stdout.strip() or compose.stderr.strip())

    for key in ("ORCHESTRATOR_API_KEY", "SERVICE_API_KEY"):
        present = bool(os.environ.get(key, "").strip())
        check(f"environment {key}", present, "set" if present else "not set")

    evidence.save_json("preflight.json", {
        "node": "Danish",
        "machine": platform.platform(),
        "python": platform.python_version(),
        "expected_commit": settings["ExpectedCommit"],
        "observed_commit": actual,
        "docker_engine": engine.stdout.strip(),
        "docker_compose": compose.stdout.strip(),
        "checks": checks,
    })

    failed = [c["check"] for c in checks if not c["ok"]]
    if failed:
        return "BLOCKED", f"preflight failed: {', '.join(failed)}. Fix these before running other tests."
    return "PASS", "frozen source, Docker, Compose, paths and keys are ready for the Danish node tests."


if __name__ == "__main__":
    run_test("00-preflight", body)
