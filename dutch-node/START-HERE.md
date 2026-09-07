# Dutch Node Task 3.3 - Reproduction and Closure Suite v1.2

Use this package on its own for the frozen Dutch-node baseline. Do not mix its
scripts with earlier local packages. The recorded source is
`paulban/ai-effect-wp3` at commit
`22fbb6eca71265a61bc1f0cee16b6d03f372d554` with pinned submodules.

See [TEST-RESULTS-SUMMARY.md](TEST-RESULTS-SUMMARY.md) for the validated outcome.

## Source preparation

```powershell
git clone --no-checkout https://github.com/paulban/ai-effect-wp3.git C:\ae33nl
git -C C:\ae33nl checkout --detach 22fbb6eca71265a61bc1f0cee16b6d03f372d554
git -C C:\ae33nl submodule update --init --recursive
git -C C:\ae33nl status --short
```

The final command must return no changes. Copy `Test-Settings.psd1.example` to
the local-only `Test-Settings.psd1`; do not commit that file.

## Temporary test configuration

Create fresh keys once in the PowerShell terminal used for the run:

```powershell
function New-TestSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    -join ($bytes | ForEach-Object { $_.ToString('x2') })
}
$env:ORCHESTRATOR_API_KEY = New-TestSecret
$env:SERVICE_API_KEY = New-TestSecret
$env:NODE_PUBLIC_BASE_URL = 'http://localhost:8443'
$env:HAI_SESSION_TOKEN_SECRET = New-TestSecret
$env:HAI_PUBLIC_BASE_URL = 'http://localhost:8443'
$env:HAI_PROXY_HOST_PORT = '8443'
$env:HAI_SESSION_SLOT_COUNT = '2'
$env:HAI_CAB_URL = 'http://frontend:80'
$env:HAI_SIM_ENV_NAME = 'Ressources/env_ICAPS_input_data_test'
```

Do not print, paste or save the key values. If a terminal is replaced while
containers remain running, restart the stack with new keys or safely confirm
that the terminal keys match the running test configuration before continuing.

## Run sequence

Run one command at a time:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-Start-Core-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\01-Test-Authentication.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\10-Test-Synthesizer.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\11-Validate-Synthesizer-Artifact.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\20-Test-Benchmark.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\21-Validate-Benchmark-Artifact.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\22-Test-Invalid-Algorithm.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\29-Prepare-HAI-Simulator.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\30-Attempt-HAI-Startup.ps1 -BuildImages
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\31-Test-HAI-Slot-Capacity.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\32-Test-HAI-Timeout-Reclaim.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\34-Test-HAI-Signed-Proxy-Link.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\35-Test-HAI-Technical-Lifecycle.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\36-Test-HAI-Restart-And-Rerun.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\40-Check-Studio-Manifest.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\50-Measure-Dutch-Reference.ps1 -Repetitions 3 -Workload Both
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\51-Record-HAI-UX-Review.ps1 -Reviewer 'REVIEWER NAME' -StartReviewSession
```

Script 51 copies a signed URL to the Windows clipboard without writing it to
the transcript. Inspect the live session personally, then enter honest ratings
and specific observations. This is an expert heuristic review, not a participant
study.

## Expected baseline conclusions

- Core startup and authentication pass.
- Synthesizer and benchmark services retain artifacts, but their workflows fail
  at the shared logical-format/DataReference boundary.
- The synthesizer graph contains edges while its pandapower lines and
  transformers are empty: a semantic-output defect.
- The retained benchmark artifact parses and contains populated KPI values.
- Invalid algorithm input is rejected without creating an artifact.
- Two HAI sessions are admitted and a third is safely refused.
- Timed-out HAI sessions are not reclaimed: a confirmed lifecycle defect.
- Signed-link tampering is rejected; normal lifecycle and service restart pass.
- The supplied Studio blueprint is pipeline topology, not a service declaration;
  this is supplementary because Solution Studio is outside the formal WP scope.
- Script 50 records short repeatability/resource references only. It does not
  establish scalability or production acceptance limits.
- Script 51 records an expert UI/UX assessment and must not be represented as a
  human-subject evaluation.

## Safety and evidence

Each run writes a new timestamped folder under `C:\ae33nl-evidence`. Scripts do
not modify the Dutch source, Compose files, dependency locks or submodule
revisions. Do not publish evidence or local configuration until it has been
scanned for credentials and reviewed for participant or sensitive data.

