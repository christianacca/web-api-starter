# GitHub App Creation Guide

## Overview

This guide walks through the process of creating and configuring a GitHub App for use with workflow orchestration systems. The process is divided into responsibilities between three teams:

- **Dev Team**: Generates ServiceNow ticket request with environment-specific details
- **GitHub Admin Team**: Creates the GitHub App for the specified environment, generates credentials, and provides initial configuration
- **App Admin Team**: Uploads credentials to Azure Key Vault for the specified environment
- **Dev Team**: Configures App ID and Installation ID for the environment in the application code

**Note**: This guide describes the process for creating and configuring a GitHub App for **one environment**. To set up multiple environments, repeat this entire process for each environment separately.

---

## Part 1: Dev Team - Generate ServiceNow Ticket Request

### Prerequisites

Before requesting GitHub App creation, the Dev Team must:
- Clone the repository locally:
  ```bash
  git clone https://github.com/christianacca/web-api-starter.git
  cd web-api-starter
  ```
- Generate a ServiceNow ticket with all required information for the GitHub Admin Team

### Run the ServiceNow Ticket Generator Script

Run the script `tools/infrastructure/generate-github-app-servicenow-ticket.ps1` to generate the ServiceNow ticket subject and body with environment-specific details.

**Script Usage:**

```powershell
cd tools/infrastructure
./generate-github-app-servicenow-ticket.ps1 -EnvironmentName <environment>
```

**Available Environment Names:**
- `dev`
- `qa`, `rel`, `release`
- `demo`, `demo-na`, `demo-emea`, `demo-apac`
- `staging`
- `prod-na`, `prod-emea`, `prod-apac`

**Example: Generate ticket for Dev environment**
```powershell
./generate-github-app-servicenow-ticket.ps1 -EnvironmentName dev
```

**Example Output:**

The script will output ServiceNow ticket fields:

```
ServiceNow Ticket Details:
─────────────────────────────────────────────────────────────

Request Title:
GitHub App Creation Request - Web API Starter (dev)

Request Type:
General IT Request

Priority:
3 - Moderate

Description:
Purpose:
This GitHub App is required to enable workflow orchestration for the dev environment. 
The application uses GitHub Apps to securely authenticate with GitHub and receive webhook notifications 
when workflows complete. This allows the application to monitor and respond to GitHub Actions workflow 
execution, enabling automated deployment pipelines and CI/CD orchestration.

Environment Details:
- Environment Name: dev
- GitHub App Name: Web API Starter (dev)
- API Domain: dev-api-was.codingdemo.co.uk
- Webhook URL: https://dev-api-was.codingdemo.co.uk/api/github/webhooks

Repository Information:
- Repository: christianacca/web-api-starter
- Branch: master

Required Permissions:
- Actions: Read & Write
- Metadata: Read

Webhook Configuration:
- Subscribe to Events: Workflow run
- Webhook Active: Yes

Next Steps:
1. Create GitHub App with the above configuration
2. Install app to repository: christianacca/web-api-starter
3. Generate private key (.pem file)
4. Generate webhook secret
5. Provide the following to App Admin Team:
   - App ID
   - Installation ID
   - Private key .pem file (securely)
   - Webhook secret (securely)

Please refer to the GitHub App Creation Guide - GitHub Admin Team Responsibilities:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#part-2-github-admin-team-responsibilities
```

### Create ServiceNow Ticket

1. **Copy the generated Request Title and Description** from the script output and create a ticket of the specified **Request Type** and **Priority**
2. **Create a new ServiceNow ticket** and fill in the corresponding fields
3. **Submit the ticket** to the GitHub Admin Team

---

## Part 2: GitHub Admin Team Responsibilities

### Prerequisites

Before creating a GitHub App, ensure you have the necessary permissions:

