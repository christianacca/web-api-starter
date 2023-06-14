function Install-ManagedIdentityAzureResource {
    <#
      .SYNOPSIS
      Provision a user assigned managed identity
     
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $TemplateFile,

        [Hashtable] $TemplateParameterObject = @{}
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
            
            Write-Information "Setting User Assigned Managed Identity '$Name'..."
            $templateParamValues = $TemplateParameterObject + @{
                managedIdentityName     =   $Name
            }
            $managedIdArmParams = @{
                ResourceGroupName       =   $ResourceGroup
                TemplateParameterObject =   $templateParamValues
                TemplateFile            =   $TemplateFile
            }
            $deploymentResult = New-AzResourceGroupDeployment @managedIdArmParams -EA Stop
            $managedId = [PSCustomObject]$deploymentResult.Outputs
            @{
                ClientId    =   $managedId.clientId.Value
                PrincipalId =   $managedId.principalId.Value
                ResourceId  =   $managedId.resourceId.Value
            }
            
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
