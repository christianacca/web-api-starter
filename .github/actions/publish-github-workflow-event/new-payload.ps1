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
    [string] $WorkflowName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' '_shared' 'GitHubWorkflowQueueSupport.psm1') -Force

$workflowQueueContext = Resolve-WorkflowQueueContext -WorkflowName $WorkflowName -EnvironmentName $GitHubEnvironment -LocalVerificationDirectiveJson $LocalVerificationDirective
$payload = [ordered]@{
    environment = $GitHubEnvironment
    instanceId = $workflowQueueContext.InstanceId
    repository = $Repository
    runAttempt = $RunAttempt
    runId = $RunId
    workflowName = $WorkflowName
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

$payloadJson = $payload | ConvertTo-Json -Compress

if ($env:GITHUB_OUTPUT) {
    if ($conclusion) {
        "conclusion=$conclusion" >> $env:GITHUB_OUTPUT
    }
    "payload-json=$payloadJson" >> $env:GITHUB_OUTPUT
    if ($workflowQueueContext.ContainsKey('StorageAccountName')) {
        "storage-account=$($workflowQueueContext.StorageAccountName)" >> $env:GITHUB_OUTPUT
    }
    if ($workflowQueueContext.ContainsKey('StorageConnectionString')) {
        "storage-connection-string=$($workflowQueueContext.StorageConnectionString)" >> $env:GITHUB_OUTPUT
    }
}