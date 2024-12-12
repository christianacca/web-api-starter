function Get-AcaAppInfoVars {
    <#
      .SYNOPSIS
      Get the variables for the ACA App deployment
      
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject,
        
        [Parameter(Mandatory)]
        [string] $SubProductName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $appResourceGroup = $convention.AppResourceGroup
            $app = $convention.SubProducts[$SubProductName]

            $failoverExists = if ($app.Failover) {
                $null -ne (Get-AzContainerApp -ResourceGroupName $appResourceGroup.ResourceName -Name $app.Failover.ResourceName -EA SilentlyContinue)
            } else {
                $false
            }
            $primaryExists = $null -ne (Get-AzContainerApp -ResourceGroupName $appResourceGroup.ResourceName -Name $app.Primary.ResourceName -EA SilentlyContinue)
            
            $vars = @{}
            $vars[('{0}FailoverExists' -f $SubProductName.ToLower())] = $failoverExists
            $vars[('{0}PrimaryExists' -f $SubProductName.ToLower())] = $primaryExists

            $vars
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}