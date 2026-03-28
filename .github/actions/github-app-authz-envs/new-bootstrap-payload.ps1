[CmdletBinding()]
param(
    [Parameter()]
    [string] $LocalVerificationDirective = "",

    [Parameter(Mandatory)]
    [string] $PrimaryEnvironment,

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

$workflowQueueContext = Resolve-WorkflowQueueContext -WorkflowName $WorkflowName -EnvironmentName $PrimaryEnvironment -LocalVerificationDirectiveJson $LocalVerificationDirective
$payloadJson = [ordered]@{
    environment = $PrimaryEnvironment
    instanceId = $workflowQueueContext.InstanceId
    repository = $Repository
    runAttempt = $RunAttempt
    runId = $RunId
    workflowName = $WorkflowName
} | ConvertTo-Json -Compress

if ($env:GITHUB_OUTPUT) {
    "payload-json=$payloadJson" >> $env:GITHUB_OUTPUT
    if ($workflowQueueContext.ContainsKey('StorageAccountName')) {
        "storage-account=$($workflowQueueContext.StorageAccountName)" >> $env:GITHUB_OUTPUT
    }
    if ($workflowQueueContext.ContainsKey('StorageConnectionString')) {
        "storage-connection-string=$($workflowQueueContext.StorageConnectionString)" >> $env:GITHUB_OUTPUT
    }
}