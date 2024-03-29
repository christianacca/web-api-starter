function Set-AzureResourceGroup {
    <#
      .SYNOPSIS
      Creates or updates the azure resource group
      
      .DESCRIPTION
      Creates or updates the azure resource group.
      This script is written to be idempotent so it is safe to be run multiple times.
      
      Required permission to run this script:
      * Azure AD role: 'Contributor'
    
      .PARAMETER Name
      Specifies the name of the resource group.

      .PARAMETER Location
      Specifies the location of the resource group. Required if the resource group does not exist.
    
      .PARAMETER Tag
      Key-value pairs in the form of a hash table. For example: @{key0="value0";key1=$null;key2="value2"}.
      If not supplied then the existing tags on the resource group will not be changed.
    
      .PARAMETER MergeTag
      Merge tags supplied with the existing tags defined on the resource group. The default behaviour is to remove
      existing tags and replace with the new tags supplied

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        
        [string] $Location,
        
        [Hashtable] $Tag,
    
        [switch] $MergeTag
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $rg = Get-AzResourceGroup $Name -EA SilentlyContinue
            if (-not($rg)) {
                Write-Information "Creating Azure Resource Group '$Name'..."
                New-AzResourceGroup $Name $Location -Tag $Tag -EA Stop
                return
            }
            
            if ($null -eq $Tag) {
                $rg
                return  
            }

            $tags = if ($MergeTag) {
                $existingTags = $rg.Tags.Clone()
                $Tag.keys | ForEach-Object -Process { $existingTags[$_] = $Tag[$_] } -End { $existingTags }
            } else {
                $Tag
            }
            Write-Information "Setting tags on Azure Resource Group '$Name'..."
            Set-AzResourceGroup -Name $Name -Tag $tags -EA Stop
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
