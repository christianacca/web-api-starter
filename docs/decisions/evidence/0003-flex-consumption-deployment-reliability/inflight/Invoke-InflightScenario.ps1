[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Control', 'Deploy', 'Restart', 'StopStart')]
    [string] $Scenario,

    [string] $Package = "$env:TEMP\opencode\inflight\InflightTest.zip",
    [int] $QueueJobSeconds = 240,
    [int] $JobsPerKind = 3,
    [int] $StopGapSeconds = 180,
    [int] $SettleTimeoutMinutes = 22,
    [string] $OutDir = "$env:TEMP\opencode\inflight\results"
)

$ErrorActionPreference = 'Stop'
$sub = '402f88b4-9dd2-49e3-9989-96c788e93372'; $tenant = '77806292-ec65-4665-8395-93cb7c9dbd36'
$rg = 'rg-dev-was-eastus2'; $app = 'func-clc-was-dev-internalapi'; $acct = 'funcsa060c4a8d35af6'
$hubInstances = 'funcclcwasdevinternalapiInstances'
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Get-StorageHeaders([string] $accept = 'application/xml') {
    $t = az account get-access-token --resource https://storage.azure.com/ --tenant $tenant --query accessToken -o tsv
    @{ Authorization = "Bearer $t"; 'x-ms-version' = '2021-12-02'; Accept = $accept }
}
function Invoke-WithRetry([scriptblock] $Action) {
    for ($i = 1; $i -le 5; $i++) {
        try { return & $Action } catch { if ($i -eq 5) { throw }; Start-Sleep -Seconds (5 * $i) }
    }
}
function Send-Message($queue, $obj) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress)))
    Invoke-WithRetry { Invoke-RestMethod -Method Post -Uri "https://$acct.queue.core.windows.net/$queue/messages" -Headers (Get-StorageHeaders) -ContentType 'application/xml' -Body "<QueueMessage><MessageText>$b64</MessageText></QueueMessage>" | Out-Null }
}
function Initialize-Queue($queue) {
    Invoke-WithRetry {
        Invoke-WebRequest -Method Put -Uri "https://$acct.queue.core.windows.net/$queue" -Headers (Get-StorageHeaders) -UseBasicParsing -SkipHttpErrorCheck | Out-Null
        Invoke-WebRequest -Method Delete -Uri "https://$acct.queue.core.windows.net/$queue/messages" -Headers (Get-StorageHeaders) -UseBasicParsing | Out-Null
    }
}
function Get-QueueCount($queue) {
    Invoke-WithRetry {
        $r = Invoke-WebRequest -Method Head -Uri "https://$acct.queue.core.windows.net/${queue}?comp=metadata" -Headers (Get-StorageHeaders) -UseBasicParsing -SkipHttpErrorCheck
        if ($r.StatusCode -eq 200) { [int]$r.Headers['x-ms-approximate-messages-count'][0] } else { 0 }
    }
}
function Get-TableRows($table, $filter) {
    $u = "https://$acct.table.core.windows.net/$table()?`$filter=$([uri]::EscapeDataString($filter))"
    Invoke-WithRetry { $r = Invoke-RestMethod -Uri $u -Headers (Get-StorageHeaders 'application/json;odata=nometadata'); @($r.value) }
}
function Get-JobState($id) {
    $rows = Get-TableRows 'inflighttest' "PartitionKey eq '$id'" | Sort-Object At
    [pscustomobject]@{
        Id = $id
        Rows = $rows
        Starts = @($rows | Where-Object Event -eq 'start').Count
        Ends = @($rows | Where-Object Event -eq 'end').Count
    }
}
function Get-OrchestrationStatus($id) {
    $r = Get-TableRows $hubInstances "PartitionKey eq '$id'"
    if ($r.Count) { $r[0].RuntimeStatus } else { 'NotFound' }
}

# ---- preflight
$tag = "$($Scenario.ToLower())-$((Get-Random -Maximum 9999).ToString('0000'))"
Write-Host "[$tag] preflight"
$count = @(az functionapp function list -g $rg -n $app --subscription $sub --query '[].name' -o tsv --only-show-errors).Count
if ($count -lt 16) { throw "Expected the test package to be deployed (16 functions), found $count. Deploy it first." }
Initialize-Queue 'inflight-job'; Initialize-Queue 'inflight-start'

# ---- start the work
$queueIds = 1..$JobsPerKind | ForEach-Object { "$tag-q$_" }
$orchIds = 1..$JobsPerKind | ForEach-Object { "$tag-o$_" }
$t0 = Get-Date
foreach ($id in $queueIds) { Send-Message 'inflight-job' @{ id = $id; seconds = $QueueJobSeconds } }
# activity A runs for as long as a queue job, the timer for half of that
foreach ($id in $orchIds) { Send-Message 'inflight-start' @{ id = $id; seconds = $QueueJobSeconds - 40 } }
Write-Host "[$tag] sent $JobsPerKind queue jobs and $JobsPerKind orchestrations at $($t0.ToUniversalTime().ToString('HH:mm:ss'))Z"

# ---- wait until everything is really in flight
$deadline = (Get-Date).AddSeconds(120)
do {
    Start-Sleep -Seconds 5
    $started = @($queueIds | Where-Object { (Get-JobState $_).Starts -ge 1 }).Count + @($orchIds | Where-Object { (Get-JobState $_).Starts -ge 1 }).Count
} while ($started -lt (2 * $JobsPerKind) -and (Get-Date) -lt $deadline)
Write-Host "[$tag] $started of $(2 * $JobsPerKind) jobs running before the disruption"
$running = $started

