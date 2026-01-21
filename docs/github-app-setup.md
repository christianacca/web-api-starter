# GitHub App Setup for Workflow Orchestration

## Overview

This document provides setup instructions for integrating a GitHub App with the Azure-hosted API and Functions applications to enable automated GitHub workflow orchestration with retry logic.

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
    
    Orchestrator->>GitHub: Dispatch workflow (correlationId: InternalApi-{instanceId})
    Note over GitHub: Workflow starts with name: InternalApi-{instanceId}
    
    GitHub->>API: Webhook: workflow_run (action: in_progress)
    API->>Middleware: Validate HMAC signature
    Middleware->>Middleware: Extract correlation ID from workflow name
    Middleware->>Middleware: Add X-Correlation-Id header
    API->>Functions: Route to webhook (header-based routing)
    Functions->>Orchestrator: Raise external event (WorkflowInProgress, runId)
    Orchestrator->>Orchestrator: Wait for completion event
    
    GitHub->>API: Webhook: workflow_run (action: completed)
    API->>Middleware: Validate HMAC signature
    Middleware->>Middleware: Add X-Correlation-Id header
    API->>Functions: Route to webhook (header-based routing)
    Functions->>Orchestrator: Raise external event (WorkflowCompleted, success)
    
    alt Workflow Failed
        Orchestrator->>GitHub: Rerun failed jobs (attempt 2)
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
2. **Dispatch**: Orchestrator dispatches GitHub workflow with unique correlation ID
3. **Tracking**: GitHub sends webhook events as workflow progresses
4. **Validation**: API middleware validates webhook signatures for security
5. **Routing**: Correlation ID header routes webhooks to Functions orchestrator
6. **Retry Logic**: On failure, orchestrator automatically reruns workflow up to MaxAttempts

---

## GitHub App Creation & Configuration

### Step 1: Create GitHub App

1. Navigate to **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
2. Configure basic information:
   - **GitHub App name**: Choose a descriptive name (e.g., `MyApp Workflow Orchestrator`)
   - **Description**: Brief description of the app's purpose
   - **Homepage URL**: Your application URL or GitHub repository URL

### Step 2: Set Permissions

Configure the following repository permissions:

| Permission | Access Level | Reason |
|------------|--------------|--------|
| **Actions** | Read & Write | Required to dispatch workflows and rerun failed jobs |
| **Metadata** | Read | Required for all GitHub Apps |

### Step 3: Configure Webhook

1. **Webhook URL**: `https://<your-api-domain>/api/workflow/webhook`
   - Replace `<your-api-domain>` with your actual API domain
   - Example: `https://api.myapp.com/api/workflow/webhook`

2. **Webhook secret**: Generate a secure webhook secret.

3. **Subscribe to events**: Check the following event:
   - **Workflow run** (workflow_run)

4. **Webhook active**: Ensure checkbox is checked

### Step 4: Generate Private Key

