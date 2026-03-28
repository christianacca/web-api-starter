[CmdletBinding()]
param(
    [Parameter()]
    [string] $LocalVerificationDirective = "",

    [Parameter(Mandatory)]
    [string] $GitHubEnvironment,

    [Parameter(Mandatory)]
    [string] $MessageType,

    [Parameter()]
    [string] $NeedsJson = "",

    [Parameter(Mandatory)]
    [string] $Repository,

    [Parameter(Mandatory)]
    [int] $RunAttempt,

    [Parameter(Mandatory)]
    [long] $RunId,

    [Parameter(Mandatory)]
    [string] $WorkflowName,

    [Parameter(Mandatory)]
    [string] $QueueName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' '_shared' 'GitHubWorkflowQueueSupport.psm1') -Force

$workflowQueueContext = Resolve-WorkflowQueueContext -WorkflowName $WorkflowName -EnvironmentName $GitHubEnvironment -LocalVerificationDirectiveJson $LocalVerificationDirective
$conclusion = $null
$payload = [ordered]@{
    environment = $GitHubEnvironment
    instanceId = $workflowQueueContext.InstanceId
    repository = $Repository
    runAttempt = $RunAttempt
    runId = $RunId
    workflowName = $WorkflowName
}

if ([string]::IsNullOrWhiteSpace($MessageType)) {
    throw "MessageType is required."
}

switch ($MessageType) {
    'GithubWorkflowInProgress' {
        break
    }
    'GithubWorkflowCompleted' {
        if ([string]::IsNullOrWhiteSpace($NeedsJson)) {
            throw "NeedsJson is required when publishing '$MessageType'."
        }

        $conclusion = Get-GitHubWorkflowConclusion -NeedsJson $NeedsJson
        $payload.conclusion = $conclusion
        break
    }
    default {
        throw "Unsupported MessageType '$MessageType'."
    }
}

if ([string]::IsNullOrWhiteSpace($QueueName)) {
    throw "QueueName is required."
}

$payloadJson = $payload | ConvertTo-Json -Compress
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

if ($workflowQueueContext.ContainsKey('StorageConnectionString')) {
    $storageConnectionString = [string] $workflowQueueContext.StorageConnectionString
    $publishTarget = "local verification queue '$QueueName'"
    $publishResponse = az storage message put `
        --connection-string $storageConnectionString `
        --queue-name $QueueName `
        --content $encodedMessageBody `
        --only-show-errors 2>&1
}
elseif ($workflowQueueContext.ContainsKey('StorageAccountName')) {
    $storageAccountName = [string] $workflowQueueContext.StorageAccountName
    $publishTarget = "$storageAccountName/$QueueName"
    $publishResponse = az storage message put `
        --account-name $storageAccountName `
        --queue-name $QueueName `
        --auth-mode login `
        --content $encodedMessageBody `
        --only-show-errors 2>&1
}
else {
    throw "Unable to resolve either StorageAccountName or StorageConnectionString for queue publishing."
}

if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish queue message '$MessageType' to '$publishTarget'. $publishResponse"
}

Write-Host "Published queue message '$MessageType' to '$publishTarget' with MessageBody id '$messageId'."

if ($env:GITHUB_OUTPUT) {
    if ($conclusion) {
        "conclusion=$conclusion" >> $env:GITHUB_OUTPUT
    }
    "published=true" >> $env:GITHUB_OUTPUT
    "message-id=$messageId" >> $env:GITHUB_OUTPUT
}