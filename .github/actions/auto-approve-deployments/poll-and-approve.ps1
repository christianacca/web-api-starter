#!/usr/bin/env pwsh
# Polls a GitHub Actions run and auto-approves pending deployment gates whose environment
# name is in EnvironmentAllowList. Requires GH_TOKEN set to a PAT of a required reviewer.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Repo,

    [Parameter(Mandatory)]
    [string] $RunId,

    [Parameter(Mandatory)]
    [string[]] $EnvironmentAllowList,

    [Parameter(Mandatory)]
    [string] $SelfJobName,

    [int] $MaxWaitSeconds = 900,

    [int] $PollIntervalSeconds = 15
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$elapsed = 0

Write-Host "Starting auto-approval polling for run $RunId in $Repo"
Write-Host "Environment allow list: $EnvironmentAllowList"

while ($elapsed -lt $MaxWaitSeconds) {
    $allOthersDone = $false
    try {
        $jobsJson = gh api "repos/$Repo/actions/runs/$RunId/jobs"
        if ($jobsJson) {
            $jobs = ($jobsJson | ConvertFrom-Json).jobs
            $otherJobs = @($jobs | Where-Object { $_.name -ne $SelfJobName })
            $incompleteOtherJobs = @($otherJobs | Where-Object { $_.status -ne 'completed' })
            $allOthersDone = ($otherJobs.Count -gt 0) -and ($incompleteOtherJobs.Count -eq 0)
        }
    } catch {
        Write-Error "Failed to check jobs: $($_.Exception.Message)"
        $allOthersDone = $false
    }

    $pending = @()
    try {
        $pendingJson = gh api "repos/$Repo/actions/runs/$RunId/pending_deployments"
        if ($pendingJson) {
            $pending = @($pendingJson | ConvertFrom-Json)
        }
    } catch {
        Write-Error "Failed to check pending deployments: $($_.Exception.Message)"
        $pending = @()
    }

    if ($allOthersDone -and $pending.Count -eq 0) {
        Write-Host "All other jobs completed and no pending deployments. Exiting."
        exit 0
    }

    # Approve any pending deployments whose environment name matches the allow list.
    $allowedEnvIds = @($pending | Where-Object { $EnvironmentAllowList -contains $_.environment.name } | ForEach-Object { $_.environment.id })

    if ($allowedEnvIds.Count -gt 0) {
        Write-Host "Approving pending deployments (ids: $($allowedEnvIds -join ','))"
        $bodyObj = @{ environment_ids = $allowedEnvIds; state = "approved"; comment = "Auto-approved by bot workflow" }
        $body = $bodyObj | ConvertTo-Json -Compress
        try {
            $body | gh api "repos/$Repo/actions/runs/$RunId/pending_deployments" `
                --method POST --input - | Out-Null
        } catch {
            Write-Error "Could not approve pending deployments: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
    $elapsed += $PollIntervalSeconds
}

Write-Host "Polling timed out after ${MaxWaitSeconds}s."
