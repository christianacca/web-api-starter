<#
.SYNOPSIS
  Bursts load at the dev Web API Starter Function App to measure scale-out behavior,
  for comparing before/after the managed-identity + content-share removal change.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Label,

    [ValidateSet('Http', 'Queue', 'Both')]
    [string]$Mode = 'Both',

    [int]$HttpConcurrency = 50,
    [int]$HttpDurationSeconds = 90,

    [int]$QueueMessageCount = 500,
    [int]$QueueConcurrency = 50,

    [string]$EnvironmentName = 'dev'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$infraDir = Join-Path $repoRoot 'tools/infrastructure'
$outputRoot = Join-Path $PSScriptRoot 'output/scale-tests'
$runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $outputRoot "$runStamp-$Label"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

Write-Host "==> Resolving '$EnvironmentName' conventions..." -ForegroundColor Cyan
Push-Location $infraDir
try
{
    $conv = . ./get-product-conventions.ps1 -EnvironmentName $EnvironmentName -AsHashtable
} finally
{
    Pop-Location
}

# get-product-conventions.ps1 turns on Set-StrictMode -Version Latest in its own
# begin{} block. Because it's dot-sourced, that setting leaks into this scope and
# is never reset by the callee. Turn it back off so empty/single-item pipeline
# results (e.g. Sort-Object on 0 or 1 items) behave normally for the rest of this script.
Set-StrictMode -Off

$apiHostName = $conv.SubProducts.Api.HostName
$funcResourceName = $conv.SubProducts.InternalApi.ResourceName
$funcStorageAccount = $conv.SubProducts.InternalApi.StorageAccountName
# Set via appInsightsCloudRoleName in main.bicep. If a KQL query below returns no rows,
# confirm this literal still matches what's deployed.
$cloudRoleName = 'Web API Starter Functions'
$appInsightsWorkspace = $conv.SubProducts.AppInsights.WorkspaceName

$baseUrl = "https://$apiHostName"
$queueName = 'default-queue'

Write-Host "    Api host        : $apiHostName"
Write-Host "    Function App    : $funcResourceName"
Write-Host "    Storage account : $funcStorageAccount"
Write-Host "    Output dir      : $runDir"

# ---------------------------------------------------------------------------
# Auth: replicate the Postman collection's Okta client-credentials flow
# ---------------------------------------------------------------------------
function Get-OktaAccessToken
{
    $envFile = Join-Path $repoRoot 'tests/postman/api-dev.postman_environment.json'
    $envJson = Get-Content $envFile -Raw | ConvertFrom-Json
    $values = @{}
    foreach ($v in $envJson.values)
    { $values[$v.key] = $v.value
    }

    $clientId = $values['tokenClientId']
    $tokenUrl = $values['tokenIssuerUrl']
    $scope = $values['tokenScope']

    Write-Host "==> Fetching Okta client secret from Key Vault..." -ForegroundColor Cyan
    $secret = az keyvault secret show --vault-name kv-was-dev --name 'NotForApp--OktaClient--WAS-Integration-Default-dev' --query value -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $secret)
    {
        throw 'Failed to read Okta client secret from Key Vault kv-was-dev.'
    }

    $body = @{
        client_id     = $clientId
        client_secret = $secret
        scope         = $scope
        grant_type    = 'client_credentials'
    }
    $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $response.access_token
}

function Get-StorageAadToken
{
    $token = az account get-access-token --resource 'https://storage.azure.com' --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $token)
    {
        throw 'Failed to acquire an AAD token for Azure Storage.'
    }
    return $token
}

