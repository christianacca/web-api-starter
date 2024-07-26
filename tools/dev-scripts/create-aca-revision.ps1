<#
    .SYNOPSIS
    Create a new revision for an existing Azure container app
    
    .DESCRIPTION
    Create a new revision for an existing Azure container app.
    IMPORTANT:
    this script is duplicated here: .github/actions/container-apps-create-revision/create-aca-revision.ps1
    Any changes to the script below is likely going to be needed in the above action script as well.
    
    .PARAMETER Name
    The name of the Container App to create a revision for
    
    .PARAMETER Image
    The full image name to deploy, including the registry and tag
    
    .PARAMETER ResourceGroup
    The name of the resource group that contains the container app
    
    .PARAMETER EnvVarsObject
    A hashtable specifying the environment variables to include in the deployment of the new revision. The keys of 
    the hashtable are the environment variable names and the values are the environment variable values
    
    .PARAMETER EnvVarsSelector
    A list of one or more strings that identity the environment variables to include in the deployment of the new revision.
    Each string, a comma separated list of environment variables. Use the format Env:VariableName to include an 
    environment variable. Use the wildcard character (*) to match environment variables that start with a 
    specific string. For example, Env:Api_* will match all environment variables that start with Api_
    
    .PARAMETER EnvVarKeyTransform
    A script block to apply to the environment variable keys. Use the format { $_-replace "search", "replace" } to 
    replace all instances of search with replace in the environment variable keys. For example, { $_ -replace "_", "__" } 
    will replace all underscores with double underscores in the environment variable keys
    
    .PARAMETER EnvVarKeyTransformString
    A string transformation to apply to the environment variable keys. Use the format "search=>replace" to replace all 
    instances of search with replace in the environment variable keys. For example, _=>__ will replace all underscores
    with double underscores in the environment variable keys
    
    .PARAMETER HealthRequestPath
    The path to the request path to use to test the new revision
    
    .PARAMETER HealthRequestTimeoutSec
    The timeout in seconds to use when testing the new revision
    
    .PARAMETER TestRevision
    A switch to indicate that the script should wait for the new revision to successfully respond to a GET request to
    the configured health endpoint

    .EXAMPLE
    $apiParams = @{
        Name            =   'my-container-app'
        ResourceGroup   =   'my-resource-group'
        Image           =   'clcsoftwaredevops.azurecr.io/web-api-starter/api:latest'
        EnvVars         =   @{
            'Api__Database__UserID' = 'xxx'
            'Api__TokenProvider__Authority' = 'xxx'
            'ApplicationInsights__AutoCollectActionArgs' = $true
            'EnvironmentInfo__EnvId' = 'local'
        }
        TestRevision    =   $true
    }
    create-aca-revision.ps1 @apiParams -InfA Continue -EA Stop
    
    Description
      -----------
    Deploys the docker image and env variables supplied as a hashtable to the Azure container app specified by the name and resource group.
    The TestRevision switch is used to wait for the new revision to successfully respond to a GET request to the default health endpoint.

    .EXAMPLE
    $apiParams = @{
        Name            =   'my-container-app'
        ResourceGroup   =   'my-resource-group'
        Image           =   'clcsoftwaredevops.azurecr.io/web-api-starter/api:latest'
        EnvVarsSelector =   'Env:Api__*', 'Env:EnvironmentInfo__*'
    }
    create-aca-revision.ps1 @apiParams -InfA Continue -EA Stop
    
    Description
      -----------
    Deploys the docker image and environment variables whose key's match the selector strings to the Azure container 
    app specified by the name and resource group.

    .EXAMPLE
    $apiParams = @{
        Name                        =   'my-container-app'
        ResourceGroup               =   'my-resource-group'
        Image                       =   'clcsoftwaredevops.azurecr.io/web-api-starter/api:latest'
        EnvVarsSelector             =   'Env:Api_Database_UserId,Env:Api_TokenProvider_*', 'Env:Db_*'
        EnvVarKeyTransformString    =   '_=>__'
    }
    create-aca-revision.ps1 @apiParams -InfA Continue -EA Stop
    
    Description
      -----------
    Transforms the environment variable keys matching the selector strings by replacing a single underscore with a
    douple underscore, and deploys the docker image and transformed env variables to the Azure container app specified
    by the name and resource group.   

    .EXAMPLE
    $apiParams = @{
        Name                        =   'my-container-app'
        ResourceGroup               =   'my-resource-group'
        Image                       =   'clcsoftwaredevops.azurecr.io/web-api-starter/api:latest'
        EnvVars                     =   @{
            'ApplicationInsights_AutoCollectActionArgs' = $true
            'EnvironmentInfo_EnvId' = 'local'
        }
        EnvVarsSelector             =   'Env:Api_Database_UserId,Env:Api_*', 'Env:Db_*'
        EnvVarKeyTransformString    =   '_=>__'
    }
    create-aca-revision.ps1 @apiParams -InfA Continue -EA Stop
    
    Description
      -----------
    Transforms the environment variable keys matching the selector strings along with explicit key value pairs supplied,
    by replacing a single underscore with a douple underscore, and deploys the docker image and transformed env variables
    to the Azure container app specified by the name and resource group.   
