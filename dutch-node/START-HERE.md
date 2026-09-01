# Dutch Node Task 3.3 — Reproduction Suite v1.1

This is the only script package to use for the frozen Dutch-node baseline. Do not mix it with earlier `v1.x`, `v2.0`, or `T33-Dutch-Tests` folders.

## First-time setup in VS Code

1. Extract the archive to `C:\T33`. The files appear directly in `C:\T33\T33-Dutch-Tests_v1.1`.
2. Open that folder in VS Code. Open a new PowerShell terminal and run:

```powershell
Set-Location C:\T33\T33-Dutch-Tests_v1.1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
Copy-Item .\Test-Settings.psd1.example .\Test-Settings.psd1
```

3. In `Test-Settings.psd1`, leave the supplied values unchanged for the recorded Dutch baseline: `RepositoryRoot = 'C:\ae33nl'` and the expected commit `22fbb6eca71265a61bc1f0cee16b6d03f372d554`.
4. Generate temporary test keys once in this terminal:

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
```

For HAI startup, set these local-only values in the same terminal:

```powershell
$env:HAI_SESSION_TOKEN_SECRET = New-TestSecret
$env:HAI_PUBLIC_BASE_URL = 'http://localhost:8443'
$env:HAI_PROXY_HOST_PORT = '8443'
$env:HAI_SESSION_SLOT_COUNT = '2'
$env:HAI_CAB_URL = 'http://frontend:80'
$env:HAI_SIM_ENV_NAME = 'Ressources/env_ICAPS_input_data_test'
```

## HAI simulator prerequisite

The HAI stack uses a local PowerGrid simulator image. The top-level HAI Compose
file refers to this image but does not build it itself. Script 29 is included to
make this dependency explicit. It safely verifies the image when it already
exists, or builds it from the pinned PowerGrid source in the frozen repository.

Run script 29 immediately before script 30. On the first run it can take several
minutes because Docker needs to build the image and install its dependencies.

## Run sequence

Always use the commands exactly as written. `-ExecutionPolicy Bypass` applies only to the child process; it does not make a permanent system change.

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
```

Run them one at a time, in this order. Send the output of each before continuing if you are recreating the original evidence with assistance.

## Expected baseline conclusions

- 00 core start: pass; orchestrator, synthesizer and benchmark become ready.
- 01 authentication: pass; missing and bad tokens are `401`; a valid token reaches the application.
- 10/20 workflow: service computation may complete, while the common HTTP `DataReference` handoff still rejects logical `GridData` or `BenchmarkResult` formats.
- 11: historical defect is a graph with edges but no pandapower lines/transformers.
- 21: retained benchmark artifact is valid and contains populated KPI leaves.
- 22: malformed algorithm safely returns a failed response and creates no artifact.
- 29: verifies or builds `powergrid-simulator-app:latest` from the frozen PowerGrid source. It does not change Dutch-node source files.
- 30: starts the HAI stack only after the simulator image is present. If it is absent, the script gives the exact next action instead of attempting an image pull.
- 31 proves two slots are admitted and a third is refused. It cleans up its own sessions.
- 32 is expected to confirm the known timeout-reclaim defect. It cleans up its own sessions.
- 33 is a recovery script only. Run it only after an interrupted HAI test, supplying the exact labelled task ID or IDs, for example: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\33-Clear-HAI-Test-Sessions.ps1 task_t33_hai_capacity1_...`.
- 34 checks signed proxy links: valid link `200`, altered token `403`.
- 35 sends clearly labelled synthetic trace and survey data. It checks technical completion, not a real human study.
- 36 checks service restart, persistence of an active session, and a clean new run.
- 40: supplementary only; the supplied Studio blueprint is a pipeline topology, not a service declaration.

Every script saves evidence to a new timestamped subfolder of `C:\ae33nl-evidence`. The scripts never modify the Dutch source tree, Compose files, dependency locks or submodule revisions. Advanced HAI tests create labelled local session state and then clean that state; their cleanup does not remove saved evidence.
