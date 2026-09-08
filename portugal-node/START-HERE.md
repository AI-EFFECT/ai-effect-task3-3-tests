# Portugal node: start here

This is the AI-EFFECT Task 3.3 Portugal-node reproduction and conditional-closure suite v1.2. It tests two routes without editing the supplied Portugal source.

| Route | Validated result | Evidence boundary |
|---|---|---|
| Integrated route | Pass | Four-stage workflow, access control, input/output contracts, safe invalid-input handling, three-run repeatability, container restart/rerun and two-workflow bounded concurrency. |
| Legacy-sidecar route | Blocked as supplied | Data Provision exposes gRPC on `50051`; the supplied sidecar expects HTTP on `600`. Script 32 is prohibited until an approved compatible adapter or configuration is supplied. |

The scripts copy the external TEF source into marked disposable workspaces. They do not clean, reset or modify the original external source or the frozen AI-EFFECT repository.

## Prerequisites

- Docker Desktop
- Windows PowerShell 5.1 or newer
- Frozen AI-EFFECT source commit `486ccc702bb2afca79fb7d31258d62ee0f94dbfc`
- Supplied external Portugal `tef-services` source and `real_data.csv`

```powershell
Set-Location C:\T33\ai-effect-task3-3-tests\portugal-node
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
Copy-Item .\Test-Settings.psd1.example .\Test-Settings.psd1
```

Review `Test-Settings.psd1`. Change local paths only; do not change `ExpectedCommit`. Keep the external TEF source exactly as supplied, even when its Git working tree contains the partner-provided integration changes.

Create temporary keys in the same terminal without displaying them:

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

## Integrated route

Run one command at a time. Each script writes timestamped evidence under `C:\ae33pt-evidence`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-Prepare-Portugal-Fixture.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\01-Start-Core-And-Portugal-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\02-Test-Orchestrator-Authentication.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\03-Record-Knowledge-Store-Health-Configuration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\04-Record-Synthetic-Data-Health-Configuration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\10-Test-Portugal-Data-Load.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\11-Test-Portugal-Feature-Engineering.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\20-Test-Portugal-Workflow.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\22-Test-Portugal-Invalid-Input.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\23-Test-Repeatability-And-Performance.ps1 -Repetitions 3 -MaxRows 1000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\24-Test-Restart-And-Rerun.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\25-Test-Bounded-Concurrency.ps1 -ParallelWorkflows 2 -MaxRows 1000
```

Scripts 23-25 are bounded T3.3 closure checks. They do not establish production performance, an SLA, a capacity limit or scalability. Those claims belong to Task 3.4 under controlled monitoring conditions.

## Legacy-sidecar compatibility gate

Run after the integrated functional checks. If either workspace already exists, use `-Reset` only after verifying its `.t33-portugal-workspace.json` safety marker.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\30-Prepare-Sidecar-Workspace.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\31-Start-Sidecar-Services.ps1
```

Script 31 stops only the disposable integrated Portugal containers because the two variants reuse host ports. On the validated baseline it reports `BLOCKED AS SUPPLIED`. Do not run script 32 unless the Portugal owner supplies an approved compatible adapter or deployment configuration.

## Close out safely

First collect runtime inventory while the successful stack is running, then stop the test containers:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\99-Collect-Closeout-Evidence.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\35-Stop-Portugal-Test-Services.ps1
$s = Import-PowerShellDataFile .\Test-Settings.psd1
docker compose -f $s.OrchestratorCompose down
Remove-Item Env:\ORCHESTRATOR_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:\SERVICE_API_KEY -ErrorAction SilentlyContinue
```

Source folders, workspaces, named volumes and evidence are retained. Do not publish evidence until it has been reviewed for credentials, personal data and sensitive local paths.

See [KNOWN-FINDINGS.md](KNOWN-FINDINGS.md) and [TEST-RESULTS-SUMMARY.md](TEST-RESULTS-SUMMARY.md).

