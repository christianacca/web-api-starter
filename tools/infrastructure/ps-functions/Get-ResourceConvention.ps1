function Get-ResourceConvention {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [string] $CompanyName = 'mri',
        
        [string] $GitOrganisationName = 'MRI-Software',
        
        [string] $GitRepositoryName,

        [Hashtable] $SubProducts = @{},

        [switch] $SeperateDataResourceGroup,
    
        [switch] $AsHashtable
    )

    $failoverEnvironmnets = 'qa', 'rel', 'release', 'prod-emea', 'prod-apac', 'prod-na'
    $hasFailover = if ($EnvironmentName -in $failoverEnvironmnets) { $true } else { $false }

    $azureRegions = switch ($EnvironmentName) {
        'prod-emea' {
            'uksouth', 'ukwest'
        }
        'prod-apac' {
            'australiaeast', 'australiasoutheast'
        }
        Default {
            'eastus', 'westus'
        }
    }

    $azurePrimaryRegion = $azureRegions[0]
    $azureSecondaryRegion = $azureRegions[1]

    $appResourceGroupName = '{0}-{1}'  -f $ProductName, $EnvironmentName
    $appReourceGroup = @{
        ResourceName        =   $appResourceGroupName
        ResourceLocation    =   $azurePrimaryRegion
    }
    
    $dataResourceGroup = if ($SeperateDataResourceGroup) {
        @{
            ResourceName        =   '{0}-{1}-data'  -f $ProductName, $EnvironmentName
            ResourceLocation    =   $azurePrimaryRegion
        }
    } else {
        $appReourceGroup
    }
    
    $sqlDbName = ('{0}{1}{2}01' -f $CompanyName, $EnvironmentName, $ProductName).Replace('-', '')
    $adSqlGroupNamePrefix = "sc.Azure.SQL.$sqlDbName"
    $sqlFirewallRule = @(
        @{
            StartIpAddress  =   '38.67.200.0'
            EndIpAddress    =   '38.67.200.126'
            Name            =   'mriNetwork01'
        }
        @{
            StartIpAddress  =   '66.181.76.192'
            EndIpAddress    =   '66.181.76.254'
            Name            =   'mriNetwork02'
        }
        @{
            StartIpAddress  =   '38.68.81.1'
            EndIpAddress    =   '38.68.81.6'
            Name            =   'mriNetwork03'
        }
    )
    $sqlPrimaryServer = @{
        ResourceName        =   '{0}{1}' -f $sqlDbName, $azurePrimaryRegion
        ResourceLocation    =   $azurePrimaryRegion
    }
    $sqlFailoverServer = @{
        ResourceName        =   '{0}{1}' -f $sqlDbName, $azureSecondaryRegion
        ResourceLocation    =   $azureSecondaryRegion
    }
    $dbGroupUser = @(
        @{
            Name            = "$adSqlGroupNamePrefix.Read";
            DatabaseRole    = 'db_datareader'
        }
        @{
            Name            = "$adSqlGroupNamePrefix.Crud";
            DatabaseRole    = 'db_datareader', 'db_datawriter'
        }
        @{
            Name            = "$adSqlGroupNamePrefix.Contributor";
            DatabaseRole    = 'db_datareader', 'db_datawriter', 'db_ddladmin'
        }
    )
    
    $aksNamespaceSuffix = if ($EnvironmentName -in 'qa', 'rel', 'release') {
        # we use the same AKS cluser for qa and release environment; good practice is a seperate namespace for each
        "-$EnvironmentName"
    } else {
        ''
    }
    $aksNamespace = 'app-{0}{1}' -f $ProductName, $aksNamespaceSuffix
    
    $aksClusterPrefix = switch ($EnvironmentName)
    {
        'prod-*' { 
            'prod' 
        }
        'ff' {
            'dev'
        }
        { $_ -in 'rel', 'release'} { 
            'qa' 
        }
        Default { 
            $EnvironmentName
        }
    }
    $aksPrimaryClusterName = '{0}-aks-{1}' -f $aksClusterPrefix, $azurePrimaryRegion
    $aksPrimaryCluster = @{
        ResourceName        =   $aksPrimaryClusterName
        ResourceGroupName   =   $aksPrimaryClusterName
    }
    $aksSecondaryClusterName = '{0}-aks-{1}' -f $aksClusterPrefix, $azureSecondaryRegion
    $aksSecondaryCluster = @{
        ResourceName        =   $aksSecondaryClusterName
        ResourceGroupName   =   $aksSecondaryClusterName
    }

    $subProductsConventions = @{}
    $SubProducts.Keys | ForEach-Object -Process {
        $spInput = $SubProducts[$_]
        $componentName = $_
        $convention = switch ($spInput.Type) {
            'SqlServer' {
                @{
                    Primary                 =   $sqlPrimaryServer
                    Failover                =   if($hasFailover) { $sqlFailoverServer } else { $null }
                    ManagedIdentity         =   "$sqlDbName-id"
                    ADGroupNamePrefix       =   $adSqlGroupNamePrefix
                    ADAdminGroupName        =   "$adSqlGroupNamePrefix.Admin"
                    Firewall                =   @{
                        Rule                    =   $sqlFirewallRule
                        AllowAllAzureServices   =   $true
                    }
                    Type                    =   $spInput.Type
                }
            }
            'SqlDatabase' {
                @{
                    ResourceName            =   $sqlDbName
                    ResourceLocation        =   $azurePrimaryRegion
                    DatabaseGroupUser       =   $dbGroupUser
                    Type                    =   $spInput.Type
                }
            }
            'FunctionApp' {
                @{
                    ResourceName        =   '{0}-{1}-{2}' -f $CompanyName, $appResourceGroupName, $componentName.ToLower()
                    ManagedIdentity     =   '{0}-{1}-{2}-id' -f $CompanyName, $appResourceGroupName, $componentName.ToLower()
                    Type                =   $spInput.Type
                }
            }
            'AksPod' {
                @{
                    ManagedIdentity     =   '{0}-{1}-{2}-id' -f $CompanyName, $appResourceGroupName, $componentName.ToLower()
                    Type                =   $spInput.Type
                }
            }
            default {
                $null
            }
        }
        if ($convention) {
            $subProductsConventions[$_] = $convention
        }
    }

    $GitRepositoryName = if ($GitRepositoryName) { 
        $GitRepositoryName 
    } else {
        "$(git rev-parse --show-toplevel)" -split [IO.Path]::DirectorySeparatorChar | Select-Object -Last 1
    }

    $results = @{
        Aks                     =   @{
            Primary             = $aksPrimaryCluster
            Failover            = if($hasFailover) { $aksSecondaryCluster } else { $null }
            Namespace           =   $aksNamespace
            HelmChartName       =   $ProductName
            RegistryName        =   'mrisoftwaredevops'
            ProdRegistryName    =   'mrisoftwaredevopsprod'
        }
        AutomationPrincipalName =   'automation-principal'
        AppResourceGroup        =   $appReourceGroup
        DataResourceGroup       =   $dataResourceGroup
        CompanyName             =   $CompanyName
        GitOrganisationName     =   $GitOrganisationName
        GitRepositoryName       =   $GitRepositoryName
        GithubCredentialName    =   'github-actions-{0}-{1}' -f $ProductName, $EnvironmentName
        ProductName             =   $ProductName
        SubProducts             =   $subProductsConventions
    }
    
    if ($AsHashtable) {
        $results
    }
    else {
        $results | ConvertTo-Json -Depth 100
    }
}
