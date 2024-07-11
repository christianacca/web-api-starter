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
                ProductName             =   'was'
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
                    ApiAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'Api' }
                    # example of an extended health check:
#                    ApiExtendedAvailabilityTest =   @{ Type = 'AvailabilityTest'; IsExtendedCheck = $true; Path = '/health-extended'; Target = 'Api' }
                    Web                 =   @{ Type = 'AksPod'; IsMainUI = $true; EnableManagedIdentity = $false }
                    WebTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'Web' }
                    WebAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'Web' }
                    KeyVault            =   @{ Type = 'KeyVault' }
                }
            }
            
#            Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable

            # If you need to override conventions, comment out the above line, and follow the example below...

            $convention = Get-ResourceConvention @conventionsParams -AsHashtable

            $convention.Aks.RegistryName = 'mrisoftwaredevopslocal'

            if ($AsHashtable) {
                $convention
            } else {
                $convention | ConvertTo-Json -Depth 100
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
