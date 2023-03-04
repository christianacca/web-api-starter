function Install-TrafficManagerProfileResource {
    <#
      .SYNOPSIS
      Provision the desired state of a traffic manager profile
    
      .PARAMETER ResourceGroup
      The name of the resource group to add the resources to. This group must already exist
          
      .PARAMETER $InputObject
      A hashtable describing the traffic manager profile
      
      .PARAMETER TemplateDirectory
      The path to the directory containing the ARM templates. The following ARM templates should exist:
      * traffic-manager.json
      * traffic-manager-with-secondary.json
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [Hashtable] $InputObject,

        [Parameter(Mandatory)]
        [string] $TemplateDirectory
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        
    }
    process {
        try {
            if (-not(Get-AzContext)) {
                throw 'There is no Azure Account context set. Please make sure to login using Connect-AzAccount'
            }

            $tmParamObject = @{
                uniqueDnsName                   =   $InputObject.ResourceName
                path                            =   $InputObject.TrafficManagerPath
                primaryEndPointName             =   $InputObject.PrimaryEndpoint.Name
                primaryEndPointHostName         =   $InputObject.PrimaryEndpoint.HostName
                primaryEndPointLocation         =   $InputObject.PrimaryEndpoint.Location
            }
            if ($InputObject.SecondaryEndpoint) {
                $tmParamObject = $tmParamObject + @{
                    secondaryEndPointName       =   $InputObject.SecondaryEndpoint.Name
                    secondaryEndPointHostName   =   $InputObject.SecondaryEndpoint.HostName
                    secondaryEndPointLocation   =   $InputObject.SecondaryEndpoint.Location
                }
            }
            $tmTemplateFile = $InputObject.SecondaryEndpoint ? 'traffic-manager-with-secondary.json' : 'traffic-manager.json'
            $webTmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   $tmParamObject
                TemplateFile            =   Join-Path $TemplateDirectory $tmTemplateFile
            }
            Write-Information "Setting Traffic manager profile '$($InputObject.ResourceName)'..."
            New-AzResourceGroupDeployment @webTmParams -EA Stop | Out-Null
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
