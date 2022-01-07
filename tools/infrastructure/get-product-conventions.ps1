    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
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
                EnvironmentName         =   $EnvironmentName
                SubProducts             =   @{
                    Sql         =   @{ Type = 'SqlServer' }
                    Db          =   @{ Type = 'SqlDatabase' }
                    Func        =   @{ Type = 'FunctionApp' }
                    Api         =   @{ Type = 'AksPod' }
                }
            }
            Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable
            
            # If you need to override conventions, follow the example below...
<#            
            $convention = Get-ResourceConvention @conventionsParams -AsHashtable
            $convention.Aks.Primary.ResourceGroupName = 'aks-pod-identity'
            $convention.Aks.Primary.ResourceName = $convention.Aks.Primary.ResourceGroupName
            $convention.Aks.Failover = $null
            $convention.Aks.RegistryName = 'kcgmail'
            
            if ($AsHashtable) {
                $convention
            } else {
                $convention | ConvertTo-Json -Depth 100
            }
#>
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
