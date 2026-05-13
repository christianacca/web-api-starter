#!/usr/bin/env pwsh
# Poll the GitHub Actions run for pending environment deployment gates and auto-approve
# those whose environment name is in ENVIRONMENT_ALLOW_LIST.
#
# Required environment variables (set by the calling workflow job):
#   REPO                   - e.g. "MRI-Software/data-services-gateway"
#   RUN_ID                 - GitHub Actions run ID to watch
#   ENVIRONMENT_ALLOW_LIST - environment name(s) to approve; either a plain string ("qa")
#                            or a JSON array string ('["dev","qa"]')
#   GH_TOKEN               - PAT of a human who is a required reviewer on those environments
#                            (the gh CLI picks this up automatically)
$ErrorActionPreference = 'Stop'

$maxWait = 900   # 15 minutes — give up if the run hasn't finished by then
$pollInterval = 15
$elapsed = 0

Write-Host "Starting auto-approval polling for run $env:RUN_ID in $env:REPO"
Write-Host "Environment allow list: $env:ENVIRONMENT_ALLOW_LIST"

# Normalise the allow list to a JSON array (handles both a JSON array string and a plain string)
try {
    $parsed = $env:ENVIRONMENT_ALLOW_LIST | ConvertFrom-Json -ErrorAction Stop
    $allowList = @($parsed)
} catch {
    $allowList = @($env:ENVIRONMENT_ALLOW_LIST)
}

while ($elapsed -lt $maxWait) {
    # The run is always "in_progress" while this job itself is running, so we can't use run
    # status to detect completion. Instead check whether every *other* job has reached a
    # terminal state (completed). When they have and nothing is pending, we're done.
    $allOthersDone = $false
    try {
        $jobsJson = gh api "repos/$env:REPO/actions/runs/$env:RUN_ID/jobs" 2>$null
        if ($LASTEXITCODE -eq 0 -and $jobsJson) {
            $jobs = ($jobsJson | ConvertFrom-Json).jobs
            $otherJobs = @($jobs | Where-Object { $_.name -ne 'auto_approve' })
            $allOthersDone = ($jobs.Count -gt 0) -and
                             ($otherJobs | Where-Object { $_.status -ne 'completed' } | Measure-Object).Count -eq 0
        }
    } catch {
        $allOthersDone = $false
    }

    # Fetch the list of deployment gates currently waiting for a reviewer to approve.
    $pending = @()
    try {
        $pendingJson = gh api "repos/$env:REPO/actions/runs/$env:RUN_ID/pending_deployments" 2>$null
        if ($LASTEXITCODE -eq 0 -and $pendingJson) {
            $pending = @($pendingJson | ConvertFrom-Json)
        }
    } catch {
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
        $envIdsStr = $envIds -join ','
        Write-Host "Approving pending deployments (ids: $envIdsStr)"
        # POST to the pending_deployments endpoint to approve the gates in bulk.
        # Uses GH_TOKEN (the PAT of a required reviewer) so GitHub treats it as a valid approval.
        $body = "{`"environment_ids`":[$envIdsStr],`"state`":`"approved`",`"comment`":`"Auto-approved by bot workflow`"}"
        try {
            $body | gh api "repos/$env:REPO/actions/runs/$env:RUN_ID/pending_deployments" `
                --method POST --input - --silent
        } catch {
            Write-Host "Warning: could not approve (may already be approved)"
        }
    }

    Start-Sleep -Seconds $pollInterval
    $elapsed += $pollInterval
}

Write-Host "Polling timed out after ${maxWait}s."
