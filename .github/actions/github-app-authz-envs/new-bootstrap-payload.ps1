[CmdletBinding()]
param(
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

$workflowQueueContext = Resolve-WorkflowQueueContext -WorkflowName $WorkflowName -EnvironmentName $PrimaryEnvironment
$payloadJson = New-GitHubWorkflowInProgressPayloadJson `
    -EnvironmentName $PrimaryEnvironment `
    -InstanceId $workflowQueueContext.InstanceId `
    -Repository $Repository `
    -RunAttempt $RunAttempt `
    -RunId $RunId `
    -WorkflowName $WorkflowName

if ($env:GITHUB_OUTPUT) {
    "payload-json=$payloadJson" >> $env:GITHUB_OUTPUT
    "storage-account=$($workflowQueueContext.StorageAccountName)" >> $env:GITHUB_OUTPUT
}