1. Scroll to the bottom of the app settings page
2. Click **Generate a private key**
3. Download the `.pem` file that is automatically generated
4. **IMPORTANT**: Store this file securely - it cannot be recovered if lost
5. Upload to Azure Key Vault immediately (see [Azure Configuration](#azure-configuration))

### Step 5: Note App ID

- The **App ID** is displayed at the top of the app settings page
- Example: `123456`
- You'll need this for configuration

### Step 6: Install App to Repository

1. In the left sidebar of your GitHub App settings, click **Install App**
2. Select the organization or account where your repository lives
3. Choose repository access:
   - **Only select repositories**: Choose the specific repository with your workflow
   - **All repositories**: Grant access to all repositories (not recommended for security)
4. Click **Install**

### Step 7: Get Installation ID

After installation, you need to retrieve the Installation ID:

- After installation, check the browser URL
- Format: `https://github.com/settings/installations/<installation-id>`

## Webhook Secret

1. Add the secret to your GitHub App webhook configuration
2. Store the same secret in Azure Key Vault for application configuration
3. Never commit the secret to source control

---

## GitHub Workflow Requirements

Your GitHub Actions workflow file must meet specific requirements for the orchestration to work correctly.

### Required Trigger

The workflow **must** accept `workflow_dispatch` trigger with a `correlationId` input:

```yaml
on:
  workflow_dispatch:
    inputs:
      correlationId:
        description: 'Correlation ID for tracking'
        required: true
        type: string
```

### Required Workflow Name Format

The workflow run name **must** use the correlationId input. This is how the system matches webhook events to orchestration instances:

```yaml
name: ${{ inputs.correlationId }}
```

### Example Minimal Workflow Structure

Here's a complete minimal example:

```yaml
name: ${{ inputs.correlationId }}

on:
  workflow_dispatch:
    inputs:
      correlationId:
        description: 'Correlation ID for tracking'
        required: true
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Display correlation ID
        run: echo "Processing with correlation ID: ${{ inputs.correlationId }}"
      
      - name: Your deployment steps
        run: |
          # Add your actual deployment logic here
          echo "Deploying application..."
```

### Important Notes

- The correlation ID format will be: `{FunctionAppIdentifier}-{orchestration-instance-id}`
- The workflow name **must exactly match** the correlationId input for tracking to work
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
    "WorkflowFile": null,
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

The API application uses header-based routing to direct webhook requests to the Functions app:

1. **Webhook Flow**: GitHub sends webhook events to `POST /api/workflow/webhook`
2. **Middleware Validation**: The `GithubWebhookMiddleware` validates the HMAC signature
3. **Header Injection**: After successful validation, middleware adds the correlation ID header (defined as `GithubHeaderNames.WorkflowCorrelationId` constant with value `"X-Correlation-Id"`) set to `InternalApi`
4. **Routing**: The reverse proxy (YARP) routes requests with this header to the Functions webhook endpoint
5. **Security**: This ensures only validated, internal webhook calls reach the Functions orchestration logic

This header-based routing pattern is configured in `appsettings.json` under `ReverseProxy.Routes.WorkflowWebhookFunctions`. The header name in the configuration must match the value of `GithubHeaderNames.WorkflowCorrelationId` defined in `src/Template.Shared/Github/GithubHeaderNames.cs`.

---

## Configuration Parameters Reference

Complete reference of all `Github` configuration parameters:

| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `Owner` | string | Yes | GitHub repository owner (username or organization name) | `myorg` or `john-doe` |
| `Repo` | string | Yes | Repository name | `my-application` |
| `Branch` | string | Yes | Branch name to trigger workflow on | `main` |
| `WorkflowFile` | string | Yes | Workflow file name (must exist in `.github/workflows/`) | `deploy.yaml` |
| `AppId` | string | Yes | GitHub App ID (found in app settings) | `123456` |
| `InstallationId` | long | Yes | Installation ID (obtained after installing app to repository) | `98765432` |
| `PrivateKeyPem` | string | Yes | GitHub App private key in PEM format (includes headers/footers) | `-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----` |
| `WebhookSecret` | string | Yes | Webhook secret for HMAC-SHA256 signature validation | `your-secret-here` |
| `MaxAttempts` | int | No | Maximum number of retry attempts for failed workflows (default: 5) | `5` |
| `WorkflowTimeoutHours` | int | No | Hours to wait for workflow completion before timeout (default: 12) | `12` |

### Important Notes

- **PrivateKeyPem Format**: Must include the full PEM format including `-----BEGIN RSA PRIVATE KEY-----` header and `-----END RSA PRIVATE KEY-----` footer, with newlines preserved (`\n`)
- **WorkflowFile**: Must match exactly the filename in the repository's `.github/workflows/` directory
- **MaxAttempts**: Total attempts = initial run + MaxAttempts retries (e.g., MaxAttempts=5 means up to 6 total runs)
- **WorkflowTimeoutHours**: Applies to each workflow run attempt, not total orchestration time

---

## Credential Rotation

Regular credential rotation is a security best practice. Follow these procedures to rotate GitHub App credentials without downtime.

### Rotating Private Key

GitHub Apps support multiple active private keys simultaneously, enabling zero-downtime rotation.

**Rotation Steps:**

1. **Generate new private key**
   - Navigate to GitHub App settings
   - Scroll to "Private keys" section
   - Click "Generate a private key"
   - Download the new `.pem` file

2. **Store new key in Azure Key Vault**
   - Upload new key as a new version of the existing secret
   - Or create a new secret with versioned name (e.g., `github-private-key-v2`)

3. **Update application configuration**
   - Update both API and Functions app settings
   - Point `PrivateKeyPem` to new Key Vault secret URI
   - Or update the value directly if not using Key Vault

4. **Deploy configuration changes**
   - Deploy updated configuration to all environments
   - Verify deployment success

5. **Verify new key is working**
   - Trigger a test workflow via API endpoint
   - Confirm workflow dispatches successfully
   - Check Application Insights logs for authentication success

6. **Revoke old private key**
   - Return to GitHub App settings
   - Click "Revoke" next to the old private key
   - Confirm revocation

**Best Practice**: Schedule key rotation every 90 days

**Rollback Plan**: If issues occur, the old key remains valid until explicitly revoked in step 6

### Rotating Webhook Secret

Webhook secret rotation requires coordination between GitHub and application configuration.

**Rotation Steps:**

1. **Generate new webhook secret**
   - Use one of the methods in [Webhook Secret Generation](#webhook-secret-generation)
   - Save the new secret securely

2. **Update GitHub App webhook configuration**
   - Navigate to GitHub App settings → Webhook
   - Update "Webhook secret" field with new secret
   - Save changes

3. **Update application configuration**
   - Store new secret in Azure Key Vault (or app settings)
   - Update both API and Functions configurations
   - **Note**: Old webhooks in flight may still use old secret until this deploys

4. **Deploy configuration changes**
   - Deploy to all environments
   - Monitor deployment progress

5. **Monitor webhook deliveries**
   - GitHub App settings → Advanced → Recent Deliveries
   - Verify successful deliveries (200 OK responses)
   - Check for signature validation failures in logs

6. **Verification period**
   - Monitor for 24-48 hours to ensure all webhook deliveries succeed
   - Check Application Insights for any signature validation errors

**Note**: Unlike private keys, GitHub does not support multiple active webhook secrets. There will be a brief period during deployment where webhook validation may fail if GitHub sends webhooks using the new secret before your app is updated.

**Mitigation Strategy**: Consider implementing dual-secret validation support in `GithubWebhookSignatureValidator` to support temporary overlap periods.

---

## Running

### Test Workflow Trigger

Trigger a workflow orchestration via the API endpoint:

```bash
# Using curl
curl -X POST https://<your-api-domain>/api/workflow/start \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json"

# Using PowerShell
Invoke-RestMethod -Uri "https://<your-api-domain>/api/workflow/start" `
  -Method POST `
  -Headers @{ "Authorization" = "Bearer <your-token>" } `
  -ContentType "application/json"
```

**Expected Response:**
```json
{
  "Id": "orchestration-instance-id"
}
```

**What happens next:**
- Orchestration instance is created in Durable Functions
- GitHub workflow is dispatched with correlationId: `InternalApi-orchestration-instance-id`
- Orchestration waits for webhook events from GitHub

### Verify Workflow Execution

1. **Navigate to GitHub repository**
   - Go to **Actions** tab
   - You should see a new workflow run

2. **Check workflow details**
   - Workflow run name should be: `InternalApi-{instance-id}`
   - Status should show as "In progress" or "Completed"
   - Inputs should show correlationId matching the instance ID

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

### Monitor Orchestration Status

**Azure Portal:**

1. Navigate to your Functions App in Azure Portal
2. Go to **Functions** → **WorkflowOrchestrator**
3. Click **Monitor** or **Invocation Details**
4. Find orchestration by instance ID from the API response
5. Verify state transitions:
   - **Running**: Orchestration is active
   - **Completed**: Orchestration finished successfully
   - **Failed**: Check error details

## Security Considerations

### Critical Security Practices

**ALWAYS validate webhook signatures** before processing webhook payloads. The `GithubWebhookMiddleware` performs HMAC-SHA256 validation using the configured webhook secret. Never bypass this validation.

**Store private keys ONLY in secure vaults** such as Azure Key Vault or HashiCorp Vault. Never store private keys in:
- Source control (Git repositories)
- Plain text configuration files
- Environment variables in shared environments
- Build/deployment logs

**Never commit secrets to source control**. Use `.gitignore` to exclude:
- `appsettings.Development.json` (if it contains secrets)
- `*.pem` files
- Any files containing webhook secrets or tokens

### Authentication & Authorization

- **Use managed identities** for Azure resource access (Key Vault, Storage, etc.)
- **Implement authentication** on the `/api/workflow/start` endpoint using:
  - Azure AD authentication tokens
  - API keys stored in Key Vault
  - OAuth 2.0 client credentials flow
- **Restrict network access** to webhook endpoint if possible (GitHub webhook IP ranges)

### Webhook Security

- **Correlation ID header validation**: The `X-Correlation-Id: InternalApi-*` header ensures only webhooks processed by your API middleware reach the Functions app. Never expose the Functions webhook endpoint directly.
- **HMAC signature validation**: All webhook requests are validated using HMAC-SHA256 before processing
- **Payload integrity**: The middleware reads and validates the full request body before forwarding
- **Request buffering**: The middleware enables buffering to allow signature validation without consuming the request stream

### Network Security

- **Use HTTPS exclusively** for all webhook URLs (GitHub requires HTTPS for webhooks)
- **Configure CORS policies** appropriately in API settings
- **Use Azure Private Endpoints** where possible to restrict Functions app access
- **Implement rate limiting** on the `/api/workflow/start` endpoint to prevent abuse

### Monitoring & Alerting

- **Monitor webhook validation failures** for potential security issues or attacks
- **Alert on signature validation failures** (could indicate misconfiguration or tampering attempts)
- **Track orchestration failures** that could indicate malicious workflow modifications
- **Audit credential access** in Key Vault access logs

### Credential Management

- **Rotate credentials regularly** (recommended: every 90 days)
- **Use separate credentials per environment** (dev, staging, production)
- **Implement least-privilege access** for GitHub App permissions
- **Revoke unused keys** immediately after rotation
- **Enable Key Vault soft delete** and purge protection

### GitHub App Permissions

- **Grant minimal required permissions**: Only Actions: Read & Write and Metadata: Read
- **Limit repository access**: Install app only to specific repositories that need orchestration
- **Review permission requests**: GitHub will prompt if app requests additional permissions
- **Audit app installations**: Regularly review where the GitHub App is installed

### Compliance Considerations

- **Log all workflow triggers** for audit trails
- **Implement data retention policies** for orchestration logs
- **Document security procedures** in compliance runbooks
- **Conduct regular security reviews** of the integration
- **Test disaster recovery procedures** including credential rotation and revocation

---

## API Endpoints Reference

### Start Workflow Orchestration

Initiates a new Durable Functions orchestration that will trigger and monitor a GitHub workflow.

**Endpoint:**
```
POST /api/workflow/start
```

**Headers:**
```
Authorization: Bearer <your-auth-token>
Content-Type: application/json
```

**Request Body:**
```
None (empty body)
```

**Success Response:**
```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "Id": "abc123-def456-ghi789-orchestration-instance-id"
}
```

**Response Fields:**
- `Id`: Unique orchestration instance identifier. Use this to track orchestration status and correlate with GitHub workflow runs.

**Example Usage:**
```bash
curl -X POST https://api.myapp.com/api/workflow/start \
  -H "Authorization: Bearer your-token-here" \
  -H "Content-Type: application/json"
```

**What Happens:**
1. Durable orchestration instance is created
2. GitHub workflow is dispatched with correlationId: `InternalApi-{instanceId}`
3. Orchestration waits for GitHub webhook events
4. Returns instance ID immediately (does not wait for workflow completion)

---

### Webhook Endpoint (GitHub → API)

Receives GitHub webhook events for workflow runs. This endpoint is called by GitHub, not by users.

**Endpoint:**
```
POST /api/workflow/webhook
```

**Headers (sent by GitHub):**
```
X-Hub-Signature-256: sha256=<hmac-signature>
X-GitHub-Event: workflow_run
X-GitHub-Delivery: <unique-delivery-id>
Content-Type: application/json
User-Agent: GitHub-Hookshot/<version>
```

**Request Body:**
```json
GitHub workflow_run webhook payload (see GitHub webhook documentation)
```

**Success Response:**
```
HTTP/1.1 200 OK
```

**Error Responses:**

```
HTTP/1.1 401 Unauthorized
Invalid signature
```
- **Cause**: Webhook signature validation failed
- **Solution**: Verify webhook secret matches configuration

```
HTTP/1.1 400 Bad Request
Invalid request body
```
- **Cause**: Malformed JSON payload
- **Solution**: Check GitHub webhook delivery details for payload structure

**Processing Flow:**
1. API middleware validates HMAC-SHA256 signature
2. Middleware extracts correlation ID from workflow run name
3. Middleware adds `X-Correlation-Id` header
4. Request is routed to Functions webhook endpoint via reverse proxy
5. Functions raises external event to corresponding orchestration instance

**Security Notes:**
- All webhook requests are validated using HMAC-SHA256 signature
- Only requests with valid signatures are forwarded to Functions
- Correlation ID header ensures only validated requests reach orchestrator

---

## Additional Resources

### GitHub Documentation
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Webhook Events and Payloads](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
---
