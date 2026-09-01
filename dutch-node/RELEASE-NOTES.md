# Release notes — v1.1

This release replaces every earlier Dutch-node test-script package. Use this
package on its own; do not copy scripts from older folders into it.

What changed in v1.1:

- Added `29-Prepare-HAI-Simulator.ps1`. It verifies or builds the required local
  `powergrid-simulator-app:latest` image from the pinned PowerGrid source.
- Script 30 now checks for that image before starting HAI. If it is missing, it
  stops with the exact corrective action instead of leaving an unclear Docker
  pull failure in the log.
- `START-HERE.md` includes the new step and explains why it is required.

This closes the only release-packaging gap identified during the final handover
review: the HAI test sequence is now self-contained for a clean machine that
has the stated repository baseline and Docker prerequisites.

What changed in v1.0:

What changed:

- The synthesizer artifact validator now reads the actual `GridData` schema. Empty pandapower tables are counted as zero instead of causing a PowerShell property error.
- The advanced HAI checks are now real PowerShell scripts: capacity, timeout/reclaim, scoped cleanup, signed links, technical lifecycle, and restart/rerun.
- Signed-link checks use temporary cookie jars, so they test the real token-to-cookie redirect path.
- The lifecycle check uses the documented public collection routes and validates the returned result reference and artifact.
- `START-HERE.md` has one complete run order and states which test records a known defect rather than stopping the suite.

The expected frozen-baseline outcome has not changed. In particular, the
synthesizer topology and shared workflow format issues remain defects, while
the HAI timeout-reclaim test is expected to confirm a known defect.
