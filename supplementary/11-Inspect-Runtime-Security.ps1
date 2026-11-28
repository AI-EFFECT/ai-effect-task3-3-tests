<#
.SYNOPSIS
Runtime security checks on running core and node containers (SEC-03 to SEC-08).

.DESCRIPTION
Part of the AI-EFFECT Task 3.3 supplementary test package. Inspects privileges, users, port bindings, image digests
and restart policies; probes control endpoints without a token and with an invalid token; checks whether published
data stores answer without credentials; and counts service keys stored in the orchestrator's Redis with their expiry.

Probes are non-destructive: control endpoints receive an empty body ({}) that cannot start work, so an enforced check
answers 401 or 403 and an unenforced one answers 422 (request reached validation). Stored key values are never read.

.NOTES
Start the core and the node first. Read README.md and START-HERE.md before running. Preserve the evidence folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Core','Germany','Portugal','Netherlands')][string]$Node
)

. (Join-Path $PSScriptRoot '_Supplementary.ps1')
$s = Read-T33SupSettings

function Test-T33RedisNoAuth([string]$HostName, [int]$Port) {
    try {
        $client = New-Object Net.Sockets.TcpClient
        $connect = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(3000)) { $client.Close(); return 'no connection' }
        $client.EndConnect($connect)
        $stream = $client.GetStream(); $stream.ReadTimeout = 3000
        $bytes = [Text.Encoding]::ASCII.GetBytes("PING`r`n"); $stream.Write($bytes, 0, $bytes.Length)
        $buffer = New-Object byte[] 256; $read = $stream.Read($buffer, 0, $buffer.Length)
        $client.Close()
        return ([Text.Encoding]::ASCII.GetString($buffer, 0, $read)).Trim()
    } catch { return "error: $($_.Exception.Message)" }
}

