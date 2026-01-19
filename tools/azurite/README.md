# Azurite storage emulator

See: <https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite>

> **IMPORTANT**: Pick the instructions below based on your preference for IDE or command-line

## Requirements

**Minimum Azurite Version**: v3.34.0 or later

This version is required to support Azure Storage API version 2025-07-05 used by .NET 10 Azure Storage SDKs.

## Install and run (for command-line)

### Install

1. Install `Azurite`: `npm install -g azurite`
2. Install `mkcert`
   * mac: `brew install mkcert`
   * windows: `choco install mkcert` (you will need have [chocolatey](https://chocolatey.org/install) already installed)
3. Generate a https certificate for Azurite (using powershell prompt): `./tools/azurite/dev-certs/generate-azurite-dev-cert.ps1`
4. (Optional) Install and use Azure Storage Explorer (see section below)

### Upgrade Azurite

To upgrade Azurite to the minimum required version or later:

```bash
npm install -g azurite@^3.34.0
```

To check your current Azurite version:

```bash
azurite --version
```

### Run Azurite

```pwsh
# use powershell core prompt
./tools/azurite/azurite-run.ps1
```

> [!NOTE] if you have only just installed Azurite then you might need to re-open the powershell command prompt before the term `azurite` is recognised.

> [!NOTE] if after re-opening the powershell prompt the term `azurite` is still not recognised then it might be that the global folder into which
npm installs global modules is not included in your PATH environment variable. For example, on a windows VM created in Azure, I had to add to my PATH
environment variable (for me C:\Users\ccrowhurst\AppData\Roaming\npm)


## Install and run (for Visual Studio)

Currently there is no (obvious) way to configure VS2022 to run its own managed version of Azurite to use https. The workaround is to run Azurite
from command-line first BEFORE starting the function app in VS2022. See instructions above


## Install and run (for Visual Studio Code)

Complete the prerequisites in the command-line section above, then:

Azurite starts automatically as a pre-launch task when you:
- Press **F5** and select **"Debug Functions (Template.Functions)"** from the debug dropdown
- Or use the debug panel and launch the Functions configuration

The Azurite process runs in a dedicated terminal panel and will remain running until you stop it manually or close VS Code.

> [!TIP]
> You can also manually start Azurite by running the task "start azurite" from the Command Palette (Cmd+Shift+P > Tasks: Run Task > start azurite)


## Install and use Azure Storage Explorer

[Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/) is a tool that can be used to explore and manage the content of Azure storage account emulated by Azurite.

1. Install Azure Storage Explorer:
   * mac: `brew install --cask microsoft-azure-storage-explorer`
   * windows: `choco install microsoftazurestorageexplorer` (you will need have [chocolatey](https://chocolatey.org/install) already installed)
2. Import root certificate authority (CA) installed by mkcert:
   * see this guide: <https://blog.jongallant.com/2020/04/local-azure-storage-development-with-azurite-azuresdks-storage-explorer/#Azure-Storage-Explorer-Setup>
3. Connect Azure Storage explorer to Azurite
   1. make sure to be running Azurite as explained in one of the guides above
   2. follow the instructions 'Add Azurite HTTPS Endpoint' in the guide: <https://blog.jongallant.com/2020/04/local-azure-storage-development-with-azurite-azuresdks-storage-explorer/#Azure-Storage-Explorer-Setup>

