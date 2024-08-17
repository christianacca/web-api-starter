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
                CompanyName             =   'CLC Software'
                ProductName             =   'Web API Starter'
#                ProductAbbreviation     =   'was-cc'
                Domain                  = @{
                    TopLevelDomain      =   'co.uk' # <- default is 'com'
                    CompanyDomain       =   'codingdemo' # <- default is CompanyName lowercased with spaces removed
#                    NonProdSubDomain    =   'xyz' # <- default is 'devtest'. only applies when `SubDomainLevel` equals 3; specify 'UseProductDomain' to have non-prod environments use the product domain
#                    ProductDomain       =   'xyz' # <- default is ProductAbbreviation
                    # example of 2 level 'na-api-product.comapny.com'
                    # example of 3 levels 'na-api.product.comapny.com', 'dev-api-product.devtest.comapny.com'
                    SubDomainLevel      =   2 # <- default is 3
                }
                EnvironmentName         =   $EnvironmentName
                SubProducts             =   [ordered]@{
                    PbiReportStorage    =   @{ 
                        Type                =   'StorageAccount'
                        AccountNamePrefix   =   'pbireport'
                        DefaultStorageTier  =   'Cool'
                        Usage               =   'Blob'
                    }
                    Aca                 =   @{ Type = 'AcaEnvironment' }
                    AcrPull             =   @{ Type = 'ManagedIdentity' }
                    AppInsights         =   @{ Type = 'AppInsights' }
                    Sql                 =   @{ Type = 'SqlServer' }
                    Db                  =   @{ Type = 'SqlDatabase' }
                    InternalApi         =   @{ Type = 'FunctionApp'; StorageUsage = 'Queue' }
                    # IMPORTANT: 'Api' should match the name of the c# project in the solution, as this value is 
                    # used in create-and-push-docker-images.ps1 to determine part of the ACR repository name for the docker image for this project
                    Api                 =   @{ Type = 'AcaApp'; AdditionalManagedId = 'AcrPull' }
                    ApiTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'Api' }
                    ApiAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'Api' }
                    # example of an extended health check:
#                    ApiExtendedAvailabilityTest =   @{ Type = 'AvailabilityTest'; IsExtendedCheck = $true; Path = '/health-extended'; Target = 'Api' }
                    KeyVault            =   @{ Type = 'KeyVault' }
#                    Web                 =   @{ Type = 'AcaApp'; IsMainUI = $true }
                }
                Subscriptions           =   & "$PSScriptRoot/get-product-azure-subscriptions.ps1"
            }
            
            Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable

            # If you need to override conventions, comment out the above line, and follow the example below...

#            $convention = Get-ResourceConvention @conventionsParams -AsHashtable
#
#            $convention.ContainerRegistries.Dev.ResourceGroupName = 'Container_Registry'
#            $convention.ContainerRegistries.Prod.ResourceGroupName = 'container-registry'
#
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
