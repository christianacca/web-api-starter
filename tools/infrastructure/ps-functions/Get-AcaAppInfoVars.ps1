function Get-AcaAppInfoVars {
    <#
      .SYNOPSIS
      Get the variables for the ACA App deployment
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Hashtable] $AppInfo,
        
        [Parameter(Mandatory)]
        [string] $ResourceGroupName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $failoverExists = if ($AppInfo.Failover) {
                $null -ne (Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $AppInfo.Failover.ResourceName -EA SilentlyContinue)
            } else {
                $false
            }
            $primaryExists = $null -ne (Get-AzContainerApp -ResourceGroupName $ResourceGroupName -Name $AppInfo.Primary.ResourceName -EA SilentlyContinue)
            
            $varPrefix = $AppInfo.Name.ToLower()
            $vars = @{}
            $vars[('{0}FailoverExists' -f $varPrefix)] = $failoverExists
            $vars[('{0}PrimaryExists' -f $varPrefix)] = $primaryExists

            $vars
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}