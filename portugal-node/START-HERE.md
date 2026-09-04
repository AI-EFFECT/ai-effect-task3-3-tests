# Portugal node: start here

This is the Task 3.3 Portugal-node reproduction suite v1.1. Clone this repository to `C:\T33`, then run it from a Windows PowerShell terminal in VS Code.

It tests two routes separately:

| Route | Recorded baseline result | What this package does |
|---|---|---|
| Integrated Portugal route | Validated | Starts the Portugal services, runs the end-to-end workflow and saves its outputs. |
| Legacy-sidecar route | Blocked by an interface mismatch | Records the mismatch without changing the supplied source. |

The package uses copies of the Portugal source in disposable workspaces. It does not edit the original `tef-services` folder or the AI-EFFECT repository.

## Before you start

You need Docker Desktop running, Windows PowerShell 5.1 or newer, and these folders:

```text
C:\T33\ai-effect-wp3
C:\Users\as\OneDrive - Maynooth University\Projects_2025\AI-effect\Portugal_Node\tef-services\tef-services
C:\T33\ai-effect-task3-3-tests\portugal-node
```

Open the test-package folder in VS Code. Then open **Terminal → New Terminal** and run these commands exactly once:

```powershell
Set-Location C:\T33\ai-effect-task3-3-tests\portugal-node
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
Copy-Item .\Test-Settings.psd1.example .\Test-Settings.psd1
```

Open `Test-Settings.psd1` in VS Code. Change a path only if your local folders are in a different place. Do not change `ExpectedCommit`.

Create test-only keys in the same terminal. They are used only by local containers started for this test run:

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

## Run the integrated route

Run one command at a time. Each command creates a timestamped evidence folder under `C:\ae33pt-evidence`.

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
```

The expected technical outcome is a completed four-step workflow. The package proves that the services exchange data successfully. It does not assess whether the model is scientifically suitable for a production use case.

## Check the legacy-sidecar route

Run this separately, after the integrated route. It is expected to record a block on the current baseline.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\30-Prepare-Sidecar-Workspace.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\31-Start-Sidecar-Services.ps1
```

On the recorded baseline, script 31 waits for the legacy Data Provision startup record, then identifies that it starts as gRPC on port 50051 while the supplied sidecar configuration expects an HTTP service on port 600. This is an integration issue, not a reason to alter the test source. Do **not** run script 32 unless the Portugal owner gives you an approved compatible adapter or deployment configuration.

## Finish safely

Stop only Portugal test containers and save the final inventory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\35-Stop-Portugal-Test-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\99-Collect-Closeout-Evidence.ps1
```

## Repeat the tests

To make a fresh disposable workspace, stop Portugal test containers first. Then run these reset commands. They remove only named volumes beginning with `pt33-tef-`.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\35-Stop-Portugal-Test-Services.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\00-Prepare-Portugal-Fixture.ps1 -Reset
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\30-Prepare-Sidecar-Workspace.ps1 -Reset
```

Read [KNOWN-FINDINGS.md](KNOWN-FINDINGS.md) before raising an issue. It distinguishes supplied Portugal configuration findings from earlier test-harness corrections.