#>
    
    [CmdletBinding()]
    param(    
        [Parameter(Mandatory)]
        [Alias('ContainerAppName')]
        [string] $Name,

        [Parameter(Mandatory)]
        [Alias('ImageToDeploy')]
        [string] $Image,
    
        [Parameter(Mandatory)]
        [string] $ResourceGroup,
        
        [Hashtable] $EnvVarsObject = @{},
        
        [string[]] $EnvVarsSelector = @(),
    
        [ScriptBlock] $EnvVarKeyTransform,

        [string] $EnvVarKeyTransformString,

        [string] $HealthRequestPath = '/health',        
        [string] $HealthRequestTimeoutSec = 90,        
        [switch] $TestRevision
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/../infrastructure/ps-functions/hashtable-functions.ps1"
        . "$PSScriptRoot/../infrastructure/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/../infrastructure/ps-functions/Invoke-ExeExpression.ps1"
    }
    process {
        try {
            if ($TestRevision -and -not($HealthRequestPath)) {
                throw 'HealthEndpoint is required when TestRevision switch is used'
            }
            if ($EnvVarsSelector) {
                $selectedEnvVars = Get-Item -Path ($EnvVarsSelector -split ',') -EA SilentlyContinue |
                    ForEach-Object -Begin { $tmp = @{} } -Process { $tmp[$_.name] = $_.value } -End { $tmp }
                $EnvVarsObject = $EnvVarsObject + $selectedEnvVars
            }
            
            if ($EnvVarKeyTransformString) {
                $operands = $EnvVarKeyTransformString -split '=>' | ForEach-Object { $_.Trim() }
                $EnvVarKeyTransform = { $_ -replace $operands[0], $operands[1]}
            }
            
            if ($EnvVarKeyTransform) {
                $EnvVarsObject = $EnvVarsObject.GetEnumerator() | ForEach-Object -Begin { $tmp = @{} } -Process {
                    $key = @($_.key) | ForEach-Object $EnvVarKeyTransform
                    $tmp[$key] = $_.value
                } -End { $tmp }
            }

            $app = Invoke-Exe { az containerapp show -n $Name -g $ResourceGroup } | ConvertFrom-Json
            $existingEnvVars = $app.properties.template.containers.env |
                ForEach-Object -Begin { $tmp = @{} } -Process { $tmp[$_.name] = $_.value } -End { $tmp }
            
            $metadataKeyName = '__DeployMetadata__AppVarKeys'
            $previousEnvVarsKeys = $existingEnvVars[$metadataKeyName] -split ','
            $requiredEnvVarKeys = $EnvVarsObject.Keys | Sort-Object
            $obsoleteEnvKeys = ($previousEnvVarsKeys | Where-Object { $_ -notin $requiredEnvVarKeys }) +
                ($requiredEnvVarKeys ? @() : @($metadataKeyName))
            
            $metadataEnvVars = $requiredEnvVarKeys ? @{ $metadataKeyName = ($requiredEnvVarKeys -join ',') } : @{}

            $desiredEnvVars = $EnvVarsObject,$metadataEnvVars,$existingEnvVars | Join-Hashtable |
                Select-Hashtable { $_ -notin $obsoleteEnvKeys }
            
            $envVarsString = $desiredEnvVars | ConvertTo-StringData -SortKeys | Join-String -Separator ' '
            $replaceEnvVarsString = if ($envVarsString) { '--replace-env-vars ' + $envVarsString } else { '' }
            
            $copyRevision = "az containerapp revision copy -n $Name -g $ResourceGroup --image $Image $replaceEnvVarsString"
            $result = Invoke-ExeExpression $copyRevision | ConvertFrom-Json | Select-Object -Exp properties
            
            if ($TestRevision) {
                # Wait for the new revision to be ready
                $HealthRequestPath = $HealthRequestPath.Trim('/')
                $revisionUrl = "https://$($result.latestRevisionFqdn)/$HealthRequestPath"
                Write-Information "Waiting for the new revision to successfully respond to GET request to $revisionUrl"
                Invoke-WebRequest -Uri $revisionUrl -TimeoutSec $HealthRequestTimeoutSec -MaximumRetryCount 2 -Method GET -EA Stop | Out-Null
            }
            $result
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