- **App Manager Permission**: You must have the App Manager role in your GitHub organization to create and manage GitHub Apps
  - Organization owners have this permission by default
  - To verify or request this permission, contact your GitHub organization owner
  - Learn more: [GitHub App Manager role](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization#github-app-managers)

### Step 1: Create GitHub App

1. Navigate to your **GitHub Organization page** → **Settings** → **GitHub Apps** → **New GitHub App**
2. Configure basic information:
   - **GitHub App name**: Use the exact name from the ServiceNow ticket
   - Example: `Web API Starter (dev)`, `Web API Starter (prod-na)`
   - **Description**: Brief description of the app's purpose
   - **Homepage URL**: Use the **API Domain** from the ServiceNow ticket (e.g., `https://dev-api-was.codingdemo.co.uk`)

![GitHub App Name and Description](assets/creating%20github%20app-%20name%20and%20description.png)

### Step 2: Set Permissions

Configure the repository permissions as provided by the Developer Team:

| Permission | Access Level |
|------------|--------------|
| **Actions** | Read & Write |
| **Metadata** | Read |

For a complete list of available permissions, see: [GitHub App Permissions Reference](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps)

![GitHub App Permissions](assets/creating%20github%20app-%20permissions.png)

### Step 3: Generate and Save Webhook Secret

Generate a secure webhook secret that will be used to validate webhook requests from GitHub.

**Using PowerShell:**
```powershell
$bytes = New-Object Byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$webhookSecret = [Convert]::ToBase64String($bytes)
Write-Host $webhookSecret
```

**Using OpenSSL (Git Bash or Linux/Mac):**
```bash
openssl rand -base64 32
```

**IMPORTANT**: Save this webhook secret securely - you will need to:
1. Enter it in the GitHub App webhook configuration (Step 4)
2. Share it securely with the App Admin Team for Key Vault upload

### Step 4: Configure Webhook

Configure the webhook settings for the GitHub App using the information from the ServiceNow ticket:

1. **Webhook URL**: Use the exact **Webhook URL** from the ServiceNow ticket
   - Example from ticket: `https://dev-api-was.codingdemo.co.uk/api/github/webhooks`

2. **Webhook secret**: Enter the webhook secret you generated in Step 3

3. **Subscribe to events**: Check the following event:
   - **Workflow run**
   - For more information on available events, see: [GitHub App Webhook Events](https://docs.github.com/en/webhooks/webhook-events-and-payloads)

4. **Webhook active**: Ensure this checkbox is checked

![GitHub App Webhook Setup](assets/creating%20github%20app-%20webhooks%20setup.png)

![GitHub App Events](assets/creating%20github%20app-%20events.png)

### Step 5: Generate Private Key

1. Scroll to the bottom of the app settings page
2. Click **Generate a private key**
3. Download the `.pem` file that is automatically generated
4. **CRITICAL**: Store this file securely - it cannot be recovered if lost

![GitHub App Generate Private Key](assets/creating%20github%20app-%20generate%20a%20private%20key.png)

### Step 6: Note App ID

- The **App ID** is displayed at the top of the app settings page
- **Note**: This ID is always available in the GitHub App settings and can be retrieved at any time
- Copy this ID for the handover to the App Admin Team and Dev Team

### Step 7: Install GitHub App to Repository

The GitHub App must be installed to the `christianacca/web-api-starter` repository for the app to function correctly.

#### Installation Process

1. In the left sidebar of your GitHub App settings, click **Install App**
2. Select the **christianacca** user account
3. Choose repository access:
   - Select **Only select repositories**
   - Select the **web-api-starter** repository
4. Review the permissions that will be granted:
   - Ensure they match the permissions configured in Step 2
   - The selected repository will have the GitHub App installed with these permissions
5. Click **Install** to complete the installation

#### Post-Installation Verification

After installation, verify the app is correctly installed:

1. Navigate to the `christianacca/web-api-starter` repository
2. Go to **Settings** → **Integrations** → **GitHub Apps**
3. Confirm your GitHub App appears in the list of installed apps
4. Verify the app has the correct permissions (Actions: Read & Write, Metadata: Read)

### Step 8: Get Installation ID

After installation, retrieve the Installation ID:

1. After clicking **Install**, check the browser URL
2. Format: `https://github.com/settings/installations/<installation-id>`
3. Note the `<installation-id>` number from the URL
4. Save this ID for handover to the App Admin Team and Dev Team

---

## Part 3: Handover to App Admin Team

### GitHub Admin Team: Information Handover

After completing the GitHub App creation and installation, the GitHub Admin Team must securely share the following with the App Admin Team:

#### Required Information to Share

1. **ServiceNow Ticket Number**
   - The ticket number from the initial GitHub App creation request
   - This helps the App Admin Team track and reference the request

2. **Environment Name**
   - The environment for which this GitHub App was created
   - Example: `dev`, `prod-na`, `staging`
   - This tells the App Admin Team which Key Vault to upload credentials to

3. **App ID**
   - Location: Displayed at the top of the GitHub App settings page
   - Example: `123456`

4. **Installation ID**
   - Location: Extracted from the browser URL after installing the app (Step 8)
   - Example: `98765432`

4. **Private Key (.pem file)**
   - Location: Downloaded in Step 5
   - **Share securely**: Use encrypted communication or secure file sharing
   - The App Admin Team will upload this to Azure Key Vault

5. **Webhook Secret**
   - Location: Generated in Step 3
   - **Share securely**: Use encrypted communication (never commit to source control)
   - The App Admin Team will upload this to Azure Key Vault

---

## Part 4: App Admin Team Responsibilities

### Prerequisites

- Clone the repository locally:
  ```bash
  git clone https://github.com/christianacca/web-api-starter.git
  cd web-api-starter
  ```
- Install az-cli (authentication is handled automatically by the script)
    * mac: `brew update && brew install azure-cli`
    * windows: `choco install azure-cli` (note: you to restart command prompt after installation)
- Access to Azure subscription with permissions to upload secrets to Key Vault
  - If you don't have the required permissions, run the [Infrastructure Grant Azure Environment Access](https://github.com/christianacca/web-api-starter/actions/workflows/infra-grant-azure-env-access.yml) workflow:
    1. Click the workflow link above
    2. Click **Run workflow**
    3. Select the target environment
    4. Choose **App Admin** as the access level
    5. Enter your user principal name (email)
    6. Click **Run workflow**

### Upload Credentials to Azure Key Vault

The App Admin Team is responsible for uploading the GitHub App credentials to Azure Key Vault for the environment specified in the ServiceNow ticket using the provided PowerShell script.

#### Upload Process

1. **Save the Private Key File**
   - Save the .pem file received from the GitHub Admin Team to a secure temporary location
   - Example: `C:/temp/github-app-private-key.pem`

2. **Run the Upload Script**

   The script `tools/infrastructure/upload-github-app-secrets.ps1` will:
   - Auto-detect the Key Vault name for the environment
   - Upload the private key as `Github--PrivateKeyPem`
   - Upload the webhook secret as `Github--WebhookSecret`
   - Verify successful upload

   **Example for dev environment:**
   ```powershell
   cd tools/infrastructure
   ./upload-github-app-secrets.ps1 `
     -EnvironmentName dev `
     -PemFilePath "C:/temp/github-app-private-key.pem" `
     -WebhookSecret "the-webhook-secret-from-github-admin"
   ```

   **Note**: Use the environment name that matches the one specified in the ServiceNow ticket (see Part 1 for available environment names).

3. **Verify Upload Success**

   After running the script, you should see output similar to:
   ```
   Upload completed successfully

   Configuration Details:
   Key Vault Name    GitHub App Name       GitHub App Slug    GitHub Webhook URL                                      Webhook Secret
   kv-was-dev        Web API Starter - Dev was-dev            https://dev-api-was.codingdemo.co.uk/api/github/webhooks <secret-value>
   ```

#### Security Cleanup

After successfully uploading to the environment:

1. **Delete the .pem file** from your local machine

2. **Clear the webhook secret** from your terminal/clipboard history

3. **Verify secrets are accessible** in the Key Vault before proceeding

#### Handover to Dev Team

After completing the upload, provide the Dev Team with:

1. **App ID** (received from GitHub Admin Team)
2. **Installation ID** (received from GitHub Admin Team)
3. **Environment Name** (the environment for which credentials were uploaded)
4. **Confirmation** that credentials have been successfully uploaded to the Key Vault

---

## Part 5: Dev Team - Configure Application Code

### Configure GitHub App in Application Code

The Dev Team must update the `tools/infrastructure/get-product-github-app-config.ps1` file with the App ID and Installation ID for the environment.

### Update Configuration File

1. **Open the configuration file**
   - File: `tools/infrastructure/get-product-github-app-config.ps1`

2. **Update the App ID and Installation ID** for the environment

   Each environment has its own GitHub App with unique App ID and Installation ID.
   
   Example for dev environment:
   ```powershell
   'dev' {
       @{
           AppId          = '2800205'        # App ID for dev environment
           InstallationId = '108147870'      # Installation ID for dev environment
       }
   }
   ```
   
   Example for prod-na environment:
   ```powershell
   'prod-na' {
       @{
           AppId          = '2800210'        # App ID for prod-na environment
           InstallationId = '108147875'      # Installation ID for prod-na environment
       }
   }
   ```

---

## Security and Private Key Management

### Private Key Rotation

For security best practices, the GitHub App private key should be rotated regularly (recommended: every 90-180 days). The rotation process involves coordination between the GitHub Admin Team and App Admin Team.

#### Rotation Process Overview

1. **GitHub Admin Team**: Generates new private key in GitHub App settings
2. **GitHub Admin Team**: Securely shares new private key with App Admin Team
3. **App Admin Team**: Uploads new private key to all environment Key Vaults
4. **App Admin Team**: Confirms successful upload
5. **GitHub Admin Team**: Deletes old private key from GitHub App settings

### Part 1: Dev Team - Generate Private Key Rotation Request

When private key rotation is needed, the Dev Team initiates the process by generating a ServiceNow ticket.

**Prerequisites:**
- Ensure the repository is cloned locally (if not already done):
  ```bash
  git clone https://github.com/christianacca/web-api-starter.git
  cd web-api-starter
  ```

**Run the ServiceNow Ticket Generator Script:**

```powershell
cd tools/infrastructure
./generate-github-app-key-rotation-ticket.ps1 -EnvironmentName dev
```

**Note**: This generates a rotation ticket for one environment. If multiple environments need rotation, generate separate tickets for each.

**Example Output:**

```
ServiceNow Ticket Details:
─────────────────────────────────────────────────────────────

Request Title:
GitHub App Private Key Rotation Request - Web API Starter (dev)

Request Type:
General IT Request

Priority:
3 - Moderate

Description:
GitHub App Information:
- GitHub App Name: Web API Starter (dev)
- Environment: dev
- Repository: christianacca/web-api-starter

Rotation Process:
1. GitHub Admin Team:
   - Navigate to GitHub App settings
   - Generate a new private key (.pem file)
   - Download the new .pem file
   - Securely share the new .pem file with App Admin Team
   - DO NOT delete the old key yet

2. App Admin Team:
   - Receive new .pem file from GitHub Admin Team
   - Upload to dev environment Key Vault using:
     tools/infrastructure/upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath <path>
   - Verify successful upload to dev environment
   - Confirm completion to GitHub Admin Team

3. GitHub Admin Team:
   - After receiving confirmation from App Admin Team
   - Delete the OLD private key from GitHub App settings
   - Confirm deletion

Please refer to the GitHub App Creation Guide - Private Key Rotation section:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#part-2-github-admin-team---generate-new-private-key
```

**Create ServiceNow Ticket:**

1. **Copy the generated Request Title, Request Type, Priority, and Description** from the script output
2. **Create a new ServiceNow ticket** and fill in the corresponding fields
3. **Submit to GitHub Admin Team and App Admin Team**
4. **Track the rotation process through completion**

### Part 2: GitHub Admin Team - Generate New Private Key

1. **Navigate to GitHub App Settings**
   - Go to GitHub → Settings → Developer settings → GitHub Apps
   - Select your GitHub App (e.g., "Web API Starter (dev)", "Web API Starter (prod-na)", etc.)

2. **Generate New Private Key**
   - Scroll to the "Private keys" section
   - Click **Generate a private key**
   - Download the new `.pem` file
   - **Important**: The old key remains active - do not delete it yet

3. **Securely Share with App Admin Team**
   - Use encrypted communication (e.g., Azure Key Vault, 1Password, secure file sharing)
   - Share the new `.pem` file with App Admin Team
   - Include the ServiceNow ticket number and environment name in communication

4. **Wait for Confirmation**
   - Wait for App Admin Team to confirm successful upload to the environment
   - Do not delete the old key until confirmation is received

### Part 3: App Admin Team - Upload New Private Key

1. **Receive New Private Key**
   - Securely receive the new `.pem` file from GitHub Admin Team
   - Save to a temporary secure location

2. **Upload to the Environment Key Vault**

   **Prerequisites:**
   - Ensure the repository is cloned locally (if not already done):
     ```bash
     git clone https://github.com/christianacca/web-api-starter.git
     cd web-api-starter
     ```

   Use the upload script for the environment specified in the ServiceNow ticket. When rotating the private key, provide only the `-PemFilePath` parameter to upload just the private key without modifying the existing webhook secret:

   ```powershell
   cd tools/infrastructure
   
   # Example: Upload to dev (only private key, preserves existing webhook secret)
   ./upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath "C:/temp/new-github-app-key.pem"
   ```

   **Note**: The script will:
   - Update the `Github--PrivateKeyPem` secret with the new private key
   - Skip webhook secret (since `-WebhookSecret` parameter is not provided)
   - Display a message "Skipping webhook secret upload (not provided)"

3. **Verify Upload Success**

   Verify the upload was successful by checking the script output for:
   - "Upload completed successfully" message
   - Correct Key Vault name
   - Correct GitHub App name


5. **Confirm to GitHub Admin Team**
   - Notify GitHub Admin Team that the environment has been updated
   - Include the environment name in your confirmation
   - Confirm it's safe to delete the old private key

6. **Delete Local Copy**
   - Delete the new private key .pem file from your local machine

### Part 4: GitHub Admin Team - Delete Old Private Key

1. **Receive Confirmation from App Admin Team**
   - Verify App Admin Team has confirmed successful upload to the environment
   - Verify testing has been completed (if applicable)

2. **Delete Old Private Key from GitHub**
   - Navigate to GitHub App settings
   - Scroll to "Private keys" section
   - Locate the **old** private key (check the creation date)
   - Click **Delete** next to the old key
   - Confirm deletion

3. **Update ServiceNow Ticket**
   - Mark the rotation as complete
   - Document the completion date
   - Close the ticket

4. **Test Workflow Integration** (Optional but Recommended)
   After completing the private key rotation, verify the GitHub App is working correctly by testing the workflow orchestration:

   - Run the **Trigger Workflow** request in the Postman collection (`tests/postman/api.postman_collection.json`)
   - Verify the workflow runs successfully in GitHub Actions
   - Confirm the GitHub App authenticates with the new private key and webhooks are processed correctly

### Rotation Schedule Recommendations

- **Regular Rotation**: Every 90-180 days
- **Emergency Rotation**: Immediately if:
  - Private key is suspected to be compromised
  - Team member with access to the key leaves the organization
  - Security audit requires immediate rotation

---

## Security Best Practices

### Private Key Management

- **NEVER commit the private key to source control**
- **GitHub Admin Team**: Delete the `.pem` file immediately after securely sharing with App Admin Team
- **App Admin Team**: Delete the `.pem` file immediately after uploading to all required Key Vaults
- Store the private key only in Azure Key Vault (uploaded by App Admin Team)
- Restrict Key Vault access to only necessary personnel and services
- Use managed identities when accessing the private key from applications

### Webhook Secret

- **GitHub Admin Team**: Generate a strong, cryptographically random webhook secret
- **App Admin Team**: Upload the secret to Key Vault and then delete from local storage
- Never commit the secret to source control
- Rotate the secret regularly (recommended: every 90 days)

#### Webhook Secret Rotation

**IMPORTANT**: Unlike private keys, webhook secrets do NOT have a sunset period. GitHub only allows one active webhook secret at a time per app. This means rotation must be carefully coordinated between the GitHub Admin Team and App Admin Team to minimize downtime.

**Rotation Process:**

1. **Plan a maintenance window**: Choose a time when webhook processing downtime is acceptable (typically during off-hours)

2. **GitHub Admin Team**:
   - Generate a new webhook secret using the same method as initial creation (Step 3)
   - **DO NOT update GitHub App settings yet**
   - Securely share the new webhook secret with App Admin Team

3. **App Admin Team**:
   - Upload the new webhook secret to the environment's Key Vault:
     ```powershell
     cd tools/infrastructure
     ./upload-github-app-secrets.ps1 -EnvironmentName <env> -WebhookSecret "<new-secret>"
     ```
   - Replace `<env>` with the environment name (e.g., `dev`, `prod-na`)
   - Replace `<new-secret>` with the actual webhook secret from GitHub Admin Team
   - Verify successful upload
   - Confirm completion to GitHub Admin Team

4. **GitHub Admin Team** (after App Admin confirmation):
   - Update the webhook secret in GitHub App settings immediately
   - Navigate to GitHub App → General → Webhook secret
   - Enter the new webhook secret
   - Save changes

**Note**: There will be a brief period between when the App Admin Team uploads the new secret and when the GitHub Admin Team updates it in GitHub settings. During this time, webhooks will continue to work with the old secret. After GitHub Admin updates the secret, any delay in Key Vault cache refresh may cause a brief period of webhook validation failures until the application picks up the new secret from Key Vault.

---

## Additional Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/creating-github-apps/creating-a-github-app)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)
