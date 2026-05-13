#!/bin/bash
# Poll the GitHub Actions run for pending environment deployment gates and auto-approve
# those whose environment name is in ENVIRONMENT_ALLOW_LIST.
#
# Required environment variables (set by the calling workflow job):
#   REPO                   - e.g. "MRI-Software/web-api-starter"
#   RUN_ID                 - GitHub Actions run ID to watch
#   ENVIRONMENT_ALLOW_LIST - environment name(s) to approve; either a plain string ("qa")
#                            or a JSON array string ('["dev","qa"]')
#   GH_TOKEN               - PAT of a human who is a required reviewer on those environments
#                            (the gh CLI picks this up automatically)
#   JOB_NAME               - the name of this job (github.job), used to exclude it from the
#                            all-others-done check so the loop can exit cleanly
set -euo pipefail

MAX_WAIT=900   # 15 minutes — give up if the run hasn't finished by then
POLL_INTERVAL=15
elapsed=0

echo "Starting auto-approval polling for run $RUN_ID in $REPO"
echo "Environment allow list: $ENVIRONMENT_ALLOW_LIST"

# Normalise the allow list to a JSON array (handles both a JSON array string and a plain string)
if echo "$ENVIRONMENT_ALLOW_LIST" | jq -e . >/dev/null 2>&1; then
  allow_list=$(echo "$ENVIRONMENT_ALLOW_LIST" | jq -c 'if type == "array" then . else [.] end')
else
  allow_list=$(jq -cn --arg env "$ENVIRONMENT_ALLOW_LIST" '[$env]')
fi

while [[ $elapsed -lt $MAX_WAIT ]]; do
  # The run is always "in_progress" while this job itself is running, so we can't use run
  # status to detect completion. Instead check whether every *other* job has reached a
  # terminal state (completed). When they have and nothing is pending, we're done.
  all_others_done=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" \
    --jq --arg job "$JOB_NAME" '(.jobs | length > 0) and ([.jobs[] | select(.name != $job) | .status] | all(. == "completed"))' \
    2>/dev/null || echo "false")

  # Fetch the list of deployment gates currently waiting for a reviewer to approve.
  pending=$(gh api "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" 2>/dev/null || echo "[]")

  # Early exit: all jobs finished and no gates are waiting — nothing left to do.
  if [[ "$all_others_done" = "true" && $(echo "$pending" | jq 'length') -eq 0 ]]; then
    echo "All other jobs completed and no pending deployments. Exiting."
    exit 0
  fi

  # From the pending list, extract the numeric environment IDs whose names are in the allow list.
  # Only allowed environments are approved — others are left for human reviewers.
  env_ids=$(echo "$pending" | jq -r --argjson allow "$allow_list" \
    '[.[] | select(.environment.name as $n | $allow | contains([$n])) | .environment.id] | join(",")' \
    2>/dev/null || echo "")

  if [[ -n "$env_ids" ]]; then
    echo "Approving pending deployments (ids: $env_ids)"
    # POST to the pending_deployments endpoint to approve the gates in bulk.
    # Uses GH_TOKEN (the PAT of a required reviewer) so GitHub treats it as a valid approval.
    printf '{"environment_ids":[%s],"state":"approved","comment":"Auto-approved by bot workflow"}' "$env_ids" \
      | gh api "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
          --method POST --input - --silent \
      || echo "Warning: could not approve (may already be approved)"
  fi

  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
done

echo "Polling timed out after ${MAX_WAIT}s."
