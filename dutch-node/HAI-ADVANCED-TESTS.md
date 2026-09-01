# Advanced HAI Test Sequence

These tests follow `29-Prepare-HAI-Simulator.ps1` and
`30-Attempt-HAI-Startup.ps1`. Run the matching numbered
PowerShell script in this folder. They were executed on the frozen baseline on
1 September 2026. Each script saves its own evidence folder.

## 31 — Two-slot capacity

`31-Test-HAI-Slot-Capacity.ps1` starts three `StartHumanAISession` requests with empty scenario, agent and survey
names, no KPI filter, and a short `session_timeout_seconds`. The first two must
return HTTP 200 with `status: pending` and inline participant links. The third
must return HTTP 200 with `status: failed` and:

`All 2 session slots are in use. Wait for a session to finish, or increase HAI_SESSION_SLOT_COUNT.`

Recorded result: **pass**.

## 32 — Timeout reclaim

`32-Test-HAI-Timeout-Reclaim.ps1` waits longer than the short session budget, verifies both session status endpoints,
then attempt a replacement session. Correct behaviour would be two failed
sessions and a pending replacement. The frozen runtime instead showed both
sessions as `running`, progress `20`, and rejected the replacement because both
slots were still occupied.

Recorded result: **confirmed defect**. `SessionService.expire_timed_out_sessions`
exists but `main.py` does not schedule it.

## 33 — Scoped cleanup

`33-Clear-HAI-Test-Sessions.ps1` is a recovery-only helper. Before using it, inspect `hai:slot:1` and `hai:slot:2` in `hai-redis`.
Only if they exactly name the labelled test sessions, reset each matching
simulator (`/hai/reset`) and survey (`/api/reset`), then remove those two slot
keys, session keys and set memberships. Never use `FLUSHDB` or `docker compose down -v`.

Recorded result: **pass**; both slots returned to free.

## 34 — Signed proxy link

`34-Test-HAI-Signed-Proxy-Link.ps1` starts one session. It keeps the token out of its console output.
Follow the GUI URL with an empty cookie jar. The redirect exchanges the token
for a cookie and the final GUI response must be HTTP 200. Append one character
to the token and repeat with a separate empty cookie jar; final response must
be HTTP 403. Then perform scoped cleanup.

Recorded result: **pass**: valid 200, altered token 403.

## 35 — Technical completion lifecycle

`35-Test-HAI-Technical-Lifecycle.ps1` is a technical fixture, not a participant study. It starts one session, obtains
the session token from its local link, then post clearly labelled synthetic JSON
to the public proxy routes:

* `POST /wp3/collect/session-trace`
* `POST /wp3/collect/survey-outcome`

Both must return 200. Fetch `/svc/hai/control/status/{task}` with the service
bearer token: expected `complete`, progress 100. Fetch `/control/output/{task}`
and the returned authenticated HTTP data URL. Verify the result artifact carries
both fixture documents and that the used slot is free.

Recorded result: **pass**.

## 36 — Restart and rerun isolation

`36-Test-HAI-Restart-And-Rerun.ps1` starts one active session, restarts only `hai-testing-service`, and waits for its
health check. The existing session must remain `running`, its signed GUI link
must return 200, and its slot must remain reserved. Use scoped cleanup, then
start and clean a new session. This verifies Redis-backed session persistence
and isolation of a subsequent run.

Recorded result: **pass**.

## Human validation boundary

None of tests 31–36 proves operator usability or the quality of real survey/KPI
data. A consenting participant must complete the GUI scenario and questionnaire
to create that separate type of evidence.
