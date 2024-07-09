function Get-ResourceConvention {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        
        [string] $ProductFullName,
        
        [string] $ProductSubDomainName,
        
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [string] $CompanyName = 'mri',

        [Collections.Specialized.OrderedDictionary] $SubProducts = @{},

        [switch] $SeperateDataResourceGroup,
    
        [switch] $AsHashtable
    )
    
    Set-StrictMode -Off # allow reference to non-existant object properties to keep script readable

    . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    . "$PSScriptRoot/Get-PublicHostName.ps1"
    . "$PSScriptRoot/Get-PbiAadSecurityGroupConvention.ps1"
    . "$PSScriptRoot/Get-RootDomain.ps1"
    . "$PSScriptRoot/Get-StorageRbacAccess.ps1"
    . "$PSScriptRoot/Get-TeamGroupNames.ps1"
    . "$PSScriptRoot/Get-UniqueString.ps1"

    $failoverEnvironmnets = 'qa', 'rel', 'release', 'prod-emea', 'prod-apac', 'prod-na'
    $hasFailover = if ($EnvironmentName -in $failoverEnvironmnets) { $true } else { $false }

    $productNameLower = $ProductName.ToLower()
    if(-not($ProductFullName)) { $ProductFullName = $ProductName.ToUpper() }
    if(-not($ProductSubDomainName)) { $ProductSubDomainName = '{0}{1}' -f $CompanyName.ToLower(), $productNameLower }

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

    $teamGroupNames = Get-TeamGroupNames $ProductName $EnvironmentName

    $azurePrimaryRegion = $azureRegions[0]
    $azureSecondaryRegion = $azureRegions[1]

    $isEnvProdLike = Get-IsEnvironmentProdLike $EnvironmentName
    $isTestEnv = $EnvironmentName -in 'ff', 'dev', 'qa', 'rel', 'release'

    $resourceGroupRbac = @(
        @{
            Role    =   $isTestEnv -or ($EnvironmentName -eq 'demo') ? 'Contributor' : 'Reader'
            Member  =   @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
        }
        @{
            Role    =   'Reader'
            Member  =   @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
        }
        @{
            Role    =   $isTestEnv ? 'Reader' : 'Contributor'
            Member  =   @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
        }
    )

    $appInstance = '{0}-{1}' -f $productNameLower, $EnvironmentName
    $appResourceGroupName = 'rg-{0}-{1}-{2}' -f $EnvironmentName, $productNameLower, $azurePrimaryRegion
    $appReourceGroup = @{
        ResourceName        =   $appResourceGroupName
        ResourceLocation    =   $azurePrimaryRegion
        UniqueString        =   Get-UniqueString $appResourceGroupName
        RbacAssignment      =   $resourceGroupRbac
    }
    
    $dataResourceGroup = if ($SeperateDataResourceGroup) {
        @{
            RbacAssignment      =   $resourceGroupRbac
            ResourceName        =   'rg-{0}-{1}-{2}-data' -f $EnvironmentName, $productNameLower, $azurePrimaryRegion
            ResourceLocation    =   $azurePrimaryRegion
        }
    } else {
        $appReourceGroup
    }

    $managedIdentityNamePrefix = "id-$appInstance"
    
    $aksNamespaceSuffix = if ($EnvironmentName -in 'qa', 'rel', 'release') {
        # we use the same AKS cluser for qa and release environment; good practice is a seperate namespace for each
        "-$EnvironmentName"
    } else {
        ''
    }
    $aksNamespace = 'app-{0}{1}' -f $productNameLower, $aksNamespaceSuffix
    $helmReleaseName = $productNameLower
    
    $aksClusterPrefix = switch ($EnvironmentName) {
        { $_ -like 'prod-*' } { 
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

    $rootDomain = Get-RootDomain $EnvironmentName
    switch ($EnvironmentName) {
        { $_ -in 'ff', 'dev', 'demo'} {
            $aksClusterNameTemplate = "aks-sharedservices-$aksClusterPrefix-{0}-001"
            $aksResourceGroupNameTemplate = $aksClusterNameTemplate.Replace('aks-', 'rg-')
        }
        'staging' {
            $aksClusterNameTemplate = "aks-shared-$aksClusterPrefix-{0}-001"
            $aksResourceGroupNameTemplate = $aksClusterNameTemplate.Replace('aks-', 'rg-')
        }
        Default {
            $aksClusterNameTemplate = "$aksClusterPrefix-aks-{0}"
            $aksResourceGroupNameTemplate = "$aksClusterPrefix-aks-{0}"
        }
    }
    # todo: delete the above switch statement and uncomment the next 2 lines once switched from old aks clusters to new
    #    $aksClusterNameTemplate = "aks-shared-$aksClusterPrefix-{0}-001"
    #    $aksResourceGroupNameTemplate = $aksClusterNameTemplate.Replace('aks-', 'rg-')

    switch ($EnvironmentName) {
        'staging' {
            $aksRootDomain = "cloud.$rootDomain"
        }
        Default {
            $aksRootDomain = $rootDomain
        }
    }

    $aksPrimaryClusterName = $aksClusterNameTemplate -f $azurePrimaryRegion
    $aksPrimaryCluster = @{
        ResourceName        =   $aksPrimaryClusterName
        ResourceGroupName   =   $aksResourceGroupNameTemplate -f $azurePrimaryRegion
        TrafficManagerHost  =   '{0}.{1}' -f $aksPrimaryClusterName, $aksRootDomain
    }

    $aksSecondaryClusterName = $aksClusterNameTemplate -f $azureSecondaryRegion
    $aksSecondaryCluster = @{
        ResourceName        =   $aksSecondaryClusterName
        ResourceGroupName   =   $aksResourceGroupNameTemplate -f $azureSecondaryRegion
        TrafficManagerHost  =   '{0}.{1}' -f $aksSecondaryClusterName, $aksRootDomain
    }

    $subProductsConventions = @{}
    $SubProducts.Keys | ForEach-Object -Process {
        $spInput = $SubProducts[$_]
        $componentName = $_
        $convention = switch ($spInput.Type) {
            'ManagedIdentity' {
                @{
                    ResourceName        =   '{0}-{1}' -f $managedIdentityNamePrefix, $componentName.ToLower()
                    Type                =   $spInput.Type
                }
            }
            'StorageAccount' {
                $storageUsage = $spInput.Usage ?? 'Blob'
                $rbacAssignment = switch ($EnvironmentName) {
                    { $isTestEnv } {
                        @{
                            Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                            Member          =   @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                        }
                    }
                    'demo' {
                        @{
                            Role            =   Get-StorageRbacAccess $storageUsage 'Readonly'
                            Member          =   @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                        }
                        @{
                            Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                            Member          =   @(
                                @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                            )
                        }
                    }
                    { $isEnvProdLike } {
                        @{
                            Role            =   Get-StorageRbacAccess $storageUsage 'Readonly'
                            Member          =   @(
                                @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                            )
                        }
                        @{
                            Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                            Member          =   @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                        }
                    }
                    Default {
                        Write-Output @() -NoEnumerate
                    }
                }
                @{
                    StorageAccountName  =   '{0}{1}' -f ($spInput.AccountNamePrefix ?? 'store'), $appReourceGroup.UniqueString
                    StorageAccountType  =   $hasFailover ? 'Standard_GZRS' : 'Standard_LRS'
                    DefaultStorageTier  =   $spInput.DefaultStorageTier ?? 'Hot'
                    RbacAssignment      =   $rbacAssignment
                    Type                =   $spInput.Type
                }
            }
            { $_ -in 'SqlServer', 'SqlDatabase' } {
                $sqlDbName = ('{0}{1}{2}01' -f $CompanyName, $EnvironmentName, $productNameLower).Replace('-', '')
                $sqlPrimaryName = '{0}{1}' -f $sqlDbName, $azurePrimaryRegion
                $adSqlGroupNamePrefix = "sg.arm.sql.$sqlDbName"
                $sqlAdAdminGroupName = "$adSqlGroupNamePrefix.admin"

                switch ($spInput.Type) {
                    'SqlServer' {
                        $sqlPrimaryServer = @{
                            ResourceName        =   $sqlPrimaryName
                            ResourceLocation    =   $azurePrimaryRegion
                            DataSource          =   $hasFailover ? "tcp:$sqlDbName-fg.database.windows.net,1433" : "tcp:$sqlPrimaryName.database.windows.net,1433"
                        }
                        $sqlFailoverServer = @{
                            ResourceName        =   '{0}{1}' -f $sqlDbName, $azureSecondaryRegion
                            ResourceLocation    =   $azureSecondaryRegion
                        }
                        $sqlFirewallRule = @(
                            @{
                                StartIpAddress  =   '0.0.0.0'
                                EndIpAddress    =   '0.0.0.0'
                                Name            =   'AllowAllWindowsAzureIps' # this is a special name that allows all Azure services
                            }
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
                            @{
                                StartIpAddress  =   '149.14.146.176'
                                EndIpAddress    =   '149.14.146.182'
                                Name            =   'London.VPN.04'
                            }
                            @{
                                StartIpAddress  =   '123.103.222.144'
                                EndIpAddress    =   '123.103.222.158'
                                Name            =   'Sydney.VPN.05'
                            }
                        )
                        @{
                            Primary                 =   $sqlPrimaryServer
                            Failover                =   if($hasFailover) { $sqlFailoverServer } else { $null }
                            ManagedIdentity         =   "$managedIdentityNamePrefix-$sqlPrimaryName"
                            AadAdminGroupName       =   $sqlAdAdminGroupName
                            AadGroupNamePrefix      =   $adSqlGroupNamePrefix
                            Firewall                =   @{
                                Rule                    =   $sqlFirewallRule
                                AllowAllAzureServices   =   $true
                            }
                            Type                    =   $spInput.Type
                        }
                    }
                    'SqlDatabase' {
                        $dbGroup = @(
                            @{
                                Name            = "$adSqlGroupNamePrefix.reader";
                                DatabaseRole    = 'db_datareader'
                                Member          = switch ($EnvironmentName) {
                                    { $_ -like 'prod-*' -or $_ -eq 'staging' } {
                                        @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                        @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                                    }
                                    'demo' {
                                        @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                                    }
                                    Default {
                                        Write-Output @() -NoEnumerate
                                    }
                                }
                            }
                            @{
                                Name            = "$adSqlGroupNamePrefix.crud";
                                DatabaseRole    = 'db_datareader', 'db_datawriter'
                                Member          = switch ($EnvironmentName) {
                                    'demo' {
                                        @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                    }
                                    Default {
                                        Write-Output @() -NoEnumerate
                                    }
                                }
                            }
                            @{
                                Name            = "$adSqlGroupNamePrefix.contributor";
                                DatabaseRole    = 'db_datareader', 'db_datawriter', 'db_ddladmin'
                                Member          = switch ($EnvironmentName) {
                                    { $_ -like 'prod-*' -or $_ -eq 'staging' -or $_ -eq 'demo' } {
                                        @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                                    }
                                    Default {
                                        Write-Output @() -NoEnumerate
                                    }
                                }
                            }
                            @{
                                Name            =   $sqlAdAdminGroupName
                                Member          = if ($isTestEnv) {
                                    @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                }
                                else {
                                    Write-Output @() -NoEnumerate
                                }
                            }
                        )
                        @{
                            AadSecurityGroup        =   $dbGroup
                            ResourceName            =   $sqlDbName
                            ResourceLocation        =   $azurePrimaryRegion
                            Type                    =   $spInput.Type
                        }
                    }
                }
            }
            'FunctionApp' {
                $funcResourceName = 'func-{0}-{1}-{2}' -f $CompanyName, $appInstance, $componentName.ToLower()
                $funcHostName = $spInput.HasMriDomain ? `
                    (Get-PublicHostName $EnvironmentName $ProductSubDomainName $componentName) : `
                    "$funcResourceName.azurewebsites.net"
                
                $storageUsage = $spInput.StorageUsage
                $rbacAssignment = if ($storageUsage) {
                    switch ($EnvironmentName) {
                        { $isTestEnv } {
                            @{
                                Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                                Member          =   @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                            }
                        }
                        'demo' {
                            @{
                                Role            =   Get-StorageRbacAccess $storageUsage 'Readonly'
                                Member          =   @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                            }
                            @{
                                Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                                Member          =   @(
                                    @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                    @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                                )
                            }
                        }
                        { $isEnvProdLike } {
                            @{
                                Role            =   Get-StorageRbacAccess $storageUsage 'Readonly'
                                Member          =   @(
                                    @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                    @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                                )
                            }
                            @{
                                Role            =   Get-StorageRbacAccess $storageUsage 'ReadWrite'
                                Member          =   @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                            }
                        }
                        Default {
                            Write-Output @() -NoEnumerate
                        }
                    }
                } else {
                    @()
                }
                @{
                    # Note: this `AuthTokenAudience` is the only value to work (in addition to the app client id)
                    # tried "api://$funcResourceName.azurewebsites.net" and "https://$funcResourceName.azurewebsites.net"
                    AuthTokenAudience   =   "api://$funcResourceName/.default"
                    ManagedIdentity     =   '{0}-{1}' -f $managedIdentityNamePrefix, $componentName.ToLower()
                    HostName            =   $funcHostName
                    RbacAssignment      =   $rbacAssignment
                    ResourceName        =   $funcResourceName
                    StorageAccountName  =   '{0}{1}' -f ($spInput.StorageAccountNamePrefix ?? 'funcsa'), $appReourceGroup.UniqueString
                    Type                =   $spInput.Type
                }
            }
            'AksPod' {
                $isMainUI = $spInput.IsMainUI ?? $false
                $managedId = '{0}-{1}' -f $managedIdentityNamePrefix, $componentName.ToLower()
                $oidcAppProductName = $spInput.OidcAppProductName ?? $ProductFullName
                $oidcAppName = '{0}{1} ({2})' -f $oidcAppProductName, ($isMainUI ? '' : ' API'), $EnvironmentName
                
                @{
                    ManagedIdentity     =   $spInput.EnableManagedIdentity -eq $false ? $null : $managedId
                    HostName            =   Get-PublicHostName $EnvironmentName $ProductSubDomainName $componentName -IsMainUI:$isMainUI
                    OidcAppName         =   $oidcAppName
                    ServiceAccountName  =   '{0}-{1}' -f $helmReleaseName, $componentName.ToLower()
                    TrafficManagerPath  =   '/trafficmanager-health-{0}-{1}' -f $aksNamespace, $componentName.ToLower()
                    DefaultHealthPath   =   $isMainUI ? '/health/status' : '/health'
                    Type                =   $spInput.Type
                }
            }
            'AppInsights' {
                $envAbbreviation = switch ($EnvironmentName) {
                    { $_ -like 'prod-*' } {
                        'p{0}' -f $EnvironmentName.Replace('prod-', '')
                    }
                    'release' {
                        'rel'
                    }
                    'staging' {
                        'stage'
                    }
                    Default {
                        $EnvironmentName
                    }
                }

                $rbacAssignment = switch ($EnvironmentName) {
                    { $isTestEnv } {
                        @{
                            Role            =   'Monitoring Contributor'
                            Member          =   @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                        }
                    }
                    { $isEnvProdLike -or $_ -eq 'demo' } {
                        @{
                            Role            =   'Monitoring Contributor'
                            Member          =   @(
                                @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                                @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                            )

                        }
                        @{
                            Role            =   'Monitoring Reader'
                            Member          =   @{ Name = $teamGroupNames.Tier1SupportGroup; Type = 'Group' }
                        }
                    }
                    Default {
                        Write-Output @() -NoEnumerate
                    }
                }

                @{
                    EnvironmentAbbreviation =   $envAbbreviation
                    IsMetricAlertsEnabled   =   $EnvironmentName -in 'dev', 'ff' ? $false : $true
                    RbacAssignment          =   $rbacAssignment
                    ResourceName            =   "appi-$appInstance"
                    ResourceGroupName       =   $appResourceGroupName
                    Type                    =   $spInput.Type
                    WorkspaceName           =   "log-$appInstance"
                }
            }
            'AvailabilityTest' {
                $targetSubProduct = $subProductsConventions[$spInput.Target]

                $fifteenMinutes = 900
                $availabilityTestFrequency = $spInput.IsExtendedCheck -or $isTestEnv ? $fifteenMinutes : 300
                $availabilityMetricFrequency = $availabilityTestFrequency -eq $fifteenMinutes ? 'PT5M' : 'PT1M'
                $availabilityMetricQueryWindow = $availabilityTestFrequency -eq $fifteenMinutes ? 'PT15M' : 'PT5M'

                # for a list of locations, see https://learn.microsoft.com/en-us/azure/azure-monitor/app/availability-standard-tests#azure
                # for a default health check, use the default set of (5) locations from which to run availability tests
                # for an extended health check, use fewer locations (Central US and West Europe) so as to not tax our service endpoint
                $testLocations = $spInput.IsExtendedCheck ? @('us-fl-mia-edge', 'emea-nl-ams-azr') : $null
                $nameQualifier = $spInput.IsExtendedCheck ? 'extended' : 'default'

                $isAvailabilityTestEnabled = $EnvironmentName -ne 'dev' # we want dev to scale to zero therefore don't check availability
                $availabilityFriendlyName = '{0} {1} - {2} health check' -f $ProductName.ToUpper(), $spInput.Target, $nameQualifier

                @{
                    Enabled                     =   $isAvailabilityTestEnabled
                    Frequency                   =   $availabilityTestFrequency
                    Locations                   =   $testLocations
                    MetricAlert                 =   @{
                        Description             =   'Alert rule for availability test "{0}"' -f $availabilityFriendlyName
                        Enabled                 =   $isAvailabilityTestEnabled
                        EvaluationFrequency     =   $availabilityMetricFrequency
                        ResourceName            =   'ima-{0}-{1}-{2}' -f $appInstance, $spInput.Target.ToLower(), $nameQualifier
                        FailedLocationCount     =   2
                        WindowSize              =   $availabilityMetricQueryWindow
                    }
                    Name                        =   $availabilityFriendlyName
                    RequestUrl                  =   'https://{0}{1}' -f $targetSubProduct.HostName, ($spInput.Path ?? $targetSubProduct.DefaultHealthPath)
                    ResourceName                =   'iwt-{0}-{1}-{2}' -f $appInstance, $spInput.Target.ToLower(), $nameQualifier
                    Type                        =   $spInput.Type
                }
            }
            'TrafficManager' {
                $tmEnvQualifier = if ($EnvironmentName -in 'qa', 'rel', 'release') {
                    # we use the same AKS cluser for qa and release environment; good practice is a seperate namespace for each
                    "-$EnvironmentName"
                } else {
                    ''
                }
                $primaryAksTrafficManagerEndpoint = @{
                    Name                =   '{0}-{1}-{2}' -f $aksPrimaryClusterName, $aksNamespace, $spInput.Target.ToLower()
                    Target              =   $aksPrimaryCluster.TrafficManagerHost
                    EndpointLocation    =   $azurePrimaryRegion
                }
                $secondaryAksTrafficManagerEndpoint = @{
                    Name                =   '{0}-{1}-{2}' -f $aksSecondaryClusterName, $aksNamespace, $spInput.Target.ToLower()
                    Target              =   $aksSecondaryCluster.TrafficManagerHost
                    EndpointLocation    =   $azureSecondaryRegion
                }
                $targetSubProduct = $subProductsConventions[$spInput.Target]
                if ($targetSubProduct.Type = 'AksPod') {
                    @{
                        ResourceName        =   $targetSubProduct.HostName.Replace(".$rootDomain", '').Replace('.', '-')
                        TrafficManagerPath  =   $targetSubProduct.TrafficManagerPath
                        Endpoints           =   @($primaryAksTrafficManagerEndpoint) + ($hasFailover ? @($secondaryAksTrafficManagerEndpoint) : @())
                        Type                =   $spInput.Type
                    }
                } else {
                    throw 'Traffic manager convention for non-AKS not yet defined'
                }
            }
            'Pbi' {
                $pbiTeamGroupNames = Get-TeamGroupNames -ProductName "$ProductName-Pbi" -EnvironmentName $EnvironmentName
                $pbiTeamAadConventionParams = @{
                    ProductName         =   $ProductName
                    EnvironmentName     =   $EnvironmentName
                    TeamGroupNames      =   $pbiTeamGroupNames
                    TeamGroupMemberOnly =   $true
                }
                $pbiTeamGroupMembership = Get-PbiAadSecurityGroupConvention @pbiTeamAadConventionParams | ForEach-Object { [PsCustomObject]$_ }
                $pbiGroups = Get-PbiAadSecurityGroupConvention $ProductName $EnvironmentName $teamGroupNames | ForEach-Object {
                    $pbiGrp = $_
                    $pbiGrp.Member = @(
                        $pbiTeamGroupMembership | Where-Object Name -like $pbiGrp.Name | Select-Object -Exp Member
                        $pbiGrp.Member
                    )
                    $pbiGrp
                }
                @{
                    AadGroupNamePrefix  =   'sg.365.pbi'
                    AadSecurityGroup    =   $pbiGroups
                    TeamGroups          =   $pbiTeamGroupNames
                    Type                =   $spInput.Type
                }
            }
            'KeyVault' {
                $rbacAssignment =  @(
                    @{
                        Role            =   'Key Vault Secrets Officer'
                        Member          =   if ($isTestEnv) {
                            @{ Name = $teamGroupNames.DevelopmentGroup; Type = 'Group' }
                        } else {
                            @{ Name = $teamGroupNames.Tier2SupportGroup; Type = 'Group' }
                        }
                    }
                )

                @{
                    ResourceName            =   'kv-{0}' -f $appInstance
                    EnablePurgeProtection   =   $isEnvProdLike
                    RbacAssignment          =   $rbacAssignment
                    Type                    =   $spInput.Type
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
    $subProductsConventions.Values | ForEach-Object {
        if (-not($_.RbacAssignment)) {
            $_.RbacAssignment = @()
        }
    }

    $results = @{
        TeamGroups              =   $teamGroupNames
        Aks                     =   @{
            Primary             =   $aksPrimaryCluster
            Failover            =   if($hasFailover) { $aksSecondaryCluster } else { $null }
            Namespace           =   $aksNamespace
            HelmReleaseName     =   $helmReleaseName
            RegistryName        =   'mrisoftwaredevops'
            ProdRegistryName    =   'mrisoftwaredevopsprod'
        }
        AppResourceGroup        =   $appReourceGroup
        DataResourceGroup       =   $dataResourceGroup
        CompanyName             =   $CompanyName
        ProductName             =   $productNameLower
        EnvironmentName         =   $EnvironmentName
        IsEnvironmentProdLike   =   $isEnvProdLike
        SubProducts             =   $subProductsConventions
        IsTestEnv               =   $isTestEnv
    }
    
    if ($AsHashtable) {
        $results
    }
    else {
        $results | ConvertTo-Json -Depth 100
    }
}
