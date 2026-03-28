# Skip API version check because Azure.Storage.Queues 12.25.0 uses API version 2026-02-06
# which is not yet supported by Azurite v3.34.0 (max supported: 2025-07-05).
# Microsoft.Azure.Functions.Worker.Extensions.Storage.Queues 5.5.3 pulls in Queues 12.25.0.
# TODO: Remove --skipApiVersionCheck once Azurite updates to support 2026 API versions
azurite --oauth basic --cert $PSScriptRoot/dev-certs/127.0.0.1.pem --key $PSScriptRoot/dev-certs/127.0.0.1-key.pem --location $PSScriptRoot/tmp-storage --skipApiVersionCheck