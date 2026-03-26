Set-StrictMode -Version Latest

$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' '..'))
$script:GetProductEnvironmentNamesScript = Join-Path $script:RepositoryRoot 'tools/infrastructure/get-product-environment-names.ps1'
$script:GetProductConventionsScript = Join-Path $script:RepositoryRoot 'tools/infrastructure/get-product-conventions.ps1'

function Resolve-GitHubAppAuthorizationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $GatedEnvironmentsText,

        [Parameter(Mandatory)]
        [string] $TriggeringActor
    )

    $gatedEnvironments = @(
        $GatedEnvironmentsText -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($gatedEnvironments.Count -eq 0) {
        throw "Input 'gated-environments' must contain at least one environment."
    }

    $primaryEnv = ""
    $pipelineEnvironments = @()
    $environments = & $script:GetProductEnvironmentNamesScript

    foreach ($environmentName in $environments) {
        $conventions = & $script:GetProductConventionsScript -EnvironmentName $environmentName -AsHashtable
        $githubConfig = $conventions.SubProducts.Github
        $expectedAppSlug = $githubConfig.AppSlug

        if ($expectedAppSlug -and ($TriggeringActor -eq "$expectedAppSlug[bot]")) {
            $primaryEnv = $githubConfig.AuthorizedEnvironment.Primary
            $pipelineEnvironments = @($githubConfig.AuthorizedEnvironment.Pipeline)
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($primaryEnv)) {
        throw "Unable to resolve dispatching actor '$TriggeringActor' to a supported GitHub App."
    }

    $authorizedTargetEnvs = @(
        $gatedEnvironments |
            Where-Object { $_ -in $pipelineEnvironments }
    )

    if ($authorizedTargetEnvs.Count -eq 0) {
        throw "Dispatching actor '$TriggeringActor' is not authorized for any workflow-gated environment. Gated environments: $($gatedEnvironments -join ', '). Pipeline environments: $($pipelineEnvironments -join ', ')."
    }

    return @{
        Primary = $primaryEnv
        Pipeline = @($pipelineEnvironments)
        AuthorizedTargetEnvs = @($authorizedTargetEnvs)
    }
}

function Resolve-WorkflowQueueContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $WorkflowName,

        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter()]
        [string] $LocalVerificationDirectiveJson = ""
    )

    if ([string]::IsNullOrWhiteSpace($WorkflowName)) {
        throw "WorkflowName is required."
    }

    $separatorIndex = $WorkflowName.IndexOf('-')
    if ($separatorIndex -le 0 -or $separatorIndex -ge ($WorkflowName.Length - 1)) {
        throw "Workflow name '$WorkflowName' must match '<dispatcher>-<instanceId>'."
    }

    $workflowDispatcherName = $WorkflowName.Substring(0, $separatorIndex)
    $instanceId = $WorkflowName.Substring($separatorIndex + 1)

    if (-not [string]::IsNullOrWhiteSpace($LocalVerificationDirectiveJson)) {
        $localVerificationDirective = $LocalVerificationDirectiveJson | ConvertFrom-Json -AsHashtable
        $storageConnectionString = [string] $localVerificationDirective.storageConnectionString

        if ([string]::IsNullOrWhiteSpace($storageConnectionString)) {
            throw "Local verification directive must include 'storageConnectionString'."
        }

        return @{
            WorkflowDispatcherName = $workflowDispatcherName
            InstanceId = $instanceId
            StorageConnectionString = $storageConnectionString
        }
    }

    $conventions = & $script:GetProductConventionsScript -EnvironmentName $EnvironmentName -AsHashtable
    $subProduct = $conventions.SubProducts[$workflowDispatcherName]
    if ($null -eq $subProduct) {
        throw "Unable to resolve workflow dispatcher '$workflowDispatcherName' in conventions for environment '$EnvironmentName'."
    }

    $storageAccountName = $subProduct.StorageAccountName
    if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
        throw "Unable to resolve the storage account for workflow dispatcher '$workflowDispatcherName' in environment '$EnvironmentName'."
    }

    return @{
        WorkflowDispatcherName = $workflowDispatcherName
        InstanceId = $instanceId
        StorageAccountName = $storageAccountName
    }
}

function New-GitHubWorkflowInProgressPayloadJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $InstanceId,

        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter(Mandatory)]
        [int] $RunAttempt,

        [Parameter(Mandatory)]
        [long] $RunId,

        [Parameter(Mandatory)]
        [string] $WorkflowName
    )

    return (@{
        environment = $EnvironmentName
        instanceId = $InstanceId
        repository = $Repository
        runAttempt = $RunAttempt
        runId = $RunId
        workflowName = $WorkflowName
    } | ConvertTo-Json -Compress)
}

function Get-GitHubWorkflowConclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $NeedsJson
    )

    $needs = $NeedsJson | ConvertFrom-Json -AsHashtable
    $results = @(
        $needs.GetEnumerator() |
            Where-Object { $_.Key -ne 'github-app-authz' } |
            ForEach-Object { $_.Value.result }
    )

    if ($results -contains 'failure') {
        return 'failure'
    }

    if ($results -contains 'cancelled') {
        return 'cancelled'
    }

    return 'success'
}

function New-GitHubWorkflowCompletedPayloadJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Conclusion,

        [Parameter(Mandatory)]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $InstanceId,

        [Parameter(Mandatory)]
        [string] $Repository,

        [Parameter(Mandatory)]
        [int] $RunAttempt,

        [Parameter(Mandatory)]
        [long] $RunId,

        [Parameter(Mandatory)]
        [string] $WorkflowName
    )

    return (@{
        conclusion = $Conclusion
        environment = $EnvironmentName
        instanceId = $InstanceId
        repository = $Repository
        runAttempt = $RunAttempt
        runId = $RunId
        workflowName = $WorkflowName
    } | ConvertTo-Json -Compress)
}

Export-ModuleMember -Function Resolve-GitHubAppAuthorizationContext, Resolve-WorkflowQueueContext, New-GitHubWorkflowInProgressPayloadJson, Get-GitHubWorkflowConclusion, New-GitHubWorkflowCompletedPayloadJson