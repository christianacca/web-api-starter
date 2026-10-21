<#
.SYNOPSIS
  Repeatedly deploys a package to the Flex Consumption app with One Deploy and checks each deployment.

.DESCRIPTION
  Uses 'az functionapp deployment source config-zip', which calls the same Flex '/api/publish' (One Deploy) endpoint
  as Azure/functions-action. After each deployment, checks all functions are registered. The Busy scenario keeps
  enqueuing 'SimpleMessage' queue messages across the deployment so that executions are in flight while it happens.
  -Package should be a package produced by the app pipeline (eg downloaded from the deployment blob container) so that
  environment-specific appsettings.json values are present. Results are summarised in README.md.
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = '402f88b4-9dd2-49e3-9989-96c788e93372',
    [string] $TenantId = '77806292-ec65-4665-8395-93cb7c9dbd36',
    [string] $ResourceGroup = 'rg-dev-was-eastus2',
    [string] $AppName = 'func-clc-was-dev-internalapi',
    [string] $StorageAccount = 'funcsa060c4a8d35af6',
    [string] $Package = "$env:TEMP\opencode\repro\Template.Functions.zip",
    [ValidateSet('Idle', 'Busy')]
    [string] $Scenario = 'Idle',
    [int] $Iterations = 5,
    [int] $ExpectedFunctionCount = 12
)

$ErrorActionPreference = 'Stop'
$siteId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$AppName"
$queueUrl = "https://$StorageAccount.queue.core.windows.net/default-queue/messages"

function Get-ArmToken { az account get-access-token --tenant $TenantId --query accessToken -o tsv }
function Get-StorageToken { az account get-access-token --resource https://storage.azure.com/ --tenant $TenantId --query accessToken -o tsv }

function Get-FunctionCount {
    $r = Invoke-RestMethod "https://management.azure.com$siteId/functions?api-version=2024-11-01" -Headers @{ Authorization = "Bearer $(Get-ArmToken)" }
    @($r.value).Count
}

$results = @()
for ($i = 1; $i -le $Iterations; $i++) {
    $load = $null
    if ($Scenario -eq 'Busy') {
        # continuous queue load from before the deployment starts until after it completes
        $load = Start-ThreadJob -ArgumentList $queueUrl, (Get-StorageToken), 150, "$Scenario-$i" -ScriptBlock {
            param($url, $tok, $seconds, $tag)
            $headers = @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2021-12-02'; 'Content-Type' = 'application/xml' }
            $end = (Get-Date).AddSeconds($seconds); $sent = 0; $failed = 0
            while ((Get-Date) -lt $end) {
                $batch = 1..10 | ForEach-Object -ThrottleLimit 10 -Parallel {
                    $body = @{ id = [guid]::NewGuid(); data = $using:tag; metadata = @{ messageType = 'SimpleMessage' } } | ConvertTo-Json -Compress
                    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
                    try { Invoke-RestMethod -Method Post -Uri $using:url -Headers $using:headers -Body "<QueueMessage><MessageText>$b64</MessageText></QueueMessage>" | Out-Null; 1 } catch { 0 }
                }
                $sent += ($batch | Measure-Object -Sum).Sum; $failed += ($batch | Where-Object { $_ -eq 0 }).Count
                Start-Sleep -Milliseconds 500
            }
            [pscustomobject]@{ Sent = $sent; EnqueueFailed = $failed }
        }
        Start-Sleep -Seconds 30
    }

    $t0 = Get-Date
    $out = az functionapp deployment source config-zip --resource-group $ResourceGroup --name $AppName --subscription $SubscriptionId --src $Package --only-show-errors 2>&1 | Out-String
    $deployOk = $LASTEXITCODE -eq 0
    $deploySec = ((Get-Date) - $t0).TotalSeconds

    Start-Sleep -Seconds 20
    $fnCount = try { Get-FunctionCount } catch { -1 }

    $loadResult = if ($load) { $load | Wait-Job -Timeout 240 | Receive-Job; $load | Remove-Job -Force }
    $r = [pscustomobject]@{
        Scenario      = $Scenario
        Iteration     = $i
        StartUtc      = $t0.ToUniversalTime().ToString('HH:mm:ss')
        DeployOk      = $deployOk
        DeploySec     = [math]::Round($deploySec, 0)
        Functions     = $fnCount
        FunctionsOk   = $fnCount -eq $ExpectedFunctionCount
        MessagesSent  = $loadResult.Sent
        Error         = if ($deployOk) { '' } else { ($out -replace '\s+', ' ').Trim() }
    }
    $r | Format-List | Out-String | Write-Host
    $results += $r
    if ($i -lt $Iterations) { Start-Sleep -Seconds 30 }
}
$results
