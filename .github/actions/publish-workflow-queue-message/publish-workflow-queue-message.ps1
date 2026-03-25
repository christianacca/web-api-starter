[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $MessageType,
    [Parameter(Mandatory)]
    [string] $PayloadJson,
    [Parameter(Mandatory)]
    [string] $StorageAccountName,
    [Parameter(Mandatory)]
    [string] $QueueName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($MessageType)) {
    throw "MessageType is required."
}

if ([string]::IsNullOrWhiteSpace($PayloadJson)) {
    throw "PayloadJson is required."
}

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    throw "StorageAccountName is required."
}

if ([string]::IsNullOrWhiteSpace($QueueName)) {
    throw "QueueName is required."
}

$null = $PayloadJson | ConvertFrom-Json -AsHashtable

$messageId = [guid]::NewGuid().ToString()
$messageBody = @{
    id = $messageId
    data = $PayloadJson
    metadata = @{
        messageType = $MessageType
    }
} | ConvertTo-Json -Compress -Depth 10

$publishResponse = az storage message put `
    --account-name $StorageAccountName `
    --queue-name $QueueName `
    --auth-mode login `
    --content $messageBody `
    --only-show-errors 2>&1

if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish queue message '$MessageType' to '$StorageAccountName/$QueueName'. $publishResponse"
}

Write-Host "Published queue message '$MessageType' to '$StorageAccountName/$QueueName' with MessageBody id '$messageId'."

if ($env:GITHUB_OUTPUT) {
    "published=true" >> $env:GITHUB_OUTPUT
    "message-id=$messageId" >> $env:GITHUB_OUTPUT
}