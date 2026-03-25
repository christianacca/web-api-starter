[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $GatedEnvironments,

    [Parameter(Mandatory)]
    [string] $TriggeringActor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' '_shared' 'GitHubWorkflowQueueSupport.psm1') -Force

$authorizationContext = Resolve-GitHubAppAuthorizationContext -GatedEnvironmentsText $GatedEnvironments -TriggeringActor $TriggeringActor

if ($env:GITHUB_OUTPUT) {
    "primary=$($authorizationContext.Primary)" >> $env:GITHUB_OUTPUT
    "pipeline=$(@($authorizationContext.Pipeline) | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT
    "authorized-target-envs=$(@($authorizationContext.AuthorizedTargetEnvs) | ConvertTo-Json -Compress)" >> $env:GITHUB_OUTPUT
}