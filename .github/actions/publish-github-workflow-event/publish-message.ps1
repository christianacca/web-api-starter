[CmdletBinding()]
param(
    [Parameter()]
    [string] $LocalVerificationDirective = "",

    [Parameter(Mandatory)]
    [string] $GitHubEnvironment,

    [Parameter(Mandatory)]
    [string] $GitHubAppInstallationId,

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

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
. (Join-Path $repositoryRoot 'tools/infrastructure/ps-functions/Get-Guid.ps1')

Import-Module (Join-Path $PSScriptRoot '..' '_shared' 'GitHubWorkflowQueueSupport.psm1') -Force

function Publish-QueueMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $WorkflowQueueContext,

        [Parameter(Mandatory)]
        [string] $QueueName,

        [Parameter(Mandatory)]
        [string] $EncodedMessageBody
    )

    if ($WorkflowQueueContext.ContainsKey('StorageConnectionString')) {
        $storageConnectionString = [string] $WorkflowQueueContext.StorageConnectionString
        $publishTarget = "local verification queue '$QueueName'"
        $publishResponse = az storage message put `
            --connection-string $storageConnectionString `
            --queue-name $QueueName `
            --content $EncodedMessageBody `
            --only-show-errors 2>&1

        return @{
            ExitCode = $LASTEXITCODE
            PublishTarget = $publishTarget
            PublishResponse = $publishResponse
        }
    }

    if ($WorkflowQueueContext.ContainsKey('StorageAccountName')) {
        $storageAccountName = [string] $WorkflowQueueContext.StorageAccountName
        $publishTarget = "$storageAccountName/$QueueName"
        $publishResponse = az storage message put `
            --account-name $storageAccountName `
            --queue-name $QueueName `
            --auth-mode login `
            --content $EncodedMessageBody `
            --only-show-errors 2>&1

        return @{
            ExitCode = $LASTEXITCODE
            PublishTarget = $publishTarget
            PublishResponse = $publishResponse
        }
    }

    throw "Unable to resolve either StorageAccountName or StorageConnectionString for queue publishing."
}

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

if ([string]::IsNullOrWhiteSpace($GitHubAppInstallationId)) {
    throw "GitHubAppInstallationId is required."
}

$payloadJson = $payload | ConvertTo-Json -Compress
$null = $payloadJson | ConvertFrom-Json -AsHashtable

$userId = (Get-Guid -Value $GitHubAppInstallationId).ToString()
$userContext = @(
    @{
        type = 'iss'
        value = 'https://github.com/'
    }
    @{
        type = 'cid'
        value = $GitHubAppInstallationId
    }
    @{
        type = 'sub'
        value = $GitHubAppInstallationId
    }
    @{
        type = 'UserId'
        value = $userId
    }
)

$messageId = [guid]::NewGuid().ToString()
$messageBody = @{
    id = $messageId
    data = $PayloadJson
    metadata = @{
        messageType = $MessageType
        userContext = $userContext
    }
} | ConvertTo-Json -Compress -Depth 10
$encodedMessageBody = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($messageBody))

$publishResult = Publish-QueueMessage -WorkflowQueueContext $workflowQueueContext -QueueName $QueueName -EncodedMessageBody $encodedMessageBody

if ($publishResult.ExitCode -ne 0) {
    throw "Failed to publish queue message '$MessageType' to '$($publishResult.PublishTarget)'. $($publishResult.PublishResponse)"
}

Write-Host "Published queue message '$MessageType' to '$($publishResult.PublishTarget)' with MessageBody id '$messageId'."

if ($env:GITHUB_OUTPUT) {
    if ($conclusion) {
        "conclusion=$conclusion" >> $env:GITHUB_OUTPUT
    }
    "published=true" >> $env:GITHUB_OUTPUT
    "message-id=$messageId" >> $env:GITHUB_OUTPUT
}