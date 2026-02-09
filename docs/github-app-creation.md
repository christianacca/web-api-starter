# GitHub App Creation Guide

## Overview

This guide walks through the process of creating and configuring a GitHub App for use with workflow orchestration systems. The process is divided into responsibilities between three teams:

- **Dev Team**: Generates ServiceNow ticket request with environment-specific details
- **GitHub Admin Team**: Creates the GitHub App, generates credentials, and provides initial configuration
- **App Admin Team**: Uploads credentials to Azure Key Vault for each environment
- **Dev Team**: Configures App ID and Installation ID in the application code

---

## Part 1: Dev Team - Generate ServiceNow Ticket Request

### Prerequisites

Before requesting GitHub App creation, the Dev Team must generate a ServiceNow ticket with all required information for the GitHub Admin Team.

### Run the ServiceNow Ticket Generator Script

Run the script `tools/infrastructure/generate-github-app-servicenow-ticket.ps1` (to be created) to generate the ServiceNow ticket subject and body with environment-specific details.

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

The script will output a ServiceNow ticket subject and body containing:

```
ServiceNow Ticket Subject:
─────────────────────────────────────────────────────────────
GitHub App Creation Request - Web API Starter - Dev

ServiceNow Ticket Body:
─────────────────────────────────────────────────────────────
Request Type: GitHub App Creation

Environment Details:
- Environment Name: dev
- GitHub App Name: Web API Starter - Dev
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

Please refer to the GitHub App Creation Guide for detailed instructions:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md
```

### Create ServiceNow Ticket

1. **Copy the generated ticket subject and body** from the script output
2. **Create a new ServiceNow ticket** with the above subject and body
3. **Submit the ticket** to the GitHub Admin Team

### Wait for GitHub Admin Team

The GitHub Admin Team will:
- Create the GitHub App according to the specifications
- Install it to the `christianacca/web-api-starter` repository
- Generate and securely share credentials with the App Admin Team

---

## Part 2: GitHub Admin Team Responsibilities

### Prerequisites

Before creating a GitHub App, ensure you have the necessary permissions:

