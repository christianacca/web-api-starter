#!/usr/bin/env pwsh
# Poll the GitHub Actions run for pending environment deployment gates and auto-approve
# those whose environment name is in EnvironmentAllowList.
#
# Requires GH_TOKEN env var to be set to a PAT of a human who is a required reviewer
# on the allowed environments (the gh CLI picks this up automatically).
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Repo,

    [Parameter(Mandatory)]
    [string] $RunId,

    [Parameter(Mandatory)]
    [string] $EnvironmentAllowList,

    [int] $MaxWait = 900,

    [int] $PollInterval = 15
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:GH_TOKEN = "ABC"  # TODO: remove — hard-coded for failure scenario testing only

$elapsed = 0

Write-Host "Starting auto-approval polling for run $RunId in $Repo"
Write-Host "Environment allow list: $EnvironmentAllowList"

# Normalise the allow list to a JSON array (handles both a JSON array string and a plain string)
try {
    $parsed = $EnvironmentAllowList | ConvertFrom-Json -ErrorAction Stop
    $allowList = @($parsed)
} catch {
    $allowList = @($EnvironmentAllowList)
}

while ($elapsed -lt $MaxWait) {
    # The run is always "in_progress" while this job itself is running, so we can't use run
    # status to detect completion. Instead check whether every *other* job has reached a
    # terminal state (completed). When they have and nothing is pending, we're done.
    $allOthersDone = $false
    try {
        $jobsJson = gh api "repos/$Repo/actions/runs/$RunId/jobs"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "gh api jobs call failed (exit $LASTEXITCODE): $jobsJson"
        } elseif ($jobsJson) {
            $jobs = ($jobsJson | ConvertFrom-Json).jobs
            $otherJobs = @($jobs | Where-Object { $_.name -ne 'auto_approve' })
            $allOthersDone = ($jobs.Count -gt 0) -and
                             ($otherJobs | Where-Object { $_.status -ne 'completed' } | Measure-Object).Count -eq 0
        }
    } catch {
        Write-Warning "Failed to check jobs: $($_.Exception.Message)"
        $allOthersDone = $false
    }

    # Fetch the list of deployment gates currently waiting for a reviewer to approve.
    $pending = @()
    try {
        $pendingJson = gh api "repos/$Repo/actions/runs/$RunId/pending_deployments"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "gh api pending_deployments call failed (exit $LASTEXITCODE): $pendingJson"
        } elseif ($pendingJson) {
            $pending = @($pendingJson | ConvertFrom-Json)
        }
    } catch {
        Write-Warning "Failed to check pending deployments: $($_.Exception.Message)"
        $pending = @()
    }

    # Early exit: all jobs finished and no gates are waiting — nothing left to do.
    if ($allOthersDone -and $pending.Count -eq 0) {
        Write-Host "All other jobs completed and no pending deployments. Exiting."
        exit 0
    }

    # From the pending list, extract the numeric environment IDs whose names are in the allow list.
    # Only allowed environments are approved — others are left for human reviewers.
    $envIds = @($pending | Where-Object { $allowList -contains $_.environment.name } | ForEach-Object { $_.environment.id })

    if ($envIds.Count -gt 0) {
        Write-Host "Approving pending deployments (ids: $($envIds -join ','))"
        # POST to the pending_deployments endpoint to approve the gates in bulk.
        # Uses GH_TOKEN (the PAT of a required reviewer) so GitHub treats it as a valid approval.
        $bodyObj = @{ environment_ids = $envIds; state = "approved"; comment = "Auto-approved by bot workflow" }
        $body = $bodyObj | ConvertTo-Json -Compress
        try {
            $body | gh api "repos/$Repo/actions/runs/$RunId/pending_deployments" `
                --method POST --input - --silent
        } catch {
            Write-Warning "Could not approve pending deployments: $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds $PollInterval
    $elapsed += $PollInterval
}

Write-Host "Polling timed out after ${MaxWait}s."
