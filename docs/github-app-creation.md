# GitHub App Creation Guide

## Overview

This guide walks through the process of creating and configuring a GitHub App for use with workflow orchestration systems. The process is divided into responsibilities between the **Admin Team** (who creates the GitHub App) and the **Developer Team** (who provides the necessary configuration requirements).

---

## Part 1: Developer Team Responsibilities

### Provide Webhook Configuration Requirements

Before the GitHub App can be created, the Developer Team must provide the following information to the Admin Team:

#### Required Information

1. **Webhook URL**
   - Format: `https://<your-api-domain>/github/webhooks`
   - Example: `https://api.myapp.com/github/webhooks`
   - This is the endpoint where GitHub will send webhook events

2. **Repository Information**
   - Specific repository name(s) where the app should be installed
   - Organization or account name
   - Branch name (typically `main`)

3. **Azure Key Vault Information**
   - **Key Vault Name**: The name of the Azure Key Vault where credentials will be stored
   - Naming convention: `kv-{product}-{environment}`
   - Example: `kv-myapp-prod`
   - The Admin Team will need access to this Key Vault to store the GitHub App credentials

---

## Part 2: Admin Team Responsibilities

### Prerequisites

Before creating a GitHub App, ensure you have the necessary permissions:

- **App Manager Permission**: You must have the App Manager role in your GitHub organization to create and manage GitHub Apps
  - Organization owners have this permission by default
  - To verify or request this permission, contact your GitHub organization owner
  - Learn more: [GitHub App Manager role](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization#github-app-managers)

### Step 1: Create GitHub App

1. Navigate to **GitHub Settings** → **Developer settings** → **GitHub Apps** → **New GitHub App**
2. Configure basic information:
   - **GitHub App name**: Use the naming convention `{product}-{environment}`
   - Example: `myapp-prod`
   - **Description**: Brief description of the app's purpose
   - **Homepage URL**: Your application URL or GitHub repository URL

![GitHub App Name and Description](assets/creating%20github%20app-%20name%20and%20description.png)

### Step 2: Set Permissions

Configure the repository permissions as provided by the Developer Team:

| Permission | Access Level |
|------------|--------------|
| **Actions** | Read & Write |
| **Metadata** | Read |

![GitHub App Permissions](assets/creating%20github%20app-%20permissions.png)

### Step 3: Generate Webhook Secret

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

**IMPORTANT**: Save this webhook secret - you will need it in the next step and for Azure Key Vault storage.

### Step 4: Configure Webhook

Use the information provided by the Developer Team:

1. **Webhook URL**: Enter the webhook URL provided by the Developer Team
   - Example: `https://api.myapp.com/github/webhooks`

2. **Webhook secret**: Enter the webhook secret you generated in Step 3

3. **Subscribe to events**: Check the following event:
   - ☑ **Workflow run**

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
- Example: `123456`
- Save this ID for the handover to the Dev/Deploy Team

### Step 7: Install GitHub App to Developer Team's Repository

The GitHub App must be installed to the specific repository/repositories provided by the Developer Team for the app to function correctly.

#### Installation Process

1. In the left sidebar of your GitHub App settings, click **Install App**
2. Select the organization or account specified by the Developer Team
   - Verify this matches the organization/account name provided in Part 1
3. Choose repository access:
   - Select **Only select repositories**
   - Select the specific repository/repositories provided by the Developer Team
4. Review the permissions that will be granted:
   - Ensure they match the permissions configured in Step 2
   - The selected repository will have the GitHub App installed with these permissions
5. Click **Install** to complete the installation

#### Post-Installation Verification

After installation, verify the app is correctly installed:

1. Navigate to the repository specified by the Developer Team
2. Go to **Settings** → **Integrations** → **GitHub Apps**
3. Confirm your GitHub App appears in the list of installed apps
4. Verify the app has the correct permissions (Actions: Read & Write, Metadata: Read)

### Step 8: Get Installation ID

After installation, retrieve the Installation ID:

1. After clicking **Install**, check the browser URL
2. Format: `https://github.com/settings/installations/<installation-id>`
3. Note the `<installation-id>` number from the URL
4. Save this ID for the handover to the Dev/Deploy Team

### Step 9: Upload Credentials to Azure Key Vault

Upload the GitHub App credentials to the Azure Key Vault specified by the Developer Team.

**Prerequisites:**
- Ensure you have Azure CLI installed and authenticated
- Verify you have appropriate permissions to the specified Key Vault

**Upload Private Key to Key Vault:**

```powershell
# Set variables (replace with your actual values)
$keyVaultName = "kv-myapp-prod"  # Provided by Developer Team
$pemFilePath = "C:\path\to\downloaded-private-key.pem"  # Path to downloaded .pem file

# Upload to Key Vault as a secret
az keyvault secret set `
  --vault-name $keyVaultName `
  --name "Github--PrivateKeyPem" `
  --file $pemFilePath
```

**Upload Webhook Secret to Key Vault:**

```powershell
# Set variables (replace with your actual values)
$keyVaultName = "kv-myapp-prod"  # Provided by Developer Team
$webhookSecret = "your-webhook-secret-from-step-3"  # From Step 3

# Upload to Key Vault as a secret
az keyvault secret set `
  --vault-name $keyVaultName `
  --name "Github--WebhookSecret" `
  --value $webhookSecret
```

**Verify Upload:**

```powershell
# Verify both secrets were uploaded successfully
az keyvault secret list --vault-name $keyVaultName --query "[?name=='Github--PrivateKeyPem' || name=='Github--WebhookSecret'].{Name:name, Created:attributes.created}" -o table
```

**Security Cleanup:**

After successfully uploading to Key Vault:

1. Delete the downloaded `.pem` file from your local machine
2. Clear the webhook secret from your terminal/clipboard history
3. Verify the secrets are accessible in Key Vault before proceeding

---

## Part 3: Handover to Dev/Deploy Team

### Admin Team: Information Handover

After completing the GitHub App creation, installation, and Azure Key Vault upload, the Admin Team must provide the following information to the Dev/Deploy Team:

#### Required Information to Share

1. **App ID**
   - Location: Displayed at the top of the GitHub App settings page
   - Example: `123456`

2. **Installation ID**
   - Location: Extracted from the browser URL after installing the app
   - Example: `98765432`

#### Handover Checklist

- [ ] App ID documented and shared
- [ ] Installation ID documented and shared
- [ ] Private key .pem file deleted from Admin Team workstation
- [ ] Webhook secret cleared from terminal/clipboard history
- [ ] Dev/Deploy Team has confirmed receipt of all information
- [ ] Verified secrets are accessible in Azure Key Vault

---

## Security Best Practices

### Private Key Management

- **NEVER commit the private key to source control**
- Store the private key in a secure vault (Azure Key Vault, HashiCorp Vault, etc.)
- Restrict access to the private key to only necessary personnel and services
- Use managed identities when accessing the private key from applications

### Webhook Secret

- Generate a strong, cryptographically random webhook secret
- Store the secret securely (Key Vault or equivalent)
- Never commit the secret to source control
- Rotate the secret regularly (recommended: every 90 days)

### App Permissions

- **Grant minimal required permissions**: Only request permissions your app actually needs
- **Limit repository access**: Install app only to specific repositories that need it
- **Review permission requests**: GitHub will prompt if app requests additional permissions
- **Audit app installations**: Regularly review where the GitHub App is installed

---

## Additional Resources

- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [Creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/creating-github-apps/creating-a-github-app)
- [Authenticating with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub App Permissions](https://docs.github.com/en/rest/overview/permissions-required-for-github-apps)
