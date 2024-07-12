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
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Api.Primary }
    
      Description
      -----------
      Returns the setting values of the SubProducts.Api.Primary section as a table. EG:
      
      Env       SettingPath             IngressHostname                                 MinReplicas MaxReplicas ResourceName             DefaultHealthPath
      ---       -----------             ---------------                                 ----------- ----------- ------------             -----------------
      dev       SubProducts.Api.Primary ca-was-dev-eus-api.ACA_ENV_DEFAULT_DOMAIN                 0           2 ca-was-dev-eus-api       /health
      qa        SubProducts.Api.Primary ca-was-qa-eus-api.ACA_ENV_DEFAULT_DOMAIN                  1           6 ca-was-qa-eus-api        /health
      rel       SubProducts.Api.Primary ca-was-rel-eus-api.ACA_ENV_DEFAULT_DOMAIN                 1           6 ca-was-rel-eus-api       /health
      demo      SubProducts.Api.Primary ca-was-demo-eus-api.ACA_ENV_DEFAULT_DOMAIN                2           6 ca-was-demo-eus-api      /health
      staging   SubProducts.Api.Primary ca-was-staging-eus-api.ACA_ENV_DEFAULT_DOMAIN             0           6 ca-was-staging-eus-api   /health
      prod-na   SubProducts.Api.Primary ca-was-prod-na-eus-api.ACA_ENV_DEFAULT_DOMAIN             3           6 ca-was-prod-na-eus-api   /health
      prod-emea SubProducts.Api.Primary ca-was-prod-emea-uks-api.ACA_ENV_DEFAULT_DOMAIN           3           6 ca-was-prod-emea-uks-api /health
      prod-apac SubProducts.Api.Primary ca-was-prod-apac-ae-api.ACA_ENV_DEFAULT_DOMAIN            3           6 ca-was-prod-apac-ae-api  /health


      .EXAMPLE
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Pbi.AadSecurityGroup } -AsArray | Select-Object -ExcludeProperty SettingPath, Member
    
      Description
      -----------
      Returns the setting values of the SubProducts.Pbi.AadSecurityGroup section as an array which is then projected to exclude SettingPath and Member from the resulting table. EG:
      
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
      ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Values.RbacAssignment } -AsArray | Select-Object -ExcludeProperty SettingPath, Member
    
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
      ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Api } Hostname
    
      Description
      -----------
      Returns the Hostname setting value of the SubProducts.Api as a table. EG:
      
      Env       SettingPath     Key      Value
      ---       -----------     ---      -----
      dev       SubProducts.Api Hostname dev-api-was.redmz.clcsoftware.com
      qa        SubProducts.Api Hostname qa-api-was.redmz.clcsoftware.com
      rel       SubProducts.Api Hostname rel-api-was.redmz.clcsoftware.com
      demo      SubProducts.Api Hostname demo-api-was.redmz.clcsoftware.com
      staging   SubProducts.Api Hostname staging-api.was.clcsoftware.com
      prod-na   SubProducts.Api Hostname na-api.was.clcsoftware.com
      prod-emea SubProducts.Api Hostname emea-api.was.clcsoftware.com
      prod-apac SubProducts.Api Hostname apac-api.was.clcsoftware.com


      .EXAMPLE
      @(`
        ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Web } HostName -AsArray; `
        ./tools/infrastructure/print-product-convention-table { $_.SubProducts.Api } HostName, ManagedIdentity -AsArray `
      ) | Where-Object Env -like 'prod-*' | Sort-Object Env, Key, SettingPath
    
      Description
      -----------
      Returns keys from multiple sections as an array that is then filtered and sorted
      
      Env       SettingPath     Value                        Key
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
        ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Api.Primary } -AsArray
        ./tools/infrastructure/print-product-convention-table.ps1 { $_.SubProducts.Api.Failover } -AsArray
      ) | select @{ n='Type'; e={$_.SettingPath} }, ResourceName, IngressHostName | ? ResourceName -like '*api' | ConvertTo-Csv > ./out/cluster-info.csv
    
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
