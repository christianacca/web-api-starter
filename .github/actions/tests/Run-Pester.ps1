[CmdletBinding()]
param(
    [switch]$SkipInstallModules
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path

. "$repoRoot/tools/infrastructure/ps-functions/Install-ScriptDependency.ps1"

Install-ScriptDependency -ImportOnly:$SkipInstallModules -Module @(
    @{
        Name           = 'Pester'
        MinimumVersion = '5.0.0'
    }
)

Invoke-Pester -Path (Join-Path $PSScriptRoot 'poll-and-approve.Tests.ps1') -Output Detailed
