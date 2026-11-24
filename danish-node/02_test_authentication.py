"""
Checks orchestrator and Danish service authentication.

Part of the AI-EFFECT Task 3.3 Danish node test package. It records evidence for one defined test or review step and should be interpreted only within that stated scope.

Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder, including failed or blocked results.
"""
from __future__ import annotations

import os

from _support import PIPELINE, Blocked, assert_baseline, bearer, health_urls, http, require_keys, run_test, wait_http_ok

PROBE_TASK = "t33-dk-auth-probe"


def body(settings, evidence):
    assert_baseline(settings)
    require_keys()
    wait_http_ok(f"{settings['OrchestratorUrl']}/health")
    for url in health_urls(settings).values():
        wait_http_ok(url, timeout_seconds=60)

    results = []

    def probe(target, case, url, headers, expected):
        status, content = http("GET", url, headers)
        if status == 0:
            raise Blocked(f"{target} could not be reached at {url}: {content}")
        ok = status in expected
        results.append({"target": target, "case": case, "url": url, "status": status,
                        "expected": list(expected), "ok": ok})
        evidence.save_text(f"{target}-{case}.txt", f"HTTP {status}\n{content}")
        print(f"{'OK  ' if ok else 'FAIL'}  {target} {case}: HTTP {status} (expected {list(expected)})")
        return ok

    orchestrator_url = f"{settings['OrchestratorUrl']}/workflows/{PROBE_TASK}"
    orchestrator_ok = all([
        probe("orchestrator", "missing-token", orchestrator_url, {}, (401,)),
        probe("orchestrator", "invalid-token", orchestrator_url, bearer("t33-invalid-token"), (401,)),
        probe("orchestrator", "valid-token", orchestrator_url, bearer(os.environ["ORCHESTRATOR_API_KEY"]), (404,)),
    ])

    services_enforced = True
    for step in PIPELINE:
        base = settings[step["url_setting"]].rstrip("/")
        control_url = f"{base}/control/status/{PROBE_TASK}"
        missing = probe(step["service"], "missing-token", control_url, {}, (401,))
        invalid = probe(step["service"], "invalid-token", control_url, bearer("t33-invalid-token"), (401,))
        services_enforced = services_enforced and missing and invalid
        probe(step["service"], "health-open", health_urls(settings)[step["service"]], {}, (200,))

    evidence.save_json("authentication-results.json", results)

    if not orchestrator_ok:
        return "FAIL", ("orchestrator authentication did not behave as expected. Check that ORCHESTRATOR_API_KEY "
                        "was set when the orchestrator stack was started.")
    if not services_enforced:
        return "DEFECT CONFIRMED", ("orchestrator authentication passed, but one or more Danish control endpoints "
                                    "accept calls without a valid token as supplied. The supplied docker-compose.yml "
                                    "does not pass SERVICE_API_KEY to the services. See DK-SEC-01.")
    return "PASS", "orchestrator and all Danish control endpoints rejected missing and invalid tokens."


if __name__ == "__main__":
    run_test("02-authentication", body)
