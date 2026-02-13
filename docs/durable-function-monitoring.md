# Durable Function Monitoring

A tool exists that allows for easy monitoring of durable functions. This is useful for tracking the status and steps of a deployment.
The tool can be found [here](https://github.com/microsoft/DurableFunctionsMonitor). The simplest setup is to run it directly from VS Code as follows:

1. Ensure you have the [Azure Account](https://marketplace.visualstudio.com/items?itemName=ms-vscode.azure-account) VS Code extension installed
2. Install the VS Code durable function extension from [here](https://marketplace.visualstudio.com/items?itemName=DurableFunctionsMonitor.durablefunctionsmonitor). Detailed instructions for running appear on that page, but basic steps are also listed below.
3. Once installed make sure you are logged in to azure via the azure cli.
4. Within VS Code go click on the Azure view in the side bar and click on durable functions.
5. Click on the connect icon and enter the address of the storage emulator
    * Address can be obtained from the AzureWebJobsStorage setting found [here](../src/DataServicesGateway.Functions/local.settings.json).
6. The durable function monitor will load up and allow you to track progress.
