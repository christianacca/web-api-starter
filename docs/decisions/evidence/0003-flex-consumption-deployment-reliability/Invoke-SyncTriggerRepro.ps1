<#
.SYNOPSIS
  Reproduces the intermittent 'syncfunctiontriggers' failure of the former custom Y1 deploy action.

.DESCRIPTION
  Replays the action's 'az functionapp restart' immediately followed by 'syncfunctiontriggers', against an idle,
  warm, or busy (queue load) app. Use -NoRestart as a control. Results are summarised in README.md.
  Only meaningful against a Y1 (Windows Consumption) app; the dev app is now hosted on Flex Consumption.
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = '402f88b4-9dd2-49e3-9989-96c788e93372',
    [string] $ResourceGroup = 'rg-dev-was-eastus2',
    [string] $AppName = 'func-clc-was-dev-internalapi',
    [string] $StorageAccount = 'funcsa060c4a8d35af6',
    [ValidateSet('Idle', 'Warm', 'Busy')]
    [string] $Scenario = 'Idle',
    [int] $Iterations = 3,
    [int] $RetryDelaySeconds = 5,
    [int] $MaxRetries = 30,
    [switch] $NoRestart
)

$ErrorActionPreference = 'Stop'
$siteId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$AppName"
$syncUrl = "https://management.azure.com$siteId/syncfunctiontriggers?api-version=2022-03-01"
$queueUrl = "https://$StorageAccount.queue.core.windows.net/default-queue/messages"

function Get-StorageToken { az account get-access-token --resource https://storage.azure.com/ --subscription $SubscriptionId --query accessToken -o tsv }

function Send-QueueMessages([int] $Count, [string] $Token) {
    $headers = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2021-12-02'; 'Content-Type' = 'application/xml' }
    1..$Count | ForEach-Object -ThrottleLimit 20 -Parallel {
        $body = @{ id = [guid]::NewGuid(); data = 'load'; metadata = @{ messageType = 'SimpleMessage' } } | ConvertTo-Json -Compress
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
        Invoke-RestMethod -Method Post -Uri $using:queueUrl -Headers $using:headers -Body "<QueueMessage><MessageText>$b64</MessageText></QueueMessage>" | Out-Null
    }
}

function Invoke-Sync {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = az rest --method post --url $syncUrl --only-show-errors 2>&1 | Out-String
    $ok = $LASTEXITCODE -eq 0
    [pscustomobject]@{ Ok = $ok; Ms = $sw.ElapsedMilliseconds; Message = ($ok ? 'OK' : (($out -replace '\s+', ' ').Trim())) }
}

$results = @()
for ($i = 1; $i -le $Iterations; $i++) {
    $loadJob = $null
    if ($Scenario -in 'Warm', 'Busy') {
        $token = Get-StorageToken
        Send-QueueMessages -Count 20 -Token $token          # make sure an instance is allocated and running
        Start-Sleep -Seconds 45
    }
    if ($Scenario -eq 'Busy') {
        $token = Get-StorageToken
        $loadJob = Start-ThreadJob -ScriptBlock {
            param($url, $tok, $seconds)
            $headers = @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2021-12-02'; 'Content-Type' = 'application/xml' }
            $end = (Get-Date).AddSeconds($seconds)
            while ((Get-Date) -lt $end) {
                1..20 | ForEach-Object -ThrottleLimit 20 -Parallel {
                    $body = @{ id = [guid]::NewGuid(); data = 'load'; metadata = @{ messageType = 'SimpleMessage' } } | ConvertTo-Json -Compress
                    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
                    try { Invoke-RestMethod -Method Post -Uri $using:url -Headers $using:headers -Body "<QueueMessage><MessageText>$b64</MessageText></QueueMessage>" | Out-Null } catch {}
                }
            }
        } -ArgumentList $queueUrl, $token, 150
        Start-Sleep -Seconds 20
    }

    $t0 = Get-Date
    if (-not $NoRestart) {
        az functionapp restart --name $AppName --resource-group $ResourceGroup --subscription $SubscriptionId --only-show-errors | Out-Null
    }
    $tRestart = ((Get-Date) - $t0).TotalSeconds

    $attempts = @()
    $first = Invoke-Sync
    $attempts += $first
    $n = 1
    while (-not $attempts[-1].Ok -and $n -lt $MaxRetries) {
        Start-Sleep -Seconds $RetryDelaySeconds
        $attempts += Invoke-Sync
        $n++
    }
    $recovered = ((Get-Date) - $t0).TotalSeconds

    if ($loadJob) { $loadJob | Wait-Job -Timeout 180 | Out-Null; $loadJob | Remove-Job -Force }

    $r = [pscustomobject]@{
        Scenario         = $Scenario
        Iteration        = $i
        StartUtc         = $t0.ToUniversalTime().ToString('HH:mm:ss')
        RestartSec       = [math]::Round($tRestart, 1)
        FirstSyncOk      = $first.Ok
        FirstSyncMs      = $first.Ms
        Attempts         = $attempts.Count
        SecToSuccess     = [math]::Round($recovered, 1)
        FinalOk          = $attempts[-1].Ok
        FirstError       = ($attempts | Where-Object { -not $_.Ok } | Select-Object -First 1).Message
    }
    $r | Format-List | Out-String | Write-Host
    $results += $r
    if ($i -lt $Iterations) { Start-Sleep -Seconds 30 }
}
$results
