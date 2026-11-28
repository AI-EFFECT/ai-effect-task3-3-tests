# Supplementary tests: start here

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7, Docker Desktop with Compose v2, Git, and Python 3.10 or newer on `PATH` (for the platform's export generator).
- **At least 30 GB free** on the system drive (Docker data) and on the evidence drive. Script 00 blocks below the `MinimumFreeGB` setting. Volume backups in script 23 can need several GB more; use `-BackupRoot` to put them on another drive.
- A test machine where the shared orchestrator can be restarted and its Redis state deleted. Scripts 21, 22, 24 and 25 do both. **Stop or finish any other work on the orchestrator first.**

## Local layout

```text
C:\T33\ai-effect-wp3          platform, checked out at bfe655d6dc58b49dd1e7b09730083971fbf3d29b
C:\T33\tef-services            partner-supplied Portuguese TEF source (as for the Portuguese suite)
C:\T33\pt33-tef-integrated     Portuguese workspace created by portugal-node\00-Prepare-Portugal-Fixture.ps1
C:\ae33nl                      Dutch fork, checked out at 22fbb6eca71265a61bc1f0cee16b6d03f372d554
C:\T33\ai-effect-task3-3-tests this repository
C:\ae33sup-evidence            evidence for this package
```

```powershell
git clone https://github.com/AI-EFFECT/ai-effect-wp3.git C:\T33\ai-effect-wp3
git -C C:\T33\ai-effect-wp3 checkout bfe655d6dc58b49dd1e7b09730083971fbf3d29b
```

Copy `Test-Settings.psd1.example` to `Test-Settings.psd1` and adapt only the paths.

## Keys

Use the same method as the node runbooks: create random temporary keys in the terminal you will use for every script, before starting any stack.

```powershell
function New-TestSecret { $b = New-Object byte[] 32; $r = [Security.Cryptography.RandomNumberGenerator]::Create(); $r.GetBytes($b); $r.Dispose(); -join ($b | ForEach-Object { $_.ToString('x2') }) }
$env:ORCHESTRATOR_API_KEY = New-TestSecret
$env:SERVICE_API_KEY = New-TestSecret
```

## Step 1: confirm the new baseline with the node suites

German and Portuguese node code is unchanged since the September baseline, but the orchestrator changed. Before running this package, rerun with the platform at `bfe655d`:

- German suite: scripts 00, 01, 02 and 40;
- Portuguese suite: scripts 00, 01, 02, 10, 11 and 20;
- Dutch suite: scripts 00 and 01, and the HAI startup scripts 29 and 30.

Each node suite checks its own `ExpectedCommit`. Use a copy of the node's `Test-Settings.psd1` with `ExpectedCommit` set to the new baseline, and record this in the node's release notes. Keep the node stacks running: the tests below need them.

## Step 2: run order

```text
.\00-Preflight.ps1
.\10-Scan-Compose-Security.ps1
.\11-Inspect-Runtime-Security.ps1 -Node Core
.\11-Inspect-Runtime-Security.ps1 -Node Germany          (repeat for Portugal and Netherlands)
.\20-Prepare-Vendor-Pipeline.ps1
.\31-Test-Template-Concurrency.ps1
.\30-Test-Vendor-Exchange.ps1 -NegativeCases
.\30-Test-Vendor-Exchange.ps1 -Node Portugal -SourceWorkflowId <id from the Portuguese script 20 evidence>
.\30-Test-Vendor-Exchange.ps1 -Node Germany -SourceWorkflowId <id from a German workflow submission>
.\30-Test-Vendor-Exchange.ps1 -Node Netherlands -SourceWorkflowId <id from the Dutch script 10 or 20 evidence>
.\23-Test-Volume-Backup-Restore.ps1 -Node Portugal       (repeat for Germany and Netherlands)
.\21-Test-Orchestrator-Restart-Midrun.ps1 -Component Worker
.\21-Test-Orchestrator-Restart-Midrun.ps1 -Component Api
.\21-Test-Orchestrator-Restart-Midrun.ps1 -Component Redis
.\22-Test-Orchestrator-State-Recreate.ps1
.\24-Record-Before-Engine-Restart.ps1
   -> restart Docker Desktop (whale icon > Restart) and wait until it is running
.\25-Verify-After-Engine-Restart.ps1
.\99-Collect-Closeout.ps1
```

Notes on specific scripts:

- **Script 30 on the German node.** The German workflow cannot complete without VILLASnode, but the outputs of its completed tasks (for example the data provider) can still be exchanged. If a node's workflow keeps no usable reference, save one DataReference as JSON (`{"protocol": ..., "uri": ..., "format": ...}`) and pass `-SourceReferenceFile`.
- **Script 31** runs before the restart tests on purpose, so it measures the template on a clean orchestrator.
- **Script 22** deletes all orchestrator state held only in Redis. Run it after the node-level tests.

## Step 3: UX evaluation

Follow [UX-EVALUATION-PROTOCOL.md](UX-EVALUATION-PROTOCOL.md). For each evaluator and interface:

```text
.\40-New-UX-Evaluation-Forms.ps1 -Evaluator E1 -Interface Dutch-HAI
```

When all forms are complete:

```text
.\41-Summarise-UX-Evaluation.ps1
```

## Reading results

Every script writes a timestamped folder under `EvidenceRoot` and ends with one `RESULT:` line. Read that line and the structured summary, not the exit code. `ERROR` means the harness failed: fix it and rerun, keeping the failed evidence. Preserve failed and blocked runs as well as passes.

## Stopping

```powershell
docker compose -f C:\T33\t33-vendor\docker-compose.yml down
Remove-Item Env:\ORCHESTRATOR_API_KEY, Env:\SERVICE_API_KEY -ErrorAction SilentlyContinue
```

Use `down --volumes` on the vendor project only when you no longer need its evidence data. Never use it on a node or orchestrator project as a cleanup shortcut.
