# Workflow Orchestration Setup

## Overview

This document provides setup instructions for integrating a GitHub App with the Azure-hosted API and Functions applications to enable automated GitHub workflow orchestration with retry logic.

For instructions on creating the GitHub App itself, see the [GitHub App Creation Guide](github-app-creation.md).

---

## Architecture

The following sequence diagram illustrates the complete workflow orchestration flow:

```mermaid
sequenceDiagram
    participant User as User/System
    participant API as API App
    participant Middleware as Webhook Middleware
    participant Functions as Functions App
    participant Orchestrator as Durable Orchestrator
    participant GitHub as GitHub Actions

    User->>API: POST /api/workflow/start 
    API->>Functions: Forward request (reverse proxy)
    Functions->>Orchestrator: Start new orchestration
    Orchestrator->>Orchestrator: Generate instance ID
    Functions-->>API: Return instance ID
    API-->>User: 200 OK {Id: "instance-id"}
    
    Orchestrator->>GitHub: Dispatch workflow (workflowName: InternalApi-{instanceId})
    Note over GitHub: Workflow starts with name: InternalApi-{instanceId}
    
    GitHub->>API: Webhook: workflow_run (action: in_progress)
    API->>Middleware: Validate HMAC signature
    Middleware->>Middleware: Extract workflow name
    Middleware->>Middleware: Add X-Workflow-Identifier header
    API->>Functions: Route to webhook (proxy HTTP client)
    Functions->>Orchestrator: Raise external event (WorkflowInProgress, runId)
    Orchestrator->>Orchestrator: Wait for completion event
    
    GitHub->>API: Webhook: workflow_run (action: completed)
    API->>Middleware: Validate HMAC signature
    Middleware->>Middleware: Add X-Workflow-Identifier header
    API->>Functions: Route to webhook (proxy HTTP client)
    Functions->>Orchestrator: Raise external event (WorkflowCompleted, success)
    
    alt Workflow Failed
        Orchestrator->>GitHub: Rerun failed jobs or entire workflow (attempt 2)
        GitHub->>API: Webhook: workflow_run (completed)
        API->>Functions: Route to webhook
        Functions->>Orchestrator: Raise external event
        Note over Orchestrator: Retry up to MaxAttempts times
    else Workflow Succeeded
        Orchestrator->>Orchestrator: Complete orchestration
    end
```

**Key Flow Points:**

1. **Initiation**: User triggers orchestration via API endpoint
2. **Dispatch**: Orchestrator dispatches GitHub workflow with unique workflow name derived from the instanceId and functionApp prefix
3. **Tracking**: GitHub sends webhook events as workflow progresses
4. **Validation**: API middleware validates webhook signatures for security using Octokit.Webhooks library
5. **Routing**: Workflow name header routes webhooks to Functions orchestrator via proxy HTTP client
6. **Retry Logic**: On failure, orchestrator automatically reruns failed jobs (or entire workflow or jobs as requested) up to MaxAttempts

---

## Prerequisites

Before setting up workflow orchestration, you must create and configure a GitHub App. Follow the step-by-step instructions in:

**[GitHub App Creation Guide](github-app-creation.md)**

You will need the following information from your GitHub App:
- App ID
- Installation ID
- Private Key (PEM file)
- Webhook Secret

---

## GitHub Workflow Requirements

Your GitHub Actions workflow file must meet specific requirements for the orchestration to work correctly.

### Required Trigger

The workflow **must** accept `workflow_dispatch` trigger with a `workflowName` input:

```yaml
on:
  workflow_dispatch:
    inputs:
      workflowName:
        description: 'Workflow name for tracking'
        required: true
        type: string
```

### Required Workflow Name Format

The workflow run name **must** use the workflowName input. This is how the system matches webhook events to orchestration instances:

```yaml
name: ${{ inputs.workflowName }}
```

### Example Minimal Workflow Structure

Here's a complete minimal example:

```yaml
name: ${{ inputs.workflowName }}

on:
  workflow_dispatch:
    inputs:
      workflowName:
        description: 'Workflow name for tracking'
        required: true
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Display workflow name
        run: echo "Processing with workflow name: ${{ inputs.workflowName }}"
      
      - name: Your deployment steps
        run: |
          # Add your actual deployment logic here
          echo "Deploying application..."
```

### Important Notes

- The workflow name format will be: `{FunctionAppIdentifier}-{orchestration-instance-id}`
- The workflow name **must exactly match** the workflowName input for tracking to work
- You can add any additional workflow logic, jobs, and steps as needed
- The workflow can be triggered manually or via other triggers, but `workflow_dispatch` is required for orchestration

---

## Azure Configuration

### Configuration Structure

Both the API and Functions applications require the same `Github` configuration section in their `appsettings.json` files.

#### API - appsettings.json

```json
{
  "Github": {
    "Owner": null,
    "Repo": null,
    "Branch": null,
    "AppId": null,
    "InstallationId": 0,
    "PrivateKeyPem": null,
    "WebhookSecret": null,
    "MaxAttempts": 5,
    "WorkflowTimeoutHours": 12
  }
}
```

#### Functions - appsettings.json

Same structure as API configuration above.

### Reverse Proxy Routing

The API application uses a proxy HTTP client pattern to direct webhook requests to the Functions app:

