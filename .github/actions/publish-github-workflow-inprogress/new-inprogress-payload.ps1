[CmdletBinding()]
param(
    [Parameter()]
    [string] $LocalVerificationDirective = "",

    [Parameter(Mandatory)]
    [string] $GitHubEnvironment,

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
$payloadJson = New-GitHubWorkflowInProgressPayloadJson `
    -EnvironmentName $GitHubEnvironment `
    -InstanceId $workflowQueueContext.InstanceId `
    -Repository $Repository `
    -RunAttempt $RunAttempt `
    -RunId $RunId `
    -WorkflowName $WorkflowName

if ($env:GITHUB_OUTPUT) {
    "payload-json=$payloadJson" >> $env:GITHUB_OUTPUT
    if ($workflowQueueContext.ContainsKey('StorageAccountName')) {
        "storage-account=$($workflowQueueContext.StorageAccountName)" >> $env:GITHUB_OUTPUT
    }
    if ($workflowQueueContext.ContainsKey('StorageConnectionString')) {
        "storage-connection-string=$($workflowQueueContext.StorageConnectionString)" >> $env:GITHUB_OUTPUT
    }
}