- **App Manager Permission**: You must have the App Manager role in your GitHub organization to create and manage GitHub Apps
  - Organization owners have this permission by default
  - To verify or request this permission, contact your GitHub organization owner
  - Learn more: [GitHub App Manager role](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization#github-app-managers)

### Step 1: Create GitHub App

1. Navigate to **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
2. Configure basic information:
   - **GitHub App name**: Use the exact name from the ServiceNow ticket
   - Example: `Web API Starter - Dev`, `Web API Starter - Prod-Na`
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

1. **App ID**
   - Location: Displayed at the top of the GitHub App settings page
   - Example: `123456`

2. **Installation ID**
   - Location: Extracted from the browser URL after installing the app (Step 8)
   - Example: `98765432`

3. **Private Key (.pem file)**
   - Location: Downloaded in Step 5
   - **Share securely**: Use encrypted communication or secure file sharing
   - The App Admin Team will upload this to Azure Key Vault

4. **Webhook Secret**
   - Location: Generated in Step 3
   - **Share securely**: Use encrypted communication (never commit to source control)
   - The App Admin Team will upload this to Azure Key Vault

#### Handover Template

Use the following template to share information with the App Admin Team:

```
ServiceNow Ticket: [Ticket Number]
Environment: [Environment Name]
App ID: [Copy from GitHub App settings page]
Installation ID: [Copy from browser URL after installation]
Private Key: [Attach .pem file via secure file sharing method]
Webhook Secret: [Share via secure communication channel]
```

#### Handover Checklist

- [ ] App ID noted and shared
- [ ] Installation ID noted and shared
- [ ] Private key .pem file shared securely with App Admin Team
- [ ] Webhook secret shared securely with App Admin Team
- [ ] App Admin Team has confirmed receipt of all information
- [ ] Private key .pem file deleted from GitHub Admin Team workstation after confirmation
- [ ] Webhook secret cleared from GitHub Admin Team terminal/clipboard history after confirmation

---

## Part 4: App Admin Team Responsibilities

### Prerequisites

- Azure CLI installed (authentication is handled automatically by the script)
  - If not installed, refer to the [Dev Setup Guide](dev-setup.md) for installation instructions
- Access to Azure subscription with permissions to upload secrets to Key Vault
  - If you don't have the required permissions, run the [Infrastructure Grant Azure Environment Access](https://github.com/christianacca/web-api-starter/actions/workflows/infra-grant-azure-env-access.yml) workflow:
    1. Click the workflow link above
    2. Click **Run workflow**
    3. Select the target environment
    4. Choose **App Admin** as the access level
    5. Enter your user principal name (email)
    6. Click **Run workflow**
- Received the following from GitHub Admin Team:
  - App ID
  - Installation ID
  - Private key .pem file (securely shared)
  - Webhook secret (securely shared)

### Upload Credentials to Azure Key Vault

The App Admin Team is responsible for uploading the GitHub App credentials to Azure Key Vault for each environment using the provided PowerShell script.

#### Upload Process

1. **Save the Private Key File**
   - Save the .pem file received from the GitHub Admin Team to a secure temporary location
   - Example: `C:/temp/github-app-private-key.pem`

2. **Run the Upload Script for Each Environment**

   The script `tools/infrastructure/upload-github-app-secrets.ps1` will:
   - Auto-detect the Key Vault name for the environment
   - Upload the private key as `Github--PrivateKeyPem`
   - Upload the webhook secret as `Github--WebhookSecret`
   - Verify successful upload

   **Example:**
   ```powershell
   cd tools/infrastructure
   ./upload-github-app-secrets.ps1 `
     -EnvironmentName dev `
     -PemFilePath "C:/temp/github-app-private-key.pem" `
     -WebhookSecret "the-webhook-secret-from-github-admin"
   ```

   **Available Environment Names:**
   - `dev`
   - `qa`, `rel`, `release`
   - `demo`, `demo-na`, `demo-emea`, `demo-apac`
   - `staging`
   - `prod-na`, `prod-emea`, `prod-apac`

3. **Verify Upload Success**

   After running the script, you should see output similar to:
   ```
   Upload completed successfully

   Configuration Details:
   Key Vault Name    GitHub App Name       GitHub App Slug    GitHub Webhook URL                                      Webhook Secret
   kv-was-dev        Web API Starter - Dev was-dev            https://dev-api-was.codingdemo.co.uk/api/github/webhooks <secret-value>
   ```

4. **Repeat for All Environments**
   - Upload credentials to each environment where the GitHub App will be used
   - Keep a record of which environments have been configured

#### Security Cleanup

After successfully uploading to all required environments:

1. **Delete the .pem file** from your local machine

2. **Clear the webhook secret** from your terminal/clipboard history

3. **Verify secrets are accessible** in each Key Vault before proceeding

#### Handover to Dev Team

After completing the uploads, provide the Dev Team with:

1. **App ID** (received from GitHub Admin Team)
2. **Installation ID** (received from GitHub Admin Team)
3. **Confirmation** that credentials have been uploaded to all required environments

---

## Part 5: Dev Team - Configure Application Code

### Configure GitHub App in Application Code

The Dev Team must update the `tools/infrastructure/get-product-github-app-config.ps1` file with the App ID and Installation ID for each environment.

#### Update Configuration File

1. **Open the configuration file**
   - File: `tools/infrastructure/get-product-github-app-config.ps1`

2. **Update the App ID and Installation ID** for each environment

   Each environment has its own GitHub App with unique App ID and Installation ID.
   
   Example:
   ```powershell
   'dev' {
       @{
           AppId          = '2800205'        # Unique App ID for dev environment
           InstallationId = '108147870'      # Unique Installation ID for dev environment
       }
   }
   'prod-na' {
       @{
           AppId          = '2800210'        # Unique App ID for prod-na environment
           InstallationId = '108147875'      # Unique Installation ID for prod-na environment
       }
   }
   ```

3. **Commit and push changes**
   ```bash
   git add tools/infrastructure/get-product-github-app-config.ps1
   git commit -m "Configure GitHub App credentials for environments"
   git push
   ```

#### Verify Configuration

The application will now use:
- **App ID and Installation ID** from `get-product-github-app-config.ps1`
- **Private Key and Webhook Secret** from Azure Key Vault (uploaded by App Admin Team)

These credentials will be used across all environments to authenticate with GitHub and process webhook events.

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

**Run the ServiceNow Ticket Generator Script:**

```powershell
cd tools/infrastructure
./generate-github-app-key-rotation-ticket.ps1 -EnvironmentName dev
```

**Note**: Run this script for each environment that requires key rotation.

**Example Output:**

```
ServiceNow Ticket Subject:
─────────────────────────────────────────────────────────────
GitHub App Private Key Rotation Request - Web API Starter (dev)

ServiceNow Ticket Body:
─────────────────────────────────────────────────────────────
Request Type: GitHub App Private Key Rotation

GitHub App Information:
- GitHub App Name: Web API Starter
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

Please refer to the GitHub App Creation Guide - Security and Private Key Management section:
https://github.com/christianacca/web-api-starter/blob/master/docs/github-app-creation.md#security-and-private-key-management

✓ Copy the above information and create a ServiceNow ticket
```

**Create ServiceNow Ticket:**

1. Copy the generated ticket subject and body
2. Create a new ServiceNow ticket
3. Submit to GitHub Admin Team and App Admin Team
4. Track the rotation process through completion

### Part 2: GitHub Admin Team - Generate New Private Key

1. **Navigate to GitHub App Settings**
   - Go to GitHub → Settings → Developer settings → GitHub Apps
   - Select your GitHub App (e.g., "Web API Starter - Dev", "Web API Starter - Prod", etc.)

2. **Generate New Private Key**
   - Scroll to the "Private keys" section
   - Click **Generate a private key**
   - Download the new `.pem` file
   - **Important**: The old key remains active - do not delete it yet

3. **Securely Share with App Admin Team**
   - Use encrypted communication (e.g., Azure Key Vault, 1Password, secure file sharing)
   - Share the new `.pem` file with App Admin Team
   - Include the ServiceNow ticket number in communication

4. **Wait for Confirmation**
   - Wait for App Admin Team to confirm successful upload to all environments
   - Do not delete the old key until confirmation is received

### Part 3: App Admin Team - Upload New Private Key

1. **Receive New Private Key**
   - Securely receive the new `.pem` file from GitHub Admin Team
   - Save to a temporary secure location

2. **Upload to All Environment Key Vaults**

   Use the upload script for each environment. When rotating the private key, do NOT provide the `-WebhookSecret` parameter - this will upload only the private key and leave the existing webhook secret unchanged:

   ```powershell
   cd tools/infrastructure
   
   # Upload to dev (only private key, preserves existing webhook secret)
   ./upload-github-app-secrets.ps1 -EnvironmentName dev -PemFilePath "C:/temp/new-github-app-key.pem"
   
   # Upload to qa
   ./upload-github-app-secrets.ps1 -EnvironmentName qa -PemFilePath "C:/temp/new-github-app-key.pem"
   
   # Upload to prod-na
   ./upload-github-app-secrets.ps1 -EnvironmentName prod-na -PemFilePath "C:/temp/new-github-app-key.pem"
   
   # Repeat for all other environments...
   ```

   **Note**: The script will:
   - Update the `Github--PrivateKeyPem` secret with the new private key
   - Skip uploading webhook secret (since `-WebhookSecret` parameter is not provided)
   - Display a message "Skipping webhook secret upload (not provided)"

3. **Verify Upload to All Environments**

   Create a checklist and verify each environment:

   - [ ] dev
   - [ ] qa / rel / release
   - [ ] demo / demo-na / demo-emea / demo-apac
   - [ ] staging
   - [ ] prod / prod-na / prod-emea / prod-apac

4. **Test New Key (Optional but Recommended)**
   - Trigger a GitHub workflow in a non-production environment
   - Verify the webhook is received and processed successfully
   - Confirms the new private key is working

5. **Confirm to GitHub Admin Team**
   - Notify GitHub Admin Team that the environment has been updated
   - Confirm it's safe to delete the old private key

6. **Delete Local Copy**
   - Delete the new private key .pem file from your local machine

### Part 4: GitHub Admin Team - Delete Old Private Key

1. **Receive Confirmation from App Admin Team**
   - Verify App Admin Team has confirmed successful upload to all environments
   - Verify testing has been completed (if applicable)

2. **Delete Old Private Key from GitHub**
   - Navigate to GitHub App settings
   - Scroll to "Private keys" section
   - Locate the **old** private key (check the creation date)
   - Click **Delete** next to the old key
   - Confirm deletion

3. **Verify Only New Key Exists**
   - Confirm only the new private key is listed
   - Note the key ID and creation date for records

4. **Update ServiceNow Ticket**
   - Mark the rotation as complete
   - Document the completion date
   - Close the ticket

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
- When rotating, coordinate between GitHub Admin Team and App Admin Team

### Secure Handover Process

- **Between GitHub Admin Team and App Admin Team**:
  - Use encrypted communication channels for sharing private key and webhook secret
  - Consider using secure file sharing services (e.g., Azure Key Vault, 1Password, LastPass shared vaults)
  - Never send credentials via unencrypted email or chat

- **Between App Admin Team and Dev Team**:
  - Only share App ID and Installation ID (these are not sensitive)
  - Confirm Key Vault upload completion before deleting local copies

### App Permissions

- **Grant minimal required permissions**: Only request permissions your app actually needs
- **Limit repository access**: Install app only to `christianacca/web-api-starter` repository
- **Review permission requests**: GitHub will prompt if app requests additional permissions
- **Audit app installations**: Regularly review where the GitHub App is installed

### Team-Specific Responsibilities

- **GitHub Admin Team**: 
  - Maintain access to GitHub App settings for future updates
  - Coordinate webhook secret rotation
  
- **App Admin Team**: 
  - Maintain Key Vault access for credential rotation
  - Document which environments have credentials uploaded
  
- **Dev Team**: 
  - Keep `get-product-github-app-config.ps1` updated
  - Never hardcode credentials in application code

---

## Additional Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/creating-github-apps/creating-a-github-app)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)