# ---- disruption
$disruptStart = Get-Date; $disruptEnd = $null; $disruptNote = ''
switch ($Scenario) {
    'Control' { $disruptNote = 'none' }
    'Deploy' {
        # run in a separate process so that an upload that stalls can be abandoned instead of hanging the whole run
        $job = Start-Job -ArgumentList $rg, $app, $sub, $Package -ScriptBlock {
            param($rg, $app, $sub, $pkg)
            az functionapp deployment source config-zip --resource-group $rg --name $app --subscription $sub --src $pkg --only-show-errors 2>&1 | Out-String
            "EXIT=$LASTEXITCODE"
        }
        if (-not (Wait-Job $job -Timeout 480)) {
            Stop-Job $job; Remove-Job $job -Force
            $disruptNote = 'INCONCLUSIVE: deployment upload stalled and was abandoned after 8 minutes'
        } else {
            $out = Receive-Job $job; Remove-Job $job -Force
            $disruptNote = if ($out -match 'EXIT=0') { 'config-zip deployment (Flex One Deploy, Recreate)' } else { "INCONCLUSIVE: deployment failed: $($out -replace '\s+', ' ')" }
        }
    }
    'Restart' { az functionapp restart -g $rg -n $app --subscription $sub --only-show-errors | Out-Null; $disruptNote = 'az functionapp restart' }
    'StopStart' {
        az functionapp stop -g $rg -n $app --subscription $sub --only-show-errors | Out-Null
        Write-Host "[$tag] app stopped, waiting $StopGapSeconds s"
        Start-Sleep -Seconds $StopGapSeconds
        az functionapp start -g $rg -n $app --subscription $sub --only-show-errors | Out-Null
        $disruptNote = "stop, $StopGapSeconds s with no app, start"
    }
}
$disruptEnd = Get-Date
Write-Host "[$tag] disruption '$disruptNote' ran $($disruptStart.ToUniversalTime().ToString('HH:mm:ss'))Z to $($disruptEnd.ToUniversalTime().ToString('HH:mm:ss'))Z"

# ---- wait for everything to settle
$settleBy = (Get-Date).AddMinutes($SettleTimeoutMinutes)
do {
    Start-Sleep -Seconds 20
    $qDone = @($queueIds | Where-Object { (Get-JobState $_).Ends -ge 1 }).Count
    $oDone = @($orchIds | Where-Object { (Get-OrchestrationStatus $_) -in 'Completed', 'Failed', 'Terminated' }).Count
    Write-Host ("[{0}] {1:HH:mm:ss}Z queue done {2}/{4}, orchestrations done {3}/{4}" -f $tag, (Get-Date).ToUniversalTime(), $qDone, $oDone, $JobsPerKind)
} while (($qDone -lt $JobsPerKind -or $oDone -lt $JobsPerKind) -and (Get-Date) -lt $settleBy)
Start-Sleep -Seconds 30   # let any late duplicate finish writing its rows

# ---- collect
$all = foreach ($id in ($queueIds + $orchIds)) {
    $s = Get-JobState $id
    $isQueue = $id -in $queueIds
    $kinds = $s.Rows | Group-Object Kind
    foreach ($k in $kinds) {
        $ks = @($k.Group | Where-Object Event -eq 'start'); $ke = @($k.Group | Where-Object Event -eq 'end')
        [pscustomobject]@{
            Scenario = $Scenario; Run = $tag; Job = $id; Type = $(if ($isQueue) { 'queue job' } else { 'orchestration' }); Step = $k.Name
            Started = $ks.Count; Finished = $ke.Count
            Instances = @($k.Group | Select-Object -ExpandProperty Instance | Sort-Object -Unique).Count
            FirstStartUtc = ($ks | Select-Object -First 1).At; LastEndUtc = ($ke | Select-Object -Last 1).At
            MaxDequeueCount = ($k.Group | Measure-Object Attempt -Maximum).Maximum
            Status = $(if ($isQueue) { '' } else { Get-OrchestrationStatus $id })
        }
    }
}
$summary = [pscustomobject]@{
    Scenario = $Scenario; Run = $tag; Disruption = $disruptNote
    DisruptionStartUtc = $disruptStart.ToUniversalTime().ToString('o'); DisruptionEndUtc = $disruptEnd.ToUniversalTime().ToString('o')
    JobsRunningBeforeDisruption = $running
    JobQueueLeft = Get-QueueCount 'inflight-job'; JobPoisonLeft = Get-QueueCount 'inflight-job-poison'
}
$all | Export-Csv "$OutDir\$tag.csv" -NoTypeInformation
$rowsDump = foreach ($id in ($queueIds + $orchIds)) { (Get-JobState $id).Rows | ForEach-Object { [pscustomobject]@{ Job = $id; Kind = $_.Kind; Event = $_.Event; Attempt = $_.Attempt; Instance = $_.Instance; At = $_.At } } }
$rowsDump | Export-Csv "$OutDir\$tag-events.csv" -NoTypeInformation
$summary | ConvertTo-Json | Set-Content "$OutDir\$tag-summary.json"
$all | Format-Table Job, Step, Started, Finished, MaxDequeueCount, Status -AutoSize | Out-String -Width 200 | Write-Host
$summary | Format-List | Out-String | Write-Host

