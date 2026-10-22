param([string] $Run, [string] $From, [string] $To)

$sub = '402f88b4-9dd2-49e3-9989-96c788e93372'
$ws = az monitor log-analytics workspace list --subscription $sub -g rg-dev-was-eastus2 --query "[0].customerId" -o tsv
$ltok = az account get-access-token --resource https://api.loganalytics.io --tenant 77806292-ec65-4665-8395-93cb7c9dbd36 --query accessToken -o tsv
function Invoke-Kql($q) {
    (Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$ws/query" -Headers @{ Authorization = "Bearer $ltok" } -ContentType 'application/json' -Body (@{ query = $q } | ConvertTo-Json)).tables[0].rows
}

$events = Import-Csv "$env:TEMP\opencode\inflight\results\$Run-events.csv"
"=== $Run : which instance ran each piece of work, and when"
$events | ForEach-Object { [pscustomobject]@{ Job = $_.Job; Kind = $_.Kind; Event = $_.Event; Inst = $_.Instance.Substring($_.Instance.Length - 6); At = [datetime]::ParseExact($_.At, 'dd-MM-yyyy HH:mm:ss', $null).ToString('HH:mm:ss') } } |
    Sort-Object Job, Kind, At | Format-Table -AutoSize | Out-String -Width 200

$q = @"
AppTraces
| where TimeGenerated between (datetime($From) .. datetime($To)) and AppRoleName == 'Web API Starter Functions'
| where Message startswith 'Job host started' or Message startswith 'Job host stopped' or Message has 'Stopping task hub worker' or Message has 'Task hub worker stopped'
| extend inst = substring(AppRoleInstance, strlen(AppRoleInstance) - 6)
| project TimeGenerated, inst, what = substring(Message, 0, 62)
| order by TimeGenerated asc
"@
"=== host lifecycle per instance ($From to $To)"
Invoke-Kql $q | ForEach-Object { "{0:HH:mm:ss} {1} {2}" -f ([datetime]$_[0]).ToUniversalTime(), $_[1], $_[2] }
