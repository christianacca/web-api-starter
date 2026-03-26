[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $MessageType,
    [Parameter(Mandatory)]
    [string] $PayloadJson,
    [Parameter()]
    [string] $StorageAccountName = "",
    [Parameter()]
    [string] $StorageConnectionString = "",
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

if ([string]::IsNullOrWhiteSpace($StorageAccountName) -and [string]::IsNullOrWhiteSpace($StorageConnectionString)) {
    throw "Either StorageAccountName or StorageConnectionString is required."
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
$encodedMessageBody = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($messageBody))

if ([string]::IsNullOrWhiteSpace($StorageConnectionString)) {
    $publishTarget = "$StorageAccountName/$QueueName"
    $publishResponse = az storage message put `
        --account-name $StorageAccountName `
        --queue-name $QueueName `
        --auth-mode login `
        --content $encodedMessageBody `
        --only-show-errors 2>&1
}
else {
    $publishTarget = "local verification queue '$QueueName'"
    $publishResponse = az storage message put `
        --connection-string $StorageConnectionString `
        --queue-name $QueueName `
        --content $encodedMessageBody `
        --only-show-errors 2>&1
}

if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish queue message '$MessageType' to '$publishTarget'. $publishResponse"
}

Write-Host "Published queue message '$MessageType' to '$publishTarget' with MessageBody id '$messageId'."

if ($env:GITHUB_OUTPUT) {
    "published=true" >> $env:GITHUB_OUTPUT
    "message-id=$messageId" >> $env:GITHUB_OUTPUT
}