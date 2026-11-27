<#
.SYNOPSIS
Static security review of the supplied Compose files for the platform core and each node (SEC-01 to SEC-04).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Reads the resolved Compose model and the raw Compose text.
Records host port bindings, authentication keys that silently default to empty, privileged settings, Docker socket
mounts, unpinned images and unpinned Python dependencies in build contexts. Nothing is started or changed.
The resolved model can contain interpolated secrets, so only reviewed extracts are saved.

.NOTES
Read README.md and START-HERE.md before running. Preserve the timestamped evidence folder.
#>
[CmdletBinding()]
param(
    [ValidateSet('All','Germany','Portugal','Netherlands')][string]$Node = 'All',
    [switch]$SkipCore
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

Invoke-T33SupTest -Settings $s -Label "10-compose-security-$($Node.ToLower())" -Body {
    param($e)
    Assert-T33SupPlatform $s | Out-Null

    $targets = New-Object System.Collections.Generic.List[object]
    if (-not $SkipCore) { $targets.Add([pscustomobject]@{ Scope = 'Core'; ComposeSet = $s.OrchestratorCompose }) }
    $names = if ($Node -eq 'All') { @($s.Nodes.Keys) } else { @($Node) }
    foreach ($name in $names) {
        $n = Get-T33SupNode $s $name
        foreach ($set in $n.ComposeSets) { $targets.Add([pscustomobject]@{ Scope = $name; ComposeSet = $set }) }
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $inventory = New-Object System.Collections.Generic.List[object]
    function Add-Finding($Scope, $Set, $Service, $Id, $Finding, $Detail) {
        $findings.Add([pscustomobject][ordered]@{ Scope = $Scope; ComposeSet = $Set; Service = $Service; TestId = $Id; Finding = $Finding; Detail = $Detail })
        Write-Host "FINDING $Id [$Scope/$Service] ${Finding}: $Detail"
    }
    $dataStorePattern = '(?i)(redis|clickhouse|postgres|mongo|mysql|mariadb|influx|minio|elastic|opensearch|rabbitmq)'

    foreach ($t in $targets) {
        $files = Get-T33ComposeFiles $t.ComposeSet

        # SEC-02: authentication keys that silently default to empty in the raw Compose text.
        foreach ($file in $files) {
            $raw = Get-Content -LiteralPath $file -Raw
            foreach ($m in [regex]::Matches($raw, '\$\{([A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD)[A-Za-z0-9_]*):?-\}')) {
                Add-Finding $t.Scope $t.ComposeSet (Split-Path $file -Leaf) 'SEC-02' 'authentication key defaults to empty' "$($m.Groups[1].Value) in $file; an unset variable silently disables the check"
            }
        }

        $model = Get-T33ComposeModel $t.ComposeSet
        foreach ($svc in $model.services.PSObject.Properties) {
            $name = $svc.Name; $d = $svc.Value
            $props = $d.PSObject.Properties.Name
            $image = if ($props -contains 'image') { [string]$d.image } else { '' }
            $built = $props -contains 'build'
            $isStore = ($image -match $dataStorePattern) -or ($name -match $dataStorePattern)

            # SEC-01: host port bindings
            $ports = @()
            if ($props -contains 'ports' -and $null -ne $d.ports) {
                foreach ($p in $d.ports) {
                    $hostIp = if ($p.PSObject.Properties.Name -contains 'host_ip' -and $p.host_ip) { [string]$p.host_ip } else { '0.0.0.0' }
                    $published = if ($p.PSObject.Properties.Name -contains 'published') { [string]$p.published } else { '' }
                    $ports += "${hostIp}:${published}->$($p.target)"
                    if ($hostIp -in @('0.0.0.0','::','')) {
                        $kind = if ($isStore) { 'data store published on all interfaces' } else { 'service published on all interfaces' }
                        Add-Finding $t.Scope $t.ComposeSet $name 'SEC-01' $kind "${hostIp}:${published} -> $($p.target)"
                    }
                }
            }

            # SEC-03: privileged settings and Docker socket
            if ($props -contains 'privileged' -and $d.privileged) { Add-Finding $t.Scope $t.ComposeSet $name 'SEC-03' 'privileged container' 'privileged: true' }
            if ($props -contains 'cap_add' -and $d.cap_add) { Add-Finding $t.Scope $t.ComposeSet $name 'SEC-03' 'added capabilities' (@($d.cap_add) -join ', ') }
            foreach ($ns in @('network_mode','pid','ipc')) {
                if ($props -contains $ns -and [string]$d.$ns -eq 'host') { Add-Finding $t.Scope $t.ComposeSet $name 'SEC-03' "host $ns namespace" "${ns}: host" }
            }
            if ($props -contains 'volumes' -and $null -ne $d.volumes) {
                foreach ($v in $d.volumes) {
                    $src = if ($v.PSObject.Properties.Name -contains 'source') { [string]$v.source } else { '' }
                    if ($src -match 'docker\.sock') { Add-Finding $t.Scope $t.ComposeSet $name 'SEC-03' 'Docker socket mounted' $src }
                }
            }

            # SEC-04: image provenance
            if ($image -and -not $built) {
                $tag = if ($image -match '@sha256:') { 'digest' } elseif ($image -match ':[^/]+$') { ($image -split ':')[-1] } else { '' }
                if ($tag -ne 'digest') {
                    $why = if ([string]::IsNullOrEmpty($tag)) { 'no tag (implicit latest)' } elseif ($tag -match '(?i)latest') { "floating tag '$tag'" } else { "tag '$tag' without digest" }
                    Add-Finding $t.Scope $t.ComposeSet $name 'SEC-04' 'pulled image not pinned by digest' "$image ($why)"
                }
            }
            if ($built) {
                $context = if ($d.build.PSObject.Properties.Name -contains 'context') { [string]$d.build.context } else { '' }
                if ($context -and (Test-Path $context)) {
                    $reqFiles = @(Get-ChildItem -LiteralPath $context -Recurse -Filter 'requirements*.txt' -File -ErrorAction SilentlyContinue | Select-Object -First 50)
                    $unpinned = 0; $total = 0
                    foreach ($rf in $reqFiles) {
                        foreach ($line in (Get-Content -LiteralPath $rf.FullName)) {
                            $l = ($line -split '#')[0].Trim()
                            if (-not $l -or $l.StartsWith('-')) { continue }
                            $total++
                            if ($l -notmatch '==') { $unpinned++ }
                        }
                    }
                    if ($unpinned -gt 0) { Add-Finding $t.Scope $t.ComposeSet $name 'SEC-04' 'unpinned Python dependencies in build context' "$unpinned of $total requirement lines lack an exact version (context $context)" }
                }
            }

            $inventory.Add([pscustomobject][ordered]@{
                Scope = $t.Scope; Service = $name; Image = $image; Built = $built; DataStore = $isStore
                Ports = ($ports -join ' '); Privileged = ($props -contains 'privileged' -and [bool]$d.privileged)
                RestartPolicy = if ($props -contains 'restart') { [string]$d.restart } else { '' }
            })
        }
    }

    Save-T33Csv (Join-Path $e 'compose-findings.csv') $findings
    Save-T33Csv (Join-Path $e 'compose-inventory.csv') $inventory
    $byId = $findings | Group-Object TestId | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{ node = $Node; targets = $targets; findings_by_test = @($byId); findings = $findings.Count })

    if (@($findings | Where-Object TestId -eq 'SEC-02').Count -gt 0) {
        return (New-T33Verdict 'DEFECT CONFIRMED' "authentication can be disabled silently by an unset variable. Findings: $($byId -join ', '). See compose-findings.csv.")
    }
    if ($findings.Count -gt 0) { return (New-T33Verdict 'FINDINGS RECORDED' "findings: $($byId -join ', '). See compose-findings.csv.") }
    return (New-T33Verdict 'PASS' 'no exposure, privilege, fail-open or provenance findings in the reviewed Compose files.')
}
