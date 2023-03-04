    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,
        
        [switch] $AsHashtable
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Get-ResourceConvention.ps1"
    }
    process {
        try {
            
            $conventionsParams = @{
                ProductName             =   'web-api-starter'
                ProductFullName         =   'Web API Starter'
                ProductSubDomainName    =   'mriwebapistarter'
                EnvironmentName         =   $EnvironmentName
                SubProducts             =   [ordered]@{
                    PbiReportStorage    =   @{ 
                        Type                =   'StorageAccount'
                        AccountNamePrefix   =   'pbireport'
                        DefaultStorageTier  =   'Cool'
                        Usage               =   'Blob'
                    }
                    AppInsights         =   @{ Type = 'AppInsights' }
                    Sql                 =   @{ Type = 'SqlServer' }
                    Db                  =   @{ Type = 'SqlDatabase' }
                    InternalApi         =   @{ Type = 'FunctionApp'; StorageUsage = 'Queue' }
                    Api                 =   @{ Type = 'AksPod' }
                    ApiTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'Api' }
                    Web                 =   @{ Type = 'AksPod'; IsMainUI = $true; EnableManagedIdentity = $false }
                    WebTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'Web' }
                    KeyVault            =   @{ Type = 'KeyVault' }
                }
            }
            
            Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable
            
            # If you need to override conventions, follow the example below...
            
#            $convention = Get-ResourceConvention @conventionsParams -AsHashtable
            
#            $convention.AppInsights.ResourceName = 'aig-app-insights'
#            $convention.AppInsights.ResourceGroupName = 'rg-aig-app-insights'
#            $convention.Aks.RegistryName = 'mrisoftwaredevopscc'
#            $convention.SubProducts.ApiTrafficManager.ResourceName = $convention.SubProducts.ApiTrafficManager.ResourceName + '-2'
#            $convention.SubProducts.WebTrafficManager.ResourceName = $convention.SubProducts.WebTrafficManager.ResourceName + '-2'
            
#            if ($AsHashtable) {
#                $convention
#            } else {
#                $convention | ConvertTo-Json -Depth 100
#            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
