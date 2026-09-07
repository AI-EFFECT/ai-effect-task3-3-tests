# Advanced HAI Test Sequence

Run these tests after `29-Prepare-HAI-Simulator.ps1` and
`30-Attempt-HAI-Startup.ps1`. The sequence was reproduced on the frozen Dutch
baseline during the 7-8 September 2026 closure run. Every script uses labelled
test sessions and saves timestamped evidence.

## 31 - Two-slot capacity

`31-Test-HAI-Slot-Capacity.ps1` submits three sessions to the two-slot default
configuration. Two must be admitted and the third must be safely refused with a
clear capacity message. Recorded result: **pass**.

## 32 - Timeout reclaim

`32-Test-HAI-Timeout-Reclaim.ps1` gives two sessions a 30-second budget, waits
50 seconds and requests a replacement. Both expired sessions remained running
and occupied the slots. Recorded result: **confirmed defect**.

## 33 - Scoped recovery

`33-Clear-HAI-Test-Sessions.ps1` is an emergency helper for interrupted tests.
Supply only exact labelled Task 3.3 task IDs. It resets matching simulator and
survey instances and removes their scoped session records. Never use `FLUSHDB`
or `docker compose down -v` as a test cleanup shortcut.

## 34 - Signed proxy link

`34-Test-HAI-Signed-Proxy-Link.ps1` verifies the token-to-cookie redirect with
separate cookie jars. The valid link returned `200`; a one-character token
change returned `403`. Recorded result: **pass**.

## 35 - Technical completion lifecycle

`35-Test-HAI-Technical-Lifecycle.ps1` posts labelled synthetic trace and survey
fixtures, checks completed status and output, verifies the artifact carries both
fixtures and confirms slot release. It is not a participant study. Recorded
result: **pass**.

## 36 - Restart and rerun

`36-Test-HAI-Restart-And-Rerun.ps1` restarts only the HAI control service. The
active session remained reserved and accessible, then a clean new run started
after scoped cleanup. Recorded result: **pass**. This does not cover Docker-host,
Redis-volume or full-machine recovery.

## 51 - Expert UI/UX review

`51-Record-HAI-UX-Review.ps1 -Reviewer 'NAME' -StartReviewSession` creates a
labelled 30-minute review session and copies its signed URL to the Windows
clipboard without recording the token. It requires explicit confirmation of a
personally observed live session, collects ten heuristic ratings and removes the
session afterward.

Recorded result: **findings recorded**, mean `3.2/5`; entry/task clarity and
error recovery were rated `2/5`. The raw notes are brief and include an internal
wording inconsistency, so the formal report must describe only supported themes
and record clarification rather than rewrite the original evidence.

## Evidence boundary

Tests 31-36 validate technical behaviour. Script 51 is an expert heuristic
review. None constitutes a representative usability study, accessibility
certification, completed operator study or validation of real survey/KPI data.