1. **Webhook Flow**: GitHub sends webhook events to `POST /api/workflow/webhook`
2. **Middleware Validation**: The webhook processor uses the Octokit.Webhooks library to deserialize and validate webhook payloads
3. **Header Injection**: After successful validation, the processor adds the workflow identifier header (defined as `GithubHeaderNames.WorkflowIdentifier` constant with value `"X-Workflow-Identifier"`)
4. **Routing**: The `FunctionAppHttpClient` forwards requests to the Functions webhook endpoint at `/api/github/webhooks`
5. **Filtering**: Only webhooks for workflows starting with the `InternalApi` prefix are forwarded to the Functions app
6. **Security**: This ensures only validated, internal webhook calls reach the Functions orchestration logic

This approach uses Octokit.Webhooks for type-safe webhook processing and direct HTTP client forwarding instead of YARP header-based routing.

---

## Configuration Parameters Reference

Complete reference of all `Github` configuration parameters:

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `Owner` | string | Yes | GitHub repository owner (username or organization name) | `myorg` or `john-doe` |
| `Repo` | string | Yes | Repository name | `my-application` |
| `Branch` | string | Yes | Branch name to trigger workflow on | `main` |
| `AppId` | string | Yes | GitHub App ID (found in app settings) | `123456` |
| `InstallationId` | long | Yes | Installation ID (obtained after installing app to repository) | `98765432` |
| `PrivateKeyPem` | string | Yes | GitHub App private key in PEM format (includes headers/footers) | `-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----` |
| `WebhookSecret` | string | Yes | Webhook secret for HMAC-SHA256 signature validation | `your-secret-here` |
| `MaxAttempts` | int | No | Maximum number of retry attempts for failed workflows (default: 5) | `5` |
| `WorkflowTimeoutHours` | int | No | Hours to wait for workflow completion before timeout (default: 12) | `12` |

### Important Notes

- **PrivateKeyPem Format**: Must include the full PEM format including `-----BEGIN RSA PRIVATE KEY-----` header and `-----END RSA PRIVATE KEY-----` footer, with newlines preserved (`\n`)
- **MaxAttempts**: Total attempts = initial run + MaxAttempts retries (e.g., MaxAttempts=5 means up to 6 total runs)
- **WorkflowTimeoutHours**: Applies to each workflow run attempt, not total orchestration time

---


```bash
# Using curl (basic - reruns only failed jobs)
curl -X POST https://<your-api-domain>/api/workflow/start \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"WorkflowFile": "deploy.yaml"}'

# Using curl (rerun entire workflow on failure)
curl -X POST https://<your-api-domain>/api/workflow/start \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"WorkflowFile": "deploy.yaml", "RerunEntireWorkflow": true}'

# Using PowerShell (basic)
Invoke-RestMethod -Uri "https://<your-api-domain>/api/workflow/start" `
  -Method POST `
  -Headers @{ "Authorization" = "Bearer <your-token>" } `
  -ContentType "application/json" `
  -Body (@{ "WorkflowFile" = "deploy.yaml" } | ConvertTo-Json)

# Using PowerShell (with RerunEntireWorkflow)
Invoke-RestMethod -Uri "https://<your-api-domain>/api/workflow/start" `
  -Method POST `
  -Headers @{ "Authorization" = "Bearer <your-token>" } `
  -ContentType "application/json" `
  -Body (@{ "WorkflowFile" = "deploy.yaml"; "RerunEntireWorkflow" = $true } | ConvertTo-Json)
```

**Expected Response:**
```json
{
  "Id": "orchestration-instance-id"
}
```

**What happens next:**
- Orchestration instance is created in Durable Functions with specified workflow file
- GitHub workflow is dispatched with workflowName: `InternalApi-orchestration-instance-id`
- Orchestration waits for webhook events from GitHub
- If webhook event doesn't arrive in time, orchestrator queries GitHub for recent workflow runs

### Verify Workflow Execution

1. **Navigate to GitHub repository**
   - Go to **Actions** tab
   - You should see a new workflow run

2. **Check workflow details**
   - Workflow run name should be: `InternalApi-{instance-id}`
   - Status should show as "In progress" or "Completed"
   - Inputs should show workflowName matching the instance ID

3. **Verify workflow logs**
   - Click into the workflow run
   - Check job logs to ensure steps are executing correctly

### Validate Webhook Delivery

1. **Navigate to GitHub App settings**
   - Settings → Developer settings → GitHub Apps → Your App

2. **Check recent deliveries**
   - Click **Advanced** tab
   - View **Recent Deliveries**
   - Look for deliveries with green checkmarks (successful)

3. **Inspect delivery details**
   - Click on a delivery to see request/response details
   - Response status should be **200 OK**
   - Response headers should show successful processing

4. **Common webhook events to verify**
   - `workflow_run` with action: `in_progress` (when workflow starts)
   - `workflow_run` with action: `completed` (when workflow finishes)

## Security Considerations

### Critical Security Practices

**Store private keys ONLY in secure vaults** such as Azure Key Vault or HashiCorp Vault. Never store private keys in:
- Source control (Git repositories)
- Plain text configuration files
- Environment variables in shared environments
- Build/deployment logs

### Webhook Security

- **Workflow identifier filtering**: The `X-Workflow-Identifier` header ensures only webhooks for workflows starting with the `InternalApi-*` prefix are forwarded to the Functions app. Never expose the Functions webhook endpoint directly.
- **Octokit.Webhooks validation**: All webhook requests are deserialized using the type-safe Octokit.Webhooks library for payload validation
- **Payload integrity**: The webhook processor validates event types and payload structure before forwarding
- **Prefix filtering**: Only workflows matching the expected identifier prefix are processed, preventing unauthorized orchestration triggers


---

## Additional Resources

### GitHub Documentation
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Webhook Events and Payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
---
