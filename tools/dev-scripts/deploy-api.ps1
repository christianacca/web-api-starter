<#
    .SYNOPSIS
    Deploys API to Azure container apps

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
    }
    ./tools/dev-scripts/deploy-api.ps1 @apiParams -InfA Continue -EA Stop
    
    Description
      -----------
    Deploys the docker image and env variables supplied as a hashtable to the Azure container app specified by the name and resource group.

    .EXAMPLE
    $apiParams = @{
        Name            =   'my-container-app'
        ResourceGroup   =   'my-resource-group'
        Image           =   'clcsoftwaredevops.azurecr.io/web-api-starter/api:latest'
        EnvVarsSelector =   'Env:Api__*', 'Env:EnvironmentInfo__*'
    }
    ./tools/dev-scripts/deploy-api.ps1 @apiParams -InfA Continue -EA Stop
    
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
    ./tools/dev-scripts/deploy-api.ps1 @apiParams -InfA Continue -EA Stop
    
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
    ./tools/dev-scripts/deploy-api.ps1 @apiParams -InfA Continue -EA Stop
    
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

        [string] $EnvVarKeyTransformString
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/../infrastructure/ps-functions/ConvertTo-StringData.ps1"
        . "$PSScriptRoot/../infrastructure/ps-functions/Invoke-Exe.ps1"
        . "$PSScriptRoot/../infrastructure/ps-functions/Invoke-ExeExpression.ps1"

        function Union-Hashtable {
            param(
                [Parameter(Mandatory, ValueFromPipeline)]
                [Hashtable[]] $InputObject
            )
            begin {
                $result = @{}
            }
            process {
                foreach ($hashtable in $InputObject) {
                    foreach ($key in $hashtable.Keys) {
                        if (-not $result.ContainsKey($key)) {
                            $result[$key] = $hashtable[$key]
                        }
                    }
                }
            }
            end {
                $result
            }
        }
        function Select-Hashtable {
            param(
                [Parameter(Mandatory, ValueFromPipeline)]
                [Hashtable] $InputObject,
                
                [Parameter(Mandatory, Position = 0)]
                [ScriptBlock] $Selector
            )
            $InputObject.Keys | Where-Object $Selector |
                ForEach-Object -Begin { $tmp = @{} } -Process { $tmp[$_] = $InputObject[$_] } -End { $tmp }
        }
    }
    process {
        try {
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

            $desiredEnvVars = $EnvVarsObject,$metadataEnvVars,$existingEnvVars | Union-Hashtable |
                Select-Hashtable { $_ -notin $obsoleteEnvKeys }
            
            $envVarsString = $desiredEnvVars | ConvertTo-StringData -SortKeys | Join-String -Separator ' '
            $replaceEnvVarsString = if ($envVarsString) { '--replace-env-vars ' + $envVarsString } else { '' }
            
            $copyRevision = "az containerapp revision copy -n $Name -g $ResourceGroup --image $Image $replaceEnvVarsString"
            $copyRevision
#            Invoke-ExeExpression $copyRevision | ConvertFrom-Json | Select-Object -Exp properties
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