# ---------------------------------------------------------------------------
# Warm-up: the API container app has MinReplicas = 0, so make sure it's
# already scaled up before timing starts - otherwise its own cold start
# pollutes the Functions scale-out measurement.
# ---------------------------------------------------------------------------
function Invoke-Warmup
{
    param([string]$Token)
    Write-Host "==> Warming up API + Function App (3 sequential requests)..." -ForegroundColor Cyan
    for ($i = 0; $i -lt 3; $i++)
    {
        try
        {
            Invoke-RestMethod -Uri "$baseUrl/api/Echo" -Headers @{ Authorization = "Bearer $Token" } | Out-Null
        } catch
        {
            Write-Warning "Warmup request $i failed: $_"
        }
        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------------------------
# HTTP burst against /api/Echo (proxied through the API to the Function App).
# CAVEAT: the API container app is capped at MaxReplicas = 2. At high
# concurrency the API itself - not the Function App - may become the
# bottleneck, which would understate the Function App's true scale-out
# headroom. Treat this as a secondary signal; the queue burst below is the
# cleaner test.
# ---------------------------------------------------------------------------
function Invoke-HttpBurst
{
    param([string]$Token)

    Write-Host "==> HTTP burst: $HttpConcurrency workers for $HttpDurationSeconds s against $baseUrl/api/Echo" -ForegroundColor Cyan
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $stopAt = (Get-Date).AddSeconds($HttpDurationSeconds)
    $startedUtc = (Get-Date).ToUniversalTime()

    1..$HttpConcurrency | ForEach-Object -ThrottleLimit ($HttpConcurrency + 5) -Parallel {
        $results = $using:results
        $stopAt = $using:stopAt
        $url = "$using:baseUrl/api/Echo"
        $headers = @{ Authorization = "Bearer $using:Token" }

        while ((Get-Date) -lt $stopAt)
        {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try
            {
                $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 30
                $sw.Stop()
                $results.Add([pscustomobject]@{
                        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
                        StatusCode   = $resp.StatusCode
                        ElapsedMs    = $sw.ElapsedMilliseconds
                        Error        = $null
                    })
            } catch
            {
                $sw.Stop()
                $statusCode = $null
                if ($_.Exception.Response)
                { $statusCode = [int]$_.Exception.Response.StatusCode
                }
                $results.Add([pscustomobject]@{
                        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
                        StatusCode   = $statusCode
                        ElapsedMs    = $sw.ElapsedMilliseconds
                        Error        = $_.Exception.Message
                    })
            }
        }
    }

    $endedUtc = (Get-Date).ToUniversalTime()
    $resultsArray = @($results.ToArray() | Sort-Object TimestampUtc)
    $resultsArray | Export-Csv (Join-Path $runDir 'http-burst-results.csv') -NoTypeInformation

    $total = $resultsArray.Count
    $failures = ($resultsArray | Where-Object { $_.StatusCode -ne 200 }).Count
    Write-Host "    Requests: $total, Failures/non-200: $failures"

    return [pscustomobject]@{
        StartedUtc = $startedUtc
        EndedUtc   = $endedUtc
        Total      = $total
        Failures   = $failures
    }
}

# ---------------------------------------------------------------------------
# Queue burst: enqueue messages directly via the Storage Queue REST API using
# an AAD token. This bypasses the API/Functions HTTP path entirely, so it
# isn't bottlenecked by the API container app's replica cap - the cleanest
# signal for the Functions scale controller's dynamic scale-out.
# ---------------------------------------------------------------------------
function Invoke-QueueBurst
{
    param([string]$StorageToken)

    Write-Host "==> Queue burst: enqueuing $QueueMessageCount messages ($QueueConcurrency concurrent) onto '$queueName'" -ForegroundColor Cyan
    $queueUrl = "https://$funcStorageAccount.queue.core.windows.net/$queueName/messages"
    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    $startedUtc = (Get-Date).ToUniversalTime()

    1..$QueueMessageCount | ForEach-Object -ThrottleLimit $QueueConcurrency -Parallel {
        $results = $using:results
        $queueUrl = $using:queueUrl
        $token = $using:StorageToken

        $id = [guid]::NewGuid()
        # NOTE: the app's JsonSerializerOptions use PropertyNamingPolicy = CamelCase
        # (see JsonSerializationOptionsExtensions.ConfigureStandardOptions). Property
        # names here MUST be camelCase or MessageBody deserializes with empty
        # defaults and fails [Required] validation on every message.
        $messageBody = @{
            id       = $id
            data     = 'SimpleMessage'
            metadata = @{ messageType = 'SimpleMessage' }
        } | ConvertTo-Json -Compress

        # Storage Queue REST API wants XML with a base64-encoded message body
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($messageBody))
        $xmlBody = "<QueueMessage><MessageText>$encoded</MessageText></QueueMessage>"

        $headers = @{
            Authorization  = "Bearer $token"
            'x-ms-version' = '2021-08-06'
            'x-ms-date'    = (Get-Date).ToUniversalTime().ToString('R')
        }

        try
        {
            Invoke-RestMethod -Method Post -Uri $queueUrl -Headers $headers -Body $xmlBody -ContentType 'application/xml' | Out-Null
            $results.Add([pscustomobject]@{ TimestampUtc = (Get-Date).ToUniversalTime().ToString('o'); MessageId = $id; Error = $null })
        } catch
        {
            $results.Add([pscustomobject]@{ TimestampUtc = (Get-Date).ToUniversalTime().ToString('o'); MessageId = $id; Error = $_.Exception.Message })
        }
    }

    $endedUtc = (Get-Date).ToUniversalTime()
    $resultsArray = @($results.ToArray() | Sort-Object TimestampUtc)
    $resultsArray | Export-Csv (Join-Path $runDir 'queue-burst-results.csv') -NoTypeInformation

    $total = $resultsArray.Count
    $failures = ($resultsArray | Where-Object { $_.Error }).Count
    Write-Host "    Enqueued: $total, Failures: $failures"

    return [pscustomobject]@{
        StartedUtc = $startedUtc
        EndedUtc   = $endedUtc
        Total      = $total
        Failures   = $failures
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$oktaToken = Get-OktaAccessToken
Invoke-Warmup -Token $oktaToken

$summary = [ordered]@{
    Label           = $Label
    EnvironmentName = $EnvironmentName
    Mode            = $Mode
    ApiHostName     = $apiHostName
    FunctionApp     = $funcResourceName
    CloudRoleName   = $cloudRoleName
}

if ($Mode -in @('Http', 'Both'))
{
    $httpSummary = Invoke-HttpBurst -Token $oktaToken
    $summary.Http = $httpSummary
}

if ($Mode -in @('Queue', 'Both'))
{
    $storageToken = Get-StorageAadToken
    $queueSummary = Invoke-QueueBurst -StorageToken $storageToken
    $summary.Queue = $queueSummary
}

$summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $runDir 'summary.json')

# ---------------------------------------------------------------------------
# Emit ready-to-paste KQL for Log Analytics (workspace: $appInsightsWorkspace)
# ---------------------------------------------------------------------------
$kqlLines = [System.Collections.Generic.List[string]]::new()
$kqlLines.Add("// Paste into Log Analytics workspace '$appInsightsWorkspace' (or the linked App Insights resource).")
$kqlLines.Add("// Run label: $Label")
$kqlLines.Add('')

# NOTE: this workspace hosts *workspace-based* Application Insights, whose schema
# uses AppRequests/TimeGenerated/AppRoleName/AppRoleInstance/DurationMs/Success
# rather than the classic requests/timestamp/cloud_RoleName/cloud_RoleInstance/
# duration/success. If your workspace uses classic App Insights, swap the table
# and column names back accordingly.
if ($summary.Contains('Http'))
{
    $h = $summary.Http
    $startIso = $h.StartedUtc.ToString('o')
    $endIso = $h.EndedUtc.ToString('o')
    $kqlLines.Add("// --- HTTP burst window: $startIso .. $endIso ---")
    $kqlLines.Add('AppRequests')
    $kqlLines.Add("| where TimeGenerated between (datetime($startIso) .. datetime($endIso))")
    $kqlLines.Add("| where AppRoleName == `"$cloudRoleName`"")
    $kqlLines.Add('| summarize instanceCount = dcount(AppRoleInstance), reqCount = count(), p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95), p99 = percentile(DurationMs, 99), failures = countif(Success == false) by bin(TimeGenerated, 10s)')
    $kqlLines.Add('| order by TimeGenerated asc')
    $kqlLines.Add('')
    $kqlLines.Add('AppRequests')
    $kqlLines.Add("| where TimeGenerated between (datetime($startIso) .. datetime($endIso))")
    $kqlLines.Add("| where AppRoleName == `"$cloudRoleName`"")
    $kqlLines.Add('| summarize firstSeen = min(TimeGenerated) by AppRoleInstance')
    $kqlLines.Add('| order by firstSeen asc')
    $kqlLines.Add('')
}

if ($summary.Contains('Queue'))
{
    $q = $summary.Queue
    $startIso = $q.StartedUtc.ToString('o')
    $kqlLines.Add("// --- Queue burst window: enqueue started $startIso (drain may continue after enqueue finishes) ---")
    $kqlLines.Add('AppRequests')
    $kqlLines.Add("| where TimeGenerated > datetime($startIso)")
    $kqlLines.Add("| where AppRoleName == `"$cloudRoleName`"")
    $kqlLines.Add('| where Name has "ExampleQueue" and Name !has "ExceptionHandler"')
    $kqlLines.Add('| summarize instanceCount = dcount(AppRoleInstance), invocationCount = count(), succeeded = countif(Success == true), failed = countif(Success == false), lastSeen = max(TimeGenerated) by bin(TimeGenerated, 10s)')
    $kqlLines.Add('| order by TimeGenerated asc')
    $kqlLines.Add('')
    $kqlLines.Add('// drain time = (max(lastSeen) across all rows above) - queue burst StartedUtc shown above')
}

$kqlLines -join "`n" | Set-Content (Join-Path $runDir 'kql-queries.kql')

Write-Host ""
Write-Host "==> Done. Artifacts written to: $runDir" -ForegroundColor Green
Write-Host "    - summary.json"
if ($Mode -in @('Http', 'Both'))
{ Write-Host "    - http-burst-results.csv"
}
if ($Mode -in @('Queue', 'Both'))
{ Write-Host "    - queue-burst-results.csv"
}
Write-Host "    - kql-queries.kql  (paste into Log Analytics against workspace '$appInsightsWorkspace')"
