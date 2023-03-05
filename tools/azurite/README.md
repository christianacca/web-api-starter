# Azurite storage emulator

See: <https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite>

> **IMPORTANT**: Pick the instructions below based on your preference for IDE or command-line

## Install and run (for command-line)

### Install

1. Install `Azurite`: `npm install -g azurite`
2. Install `mkcert`
   * mac: `brew install mkcert`
   * windows: `choco install mkcert` (you will need have [chocolatey](https://chocolatey.org/install) already installed)
3. Generate a https certificate for Azurite (using powershell prompt): `./tools/azurite/dev-certs/generate-azurite-dev-cert.ps1`
4. (Optional) Install and use Azure Storage Explorer (see section below)

### Run Azurite

1. Run `Azurite` listening over https (using powershell prompt): `./tools/azurite/azurite-run.ps1`

Note: if you have only just installed Azurite then you might need to re-open the powershell command prompt before the term `azurite` is recognised.
Note: if after re-opening the powershell prompt the term `azurite` is still not recognised then it might be that the global folder into which
npm installs global modules is not included in your PATH environment variable. For example, on a windows VM created in Azure, I had to add to my PATH
environment variable (for me C:\Users\ccrowhurst\AppData\Roaming\npm)


## Install and run (for Visual Studio)

Currently there is no (obvious) way to configure VS2022 to run its own managed version of Azurite to use https. The workaround is to run Azurite
from command-line first BEFORE starting the function app in VS2022. See instructions above


## Install and run (for Visual Studio Code)

**TODO**


## Install and use Azure Storage Explorer

[Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/) is a tool that can be used to explore and manage the content of Azure storage account emulated by Azurite.

> Note: version 1.25.1 of Azure Storage Explorer has a bug that prevents it from viewing blobs. This bug should be resolved in 1.26

1. Install Azure Storage Explorer:
   * mac: `brew install --cask microsoft-azure-storage-explorer`
   * windows: `choco install microsoftazurestorageexplorer` (you will need have [chocolatey](https://chocolatey.org/install) already installed)
2. Import root certificate authority (CA) installed by mkcert:
   * see this guide: <https://blog.jongallant.com/2020/04/local-azure-storage-development-with-azurite-azuresdks-storage-explorer/#Azure-Storage-Explorer-Setup>
3. Connect Azure Storage explorer to Azurite
   1. make sure to be running Azurite as explained in one of the guides above
   2. follow the instructions 'Add Azurite HTTPS Endpoint' in the guide: <https://blog.jongallant.com/2020/04/local-azure-storage-development-with-azurite-azuresdks-storage-explorer/#Azure-Storage-Explorer-Setup>

