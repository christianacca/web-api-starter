# Durable Function Monitoring

A tool exists that allows for easy monitoring of durable functions. This is useful for tracking the status and steps of a deployment.
The tool can be found in the [Durable Functions Monitor repository](https://github.com/microsoft/DurableFunctionsMonitor). The simplest setup is to run it directly from VS Code as follows:

1. Ensure you have the [Azure Account](https://marketplace.visualstudio.com/items?itemName=ms-vscode.azure-account) VS Code extension installed
2. Install the [Durable Functions Monitor VS Code extension](https://marketplace.visualstudio.com/items?itemName=DurableFunctionsMonitor.durablefunctionsmonitor). Detailed instructions for running appear on that page, but basic steps are also listed below.
3. Once installed make sure you are logged in to azure via the azure cli.
4. Start Azurite for this repo by running `./tools/azurite/azurite-run.ps1`.
5. Within VS Code, open the Azure view in the side bar and expand the **Durable Functions** section.
6. Click the connect icon and enter the address of the storage emulator.
    * The address can be obtained from the `AzureWebJobsStorage` setting in [src/Template.Functions/local.settings.json](../src/Template.Functions/local.settings.json).
7. In the **Durable Functions** section, expand the connected storage account for the Azurite emulator, which should appear as `devstoreaccount1`.
8. Under that storage account, expand **Task Hubs** and open the task hub for this repo, which is `TestHubName`.
9. Durable Functions Monitor will then load that task hub and allow you to track progress.

## Troubleshooting

### General issues

If Durable Functions Monitor connects to `devstoreaccount1` but shows **No Task Hubs found**, the most likely cause is that the local Functions app has never been started and initialized Durable storage artifacts in the currently running Azurite instance.

For this repo, the local Durable task hub is `TestHubName`.

**Solution**: start the functions app in this project that hosts the durable function orchestrator you want to monitor

### macOS-specific issues

If VS Code on macOS shows an error similar to the following when starting Durable Functions Monitor:

```text
Func: Failed to start the inproc6 model host. An error occurred trying to start process '/usr/local/Cellar/azure-functions-core-tools@4/4.8.0/in-proc6/func' with working directory '.../durablefunctionsmonitor.../backend'. Permission denied
```

then the problem may be that the Azure Functions Core Tools in-proc host binaries have lost their execute permission on disk.

This does not mean that this solution is using the in-process Azure Functions worker model. Durable Functions Monitor uses its own backend host, and that host can still invoke an `in-proc6` executable even when the function app itself runs in isolated-process mode.

Inspect and fix the permissions with:

```bash
ls -l /usr/local/Cellar/azure-functions-core-tools@4/4.8.0/in-proc*/func
chmod 755 /usr/local/Cellar/azure-functions-core-tools@4/4.8.0/in-proc6/func \
    /usr/local/Cellar/azure-functions-core-tools@4/4.8.0/in-proc8/func
```

After updating the permissions, reload VS Code and try Durable Functions Monitor again.

If the execute bit is removed again later, repair the Homebrew installation:

```bash
brew reinstall azure-functions-core-tools@4
```
