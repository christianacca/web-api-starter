    <#
      .SYNOPSIS
      Output as a table a section or individual setting value from the product conventions for ALL environments
      
      .PARAMETER SectionSelector
      A script block that returns the section from the product conventions that is to be output

      .PARAMETER SettingKey
      Individual setting key whose value to output

      .PARAMETER SchemaOnly
      Return only the names of the keys for the selected section

      .PARAMETER AsArray
      Return the output as an array of objects rather than a formatted table?

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.Aks.Primary }
    
      Description
      -----------
      Returns the setting values of the Aks.Primary section as a table. EG:
      
      Env       Path        TrafficManagerHost                                       ResourceName                       ResourceGroupName
      ---       ----        ------------------                                       ------------                       -----------------
      dev       Aks.Primary aks-sharedservices-dev-eastus-001.redmz.mrisoftware.com  aks-sharedservices-dev-eastus-001  rg-sharedservices-dev-eastus-001
      qa        Aks.Primary qa-aks-eastus.redmz.mrisoftware.com                      qa-aks-eastus                      qa-aks-eastus
      demo      Aks.Primary aks-sharedservices-demo-eastus-001.redmz.mrisoftware.com aks-sharedservices-demo-eastus-001 rg-sharedservices-demo-eastus-001
      staging   Aks.Primary staging-aks-eastus.aig.mrisoftware.com                   staging-aks-eastus                 staging-aks-eastus
      prod-na   Aks.Primary prod-aks-eastus.aig.mrisoftware.com                      prod-aks-eastus                    prod-aks-eastus
      prod-emea Aks.Primary prod-aks-uksouth.aig.mrisoftware.com                     prod-aks-uksouth                   prod-aks-uksouth
      prod-apac Aks.Primary prod-aks-australiaeast.aig.mrisoftware.com               prod-aks-australiaeast             prod-aks-australiaeast

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Pbi.AadSecurityGroup } -AsArray | Select-Object -ExcludeProperty Path, Member
    
      Description
      -----------
      Returns the setting values of the SubProducts.Pbi.AadSecurityGroup section as an array which is then projected to exclude Path and Member from the resulting table. EG:
      
      Env       PbiRole     Name
      ---       -------     ----
      dev       Admin       sg.365.pbi.workspace.aig.dev.admin
      dev       Admin       sg.365.pbi.workspace.aig.dev.app
      qa        Admin       sg.365.pbi.workspace.aig.qa.admin
      qa        Admin       sg.365.pbi.workspace.aig.qa.app
      demo      Admin       sg.365.pbi.report.aig.demo.admin

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Pbi.AadSecurityGroup } -AsArray | select * -pv grp | select -Exp Member -pv memb |
         select @{ n='Env'; e={ $grp.Env }}, @{ n='GroupName'; e={ $grp.Name }}, @{ n='Member'; e={ $memb.Name }}

      Description
      -----------
      Returns the setting values of the SubProducts.Pbi.AadSecurityGroup section as an array which is then projected to return a table from multiple properties. EG:
      
      Env       GroupName                                  Member
      ---       ---------                                  ------
      dev       sg.365.pbi.workspace.aig.dev.admin         sg.role.development.aig.dev
      qa        sg.365.pbi.workspace.aig.qa.admin          sg.role.development.aig.qa
      demo      sg.365.pbi.report.aig.demo.admin           sg.role.supporttier2.aig.demo
      demo      sg.365.pbi.dataset.aig.demo.admin          sg.role.supporttier2.aig.demo

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Values.RbacAssignment } -AsArray | Select-Object -ExcludeProperty Path, Member
    
      Description
      -----------
      Returns the setting values from every RbacAssignment section under SubProducts as an array which is then projected to return a table of values from nested fields. EG:
      
      Env       Role
      ---       ----
      dev       Storage Blob Data Contributor
      qa        Storage Blob Data Contributor
      demo      Storage Blob Data Reader

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Values.RbacAssignment } -AsArray | select * -pv role | select -Exp Member -pv memb |
         select @{ n='Env'; e={ $role.Env }}, @{ n='RoleName'; e={ $role.Role }}, @{ n='Member'; e={ $memb.Name }}

      Description
      -----------
      Returns the setting values from every RbacAssignment section under SubProducts as an array which is then projected to return a table of values from nested fields. EG:
      
      Env       RoleName                      Member
      ---       --------                      ------
      dev       Storage Blob Data Contributor sg.role.development.aig.dev
      qa        Storage Blob Data Contributor sg.role.development.aig.qa
      demo      Storage Blob Data Reader      sg.role.supporttier1.aig.demo
      demo      Storage Blob Data Contributor sg.role.development.aig.demo
      demo      Storage Blob Data Contributor sg.role.supporttier2.aig.demo

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Db } -SchemaOnly
   
      Description
      -----------
      Returns the setting keys of the SubProducts.Db section. EG:
    
      AadSecurityGroup
      RbacAssignment
      ResourceLocation
      ResourceName
      Type

      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table { $_.Aks.Primary } TrafficManagerHost
    
      Description
      -----------
      Returns the TrafficManagerHost setting value of the Aks.Primary as a table. EG:
      
      Env       Path        Value                                                    Key
      ---       ----        -----                                                    ---
      dev       Aks.Primary aks-sharedservices-dev-eastus-001.redmz.mrisoftware.com  TrafficManagerHost
      qa        Aks.Primary qa-aks-eastus.redmz.mrisoftware.com                      TrafficManagerHost
      demo      Aks.Primary aks-sharedservices-demo-eastus-001.redmz.mrisoftware.com TrafficManagerHost
      staging   Aks.Primary staging-aks-eastus.aig.mrisoftware.com                   TrafficManagerHost
      prod-na   Aks.Primary prod-aks-eastus.aig.mrisoftware.com                      TrafficManagerHost
      prod-emea Aks.Primary prod-aks-uksouth.aig.mrisoftware.com                     TrafficManagerHost
      prod-apac Aks.Primary prod-aks-australiaeast.aig.mrisoftware.com               TrafficManagerHost

      .EXAMPLE
      @(`
        ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Web } HostName -AsArray; `
        ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Api } HostName, ManagedIdentity -AsArray `
      ) | Where-Object Env -like 'prod-*' | Sort-Object Env, Key, Path
    
      Description
      -----------
      Returns keys from multiple sections as an array that is then filtered and sorted
      
      Env       Path            Value                        Key
      ---       ----            -----                        ---
      prod-apac SubProducts.Api apac-api.aig.mrisoftware.com HostName
      prod-apac SubProducts.Web apac.aig.mrisoftware.com     HostName
      prod-apac SubProducts.Api id-aig-prod-apac-api         ManagedIdentity
      prod-emea SubProducts.Api emea-api.aig.mrisoftware.com HostName
      prod-emea SubProducts.Web emea.aig.mrisoftware.com     HostName
      prod-emea SubProducts.Api id-aig-prod-emea-api         ManagedIdentity
      prod-na   SubProducts.Api na-api.aig.mrisoftware.com   HostName
      prod-na   SubProducts.Web na.aig.mrisoftware.com       HostName
      prod-na   SubProducts.Api id-aig-prod-na-api           ManagedIdentity

      .EXAMPLE
      @(
        ./tools/infrastructure/print-product-convention-table.ps1 { $_.Aks.Primary } -AsArray
        ./tools/infrastructure/print-product-convention-table.ps1 { $_.Aks.Failover } -AsArray
      ) | select @{ n='Type'; e={$_.Path} }, ResourceName, ResourceGroupName, TrafficManagerHost | ? ResourceName | ConvertTo-Csv > ./out/cluster-info.csv
    
      Description
      -----------
      Returns multiple sections as an array that is projected, filtered, output as csv, and saved to a file

      .EXAMPLE
      Write-Host '## RBAC (sub-products)' -ForegroundColor Blue; `
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Values.RbacAssignment } -AsArray | select * -pv role | select -Exp Member -pv memb |
        select @{ n='Env'; e={ $role.Env }}, @{ n='RoleName'; e={ $role.Role }}, @{ n='Member'; e={ $memb.Name }} | ft; `
      Write-Host '## RBAC (resource group)' -ForegroundColor Blue; `
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.AppResourceGroup.RbacAssignment } -AsArray | select * -pv role | select -Exp Member -pv memb |
        select @{ n='Env'; e={ $role.Env }}, @{ n='RoleName'; e={ $role.Role }}, @{ n='Member'; e={ $memb.Name }} | ft; `
      Write-Host '## Azure AAD groups (Db)' -ForegroundColor Blue; `
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Db.AadSecurityGroup } -AsArray | select * -pv grp | select -Exp Member -pv memb |
        select @{ n='Env'; e={ $grp.Env }}, @{ n='GroupName'; e={ $grp.Name }}, @{ n='Member'; e={ $memb.Name }} | ft; `
    
      Description
      -----------
      Returns tables describing all Azure RBAC and Azure ADD security group membership

    #>


    [CmdletBinding()]
    param(
        [ScriptBlock] $SectionSelector,

        [string[]] $SettingKey,
    
        [switch] $SchemaOnly,
        [switch] $AsArray
    
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {

            $environments = 'dev', 'qa', 'rel', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac'
            
            if ($SchemaOnly) {
                $environments |
                    ForEach-Object {
                        & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $_ -AsHashtable
                    } |
                    ForEach-Object $SectionSelector |
                    ForEach-Object {
                        $_ ? $_.Keys : @()
                    } | Select-Object -Unique | Sort-Object
            } else {

                $projection = if ($SettingKey) {
                    {
                        $section = $_
                        if ($section) {
                            $SettingKey | ForEach-Object {
                                @{
                                    Key     =   $_
                                    Value   =   $section[$_]
                                }
                            }
                        } else {
                            @()
                        }
                    }
                } else {
                    { $_ }
                }
                
                $path = $SectionSelector.ToString().Replace('$_.', '').Trim()
                
                $result = $environments |
                    ForEach-Object {
                        & "$PSScriptRoot/get-product-conventions.ps1" -EnvironmentName $_ -AsHashtable
                    } -pv convention  |
                    ForEach-Object $SectionSelector |
                    ForEach-Object $projection |
                    Select-Object @{ n='Env'; e={ $convention.EnvironmentName} }, @{ n='SettingPath'; e={ $path }}, *
                
                if ($AsArray) {
                    $result
                } else {
                    $result | Format-Table    
                }
            }
        }
        catch {
            Write-Error "$_`n$($_.ScriptStackTrace)" -EA $callerEA
        }
    }