Invoke-T33SupTest -Settings $s -Label "11-runtime-security-$($Node.ToLower())" -Body {
    param($e)
    Assert-T33SupPlatform $s | Out-Null
    Require-T33SupKeys

    $containers = if ($Node -eq 'Core') { Get-T33CoreContainers } else { Get-T33NodeContainers (Get-T33SupNode $s $Node) }
    $containers = @($containers | Where-Object { (Get-T33ContainerState $_) -in @('running','healthy','unhealthy','starting') })
    if ($containers.Count -eq 0) { Stop-T33Blocked "no running containers were found for $Node. Start them first." }

    $findings = New-Object System.Collections.Generic.List[object]
    $inventory = New-Object System.Collections.Generic.List[object]
    $probes = New-Object System.Collections.Generic.List[object]
    function Add-Finding($Container, $Id, $Finding, $Detail) {
        $findings.Add([pscustomobject][ordered]@{ Container = $Container; TestId = $Id; Finding = $Finding; Detail = $Detail })
        Write-Host "FINDING $Id [$Container] ${Finding}: $Detail"
    }
    $dataStorePattern = '(?i)(redis|clickhouse|postgres|mongo|mysql|mariadb|influx|minio)'

    foreach ($c in $containers) {
        $info = (Invoke-T33Docker @('inspect',$c)).Output | ConvertFrom-Json
        $info = @($info)[0]
        $hc = $info.HostConfig; $cfg = $info.Config
        $imageRef = [string]$cfg.Image
        $digest = (Invoke-T33Docker @('image','inspect',$info.Image,'--format','{{join .RepoDigests " "}}') -AllowFailure).Output.Trim()
        $user = [string]$cfg.User
        $isRoot = [string]::IsNullOrWhiteSpace($user) -or $user -in @('root','0','0:0')
        $restart = [string]$hc.RestartPolicy.Name

        if ($hc.Privileged) { Add-Finding $c 'SEC-03' 'privileged container' 'Privileged=true' }
        if ($null -ne $hc.CapAdd -and @($hc.CapAdd).Count -gt 0) { Add-Finding $c 'SEC-03' 'added capabilities' (@($hc.CapAdd) -join ', ') }
        if ([string]$hc.NetworkMode -eq 'host') { Add-Finding $c 'SEC-03' 'host network namespace' 'NetworkMode=host' }
        foreach ($m in @($info.Mounts)) { if ([string]$m.Source -match 'docker\.sock') { Add-Finding $c 'SEC-03' 'Docker socket mounted' $m.Source } }
        if ([string]::IsNullOrWhiteSpace($digest)) { Add-Finding $c 'SEC-04' 'no registry digest recorded' "$imageRef (locally built or untracked image $($info.Image))" }
        if ($isRoot) { Add-Finding $c 'SEC-05' 'runs as root' $(if ($user) { "User=$user" } else { 'no User set' }) }

        $bindings = New-Object System.Collections.Generic.List[string]
        if ($null -ne $hc.PortBindings) {
            foreach ($pb in $hc.PortBindings.PSObject.Properties) {
                foreach ($b in @($pb.Value)) {
                    if ($null -eq $b) { continue }
                    $hostIp = if ([string]::IsNullOrEmpty([string]$b.HostIp)) { '0.0.0.0' } else { [string]$b.HostIp }
                    $bindings.Add("${hostIp}:$($b.HostPort)->$($pb.Name)")
                    if (-not ($pb.Name -like '*/tcp')) { continue }
                    $port = [int]$b.HostPort
                    $target = "http://127.0.0.1:$port"
                    $isStore = ($imageRef -match $dataStorePattern) -or ($c -match $dataStorePattern)

                    if ($imageRef -match '(?i)redis' -or $c -match '(?i)redis') {
                        $reply = Test-T33RedisNoAuth '127.0.0.1' $port
                        $probes.Add([pscustomobject][ordered]@{ Container = $c; Port = $port; Probe = 'redis PING without password'; Status = $reply })
                        if ($reply -like '+PONG*') { Add-Finding $c 'SEC-07' 'Redis answers without a password' "127.0.0.1:$port replied +PONG; published on $hostIp" }
                        continue
                    }
                    if ($imageRef -match '(?i)clickhouse' -and $pb.Name -like '8123/*') {
                        $r = Invoke-T33Request -Method GET -Uri "$target/?query=SELECT%201" -TimeoutSeconds 5
                        $probes.Add([pscustomobject][ordered]@{ Container = $c; Port = $port; Probe = 'ClickHouse SELECT 1 without credentials'; Status = $r.StatusCode })
                        if ($r.StatusCode -eq 200) { Add-Finding $c 'SEC-07' 'ClickHouse answers queries without credentials' "127.0.0.1:$port returned 200; published on $hostIp" }
                        continue
                    }
                    if ($isStore) {
                        $probes.Add([pscustomobject][ordered]@{ Container = $c; Port = $port; Probe = 'data store port recorded, not probed'; Status = 'n/a' })
                        continue
                    }

                    # SEC-06: control interface probes with an empty body that cannot start work.
                    $noToken = Invoke-T33Request -Method POST -Uri "$target/control/execute" -Body '{}' -TimeoutSeconds 10
                    $badToken = Invoke-T33Request -Method POST -Uri "$target/control/execute" -Headers @{ Authorization = 'Bearer t33-invalid-token' } -Body '{}' -TimeoutSeconds 10
                    foreach ($pr in @(@{ Case = 'missing token'; R = $noToken }, @{ Case = 'invalid token'; R = $badToken })) {
                        $probes.Add([pscustomobject][ordered]@{ Container = $c; Port = $port; Probe = "POST /control/execute {} ($($pr.Case))"; Status = $pr.R.StatusCode })
                    }
                    Save-T33Text (Join-Path $e "probe-$c-$port.txt") ("missing token: HTTP $($noToken.StatusCode)`n$($noToken.Content)`n`ninvalid token: HTTP $($badToken.StatusCode)`n$($badToken.Content)")
                    foreach ($pr in @(@{ Case = 'missing token'; R = $noToken }, @{ Case = 'invalid token'; R = $badToken })) {
                        # 422 = the request passed authentication and reached body validation.
                        if ($pr.R.StatusCode -in @(200,201,202,422)) {
                            Add-Finding $c 'SEC-06' 'control endpoint reachable without a valid token' "POST /control/execute with $($pr.Case) returned $($pr.R.StatusCode) on port $port (published on $hostIp)"
                        }
                    }
                }
            }
        }

        $inventory.Add([pscustomobject][ordered]@{
            Container = $c; Image = $imageRef; Digest = $digest; User = $user; Root = $isRoot
            Privileged = [bool]$hc.Privileged; RestartPolicy = $restart; Bindings = ($bindings -join ' ')
        })
    }

    # SEC-08: service keys stored in the orchestrator's Redis (count and expiry only).
    $keyStats = $null
    if ($Node -eq 'Core') {
        $redis = @($containers | Where-Object { $_ -match '^orchestrator-redis' }) | Select-Object -First 1
        if ($redis) {
            $keys = @((Invoke-T33Docker @('exec',$redis,'redis-cli','--scan','--pattern','services_key:*')).Output -split "`n" | Where-Object { $_.Trim() })
            $persistent = 0
            foreach ($k in $keys) {
                $ttl = [int]((Invoke-T33Docker @('exec',$redis,'redis-cli','TTL',$k.Trim())).Output.Trim())
                if ($ttl -eq -1) { $persistent++ }
            }
            $keyStats = [ordered]@{ stored_service_keys = $keys.Count; without_expiry = $persistent }
            Write-Host "Service keys stored in Redis: $($keys.Count); without expiry: $persistent"
            if ($persistent -gt 0) { Add-Finding $redis 'SEC-08' 'workflow service keys stored without expiry' "$persistent of $($keys.Count) services_key entries never expire" }
        }
        $orch = Invoke-T33Request -Method GET -Uri "$($s.OrchestratorUrl)/workflows/t33-probe"
        $probes.Add([pscustomobject][ordered]@{ Container = 'orchestrator-api'; Port = ''; Probe = 'GET /workflows/t33-probe (missing token)'; Status = $orch.StatusCode })
        if ($orch.StatusCode -ne 401) { Add-Finding 'orchestrator-api' 'SEC-06' 'orchestrator reachable without a token' "GET /workflows/t33-probe returned $($orch.StatusCode)" }
    }

    Save-T33Csv (Join-Path $e 'runtime-findings.csv') $findings
    Save-T33Csv (Join-Path $e 'runtime-inventory.csv') $inventory
    Save-T33Csv (Join-Path $e 'probes.csv') $probes
    $byId = @($findings | Group-Object TestId | ForEach-Object { "$($_.Name)=$($_.Count)" })
    Save-T33Json (Join-Path $e 'summary.json') ([ordered]@{ node = $Node; containers = $containers; findings_by_test = $byId; service_keys = $keyStats })

    if (@($findings | Where-Object { $_.TestId -in @('SEC-06','SEC-07','SEC-08') }).Count -gt 0) {
        return (New-T33Verdict 'DEFECT CONFIRMED' "access-control findings: $($byId -join ', '). See runtime-findings.csv and probes.csv.")
    }
    if ($findings.Count -gt 0) { return (New-T33Verdict 'FINDINGS RECORDED' "findings: $($byId -join ', '). See runtime-findings.csv.") }
    return (New-T33Verdict 'PASS' "$($containers.Count) containers: no privilege, root, provenance or access-control findings.")
}
