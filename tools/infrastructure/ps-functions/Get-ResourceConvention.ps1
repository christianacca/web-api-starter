function Get-ResourceConvention {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        [string] $ProductAbbreviation,
        
        [hashtable] $Domain = @{},
        
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [Parameter(Mandatory)]
        [string] $CompanyName,
        [string] $CompanyAbbreviation,

        [Collections.Specialized.OrderedDictionary] $SubProducts = @{},

        [switch] $SeperateDataResourceGroup,
    
        [switch] $AsHashtable
    )
    
    Set-StrictMode -Off # allow reference to non-existant object properties to keep script readable

    . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    . "$PSScriptRoot/Get-PublicHostName.ps1"
    . "$PSScriptRoot/Get-PbiAadSecurityGroupConvention.ps1"
    . "$PSScriptRoot/Get-StorageRbacAccess.ps1"
    . "$PSScriptRoot/Get-TeamGroupNames.ps1"
    . "$PSScriptRoot/Get-UniqueString.ps1"
    . "$PSScriptRoot/Select-StringUntil.ps1"

    $failoverEnvironmnets = 'qa', 'rel', 'release', 'prod-emea', 'prod-apac', 'prod-na'
    $hasFailover = if ($EnvironmentName -in $failoverEnvironmnets) { $true } else { $false }

    if(-not($ProductAbbreviation)) {
        $ProductAbbreviation = -join ($ProductName -split ' ' | ForEach-Object { $_[0].ToString().ToLower() })
    } else {
        $ProductAbbreviation = $ProductAbbreviation.ToLower()
    }
    if(-not($CompanyAbbreviation)) {
        $CompanyAbbreviation = ($CompanyName -split ' ')[0].ToLower()
    } else {
        $CompanyAbbreviation = $CompanyAbbreviation.ToLower()
    }
    
    $Domain.CompanyDomain = $Domain.CompanyDomain ?? $CompanyName.Replace(' ', '').ToLower()
    $Domain.ProductDomain = $Domain.ProductDomain ?? $ProductAbbreviation

    # for full abreviations see CAF list see: https://www.jlaundry.nz/2022/azure_region_abbreviations/
    # for listing of which azure service are available in which regions see: https://www.azurespeed.com/Information/AzureRegions
    $azureRegions = switch ($EnvironmentName) {
        'prod-emea' {
            @{ Name = 'uksouth'; Abbreviation = 'uks' }, @{ Name = 'ukwest'; Abbreviation = 'ukw' }
        }
        'prod-apac' {
            @{ Name = 'australiaeast'; Abbreviation = 'ae' }
            @{ Name = 'australiasoutheast'; Abbreviation = 'ase' }
            # australiasoutheast is not available in azure container apps; this is the closest alternative region to australiaeast
            @{ Name = 'southeastasia'; Abbreviation = 'sea' }
        }
        Default {
            @{ Name = 'eastus'; Abbreviation = 'eus' }, @{ Name = 'westus'; Abbreviation = 'wus' }
        }
    }

    $teamGroupNames = Get-TeamGroupNames $ProductAbbreviation $EnvironmentName

    $azurePrimaryRegion = $azureRegions[0]
    $azureSecondaryRegion = $azureRegions[1]
    $azureSecondaryAltRegion = $azureRegions[2]

    $isEnvProdLike = Get-IsEnvironmentProdLike $EnvironmentName
    $isTestEnv = $EnvironmentName -in 'ff', 'dev', 'qa', 'rel', 'release'
    $isScaleToZeroEnv = $EnvironmentName -in 'ff', 'dev', 'staging'
    
    if ($isScaleToZeroEnv -and $hasFailover) {
        throw 'Scale to zero environments cannot have failover. This is because the primary has to be tested for availability before the failover can be promoted, and therefore will need at least one container to serve traffic.'
    }

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

    $appInstance = '{0}-{1}' -f $ProductAbbreviation, $EnvironmentName
    $appResourceGroupName = 'rg-{0}-{1}-{2}' -f $EnvironmentName, $ProductAbbreviation, $azurePrimaryRegion.Name
    $appReourceGroup = @{
        ResourceName        =   $appResourceGroupName
        ResourceLocation    =   $azurePrimaryRegion.Name
        UniqueString        =   Get-UniqueString $appResourceGroupName
        RbacAssignment      =   $resourceGroupRbac
    }
    
    $dataResourceGroup = if ($SeperateDataResourceGroup) {
        @{
            RbacAssignment      =   $resourceGroupRbac
            ResourceName        =   'rg-{0}-{1}-{2}-data' -f $EnvironmentName, $ProductAbbreviation, $azurePrimaryRegion.Name
            ResourceLocation    =   $azurePrimaryRegion.Name
        }
    } else {
        $appReourceGroup
    }

    $managedIdentityNamePrefix = "id-$appInstance"

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
                $sqlDbName = ('{0}{1}{2}01' -f $CompanyAbbreviation, $EnvironmentName, $ProductAbbreviation).Replace('-', '')
                $sqlPrimaryName = '{0}{1}' -f $sqlDbName, $azurePrimaryRegion.Name
                $adSqlGroupNamePrefix = "sg.arm.sql.$sqlDbName"
                $sqlAdAdminGroupName = "$adSqlGroupNamePrefix.admin"

                switch ($spInput.Type) {
                    'SqlServer' {
                        $sqlPrimaryServer = @{
                            ResourceName        =   $sqlPrimaryName
                            ResourceLocation    =   $azurePrimaryRegion.Name
                            DataSource          =   $hasFailover ? "tcp:$sqlDbName-fg.database.windows.net,1433" : "tcp:$sqlPrimaryName.database.windows.net,1433"
                        }
                        $sqlFailoverServer = @{
                            ResourceName        =   '{0}{1}' -f $sqlDbName, $azureSecondaryRegion.Name
                            ResourceLocation    =   $azureSecondaryRegion.Name
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
                            ResourceLocation        =   $azurePrimaryRegion.Name
                            Type                    =   $spInput.Type
                        }
                    }
                }
            }
            'FunctionApp' {
                $funcResourceName = 'func-{0}-{1}-{2}' -f $CompanyAbbreviation, $appInstance, $componentName.ToLower()
                $funcHostName = $spInput.HasCustomDomain ? `
                    (Get-PublicHostName $EnvironmentName @Domain -SubProductName $componentName) : `
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
            'AcaEnvironment' {
                $acaEnvNameTemplate = 'cae-{0}-{1}'
                $acaSecondaryRegion = $azureSecondaryAltRegion ?? $azureSecondaryRegion
                $acaEnvPrimary = @{
                    ResourceName        =   $acaEnvNameTemplate -f $appInstance, $azurePrimaryRegion.Abbreviation
                    ResourceLocation    =   $azurePrimaryRegion.Name
                }
                $acaEnvFailover = @{
                    ResourceName        =   $acaEnvNameTemplate -f $appInstance, $acaSecondaryRegion.Abbreviation
                    ResourceLocation    =   $acaSecondaryRegion.Name
                }
                @{
                    Primary             = $acaEnvPrimary
                    Failover            = if ($hasFailover) { $acaEnvFailover } else { $null }
                    Type                =   $spInput.Type
                }
            }
            'AcaApp' {
                $isMainUI = $spInput.IsMainUI ?? $false
                $oidcAppProductName = $spInput.OidcAppProductName ?? $ProductName
                $oidcAppName = '{0}{1} ({2})' -f $oidcAppProductName, ($isMainUI ? '' : ' API'), $EnvironmentName
                $acaEnv = $subProductsConventions[$spInput.AcaEnv ?? 'Aca']

                $managedId = @{
                    Primary     = '{0}-{1}' -f $managedIdentityNamePrefix, $componentName.ToLower()
                }
                if ($spInput.AdditionalManagedId) {
                    @($spInput.AdditionalManagedId) | ForEach-Object {
                        $managedId[$_] = $subProductsConventions.$_.ResourceName
                    }    
                }
                
                $acaShareSettings = @{
                    DefaultHealthPath   =   '/health'
                    MaxReplicas         =   switch ($EnvironmentName) {
                        'dev' {
                            2 # optimize for spend
                        }
                        Default {
                            6 # somewhat arbitrary limit here so adjust as needed
                        }
                    }
                }

                $acaAppNameTemplate = 'ca-{0}-{1}-{2}'
                $acaIngressHostnameTemplate = '{0}.ACA_ENV_DEFAULT_DOMAIN'
                
                $primaryAcaResourceName = $acaAppNameTemplate -f $appInstance, $azurePrimaryRegion.Abbreviation, $componentName.ToLower()
                $acaAppPrimary = @{
                    ResourceName        =   $primaryAcaResourceName
                    ResourceLocation    =   $azurePrimaryRegion.Name
                    AcaEnvResourceName  =   $acaEnv.Primary.ResourceName
                    IngressHostname     =   $acaIngressHostnameTemplate -f $primaryAcaResourceName
                    MinReplicas         =   switch ($EnvironmentName) {
                        { $_ -like 'prod-*' } {
                            3 # required for zone availability resillency
                        }
                        Default {
                            # for environemnts NOT scaling to zero, then choice of min replicas is based on whether failover is configured:
                            # - failover configured - 1 replica and use failover cluster to maintain resillency
                            # - no failover configured - use 2 replicas for resillency (ideally combined with zone redundancy)
                            $isScaleToZeroEnv ? 0 : $hasFailover ? 1 : 2
                        }
                    }
                } + $acaShareSettings

                $acaSecondaryRegion = $azureSecondaryAltRegion ?? $azureSecondaryRegion
                $failoverAcaResourceName = $acaAppNameTemplate -f $appInstance, $acaSecondaryRegion.Abbreviation, $componentName.ToLower()
                $acaAppFailover = @{
                    ResourceName        =   $failoverAcaResourceName
                    ResourceLocation    =   $acaSecondaryRegion.Name
                    AcaEnvResourceName  =   $acaEnv.Failover.ResourceName
                    IngressHostname     =   $acaIngressHostnameTemplate -f $failoverAcaResourceName
                    MinReplicas         =   0 # make failover passive node (ie traffic not sent to it unless primary fails)
                } + $acaShareSettings

                $imageRepositoryPrefix = $ProductName.ToLower().Replace(' ', '-')
                @{
                    Primary                 =   $acaAppPrimary
                    Failover                =   if ($hasFailover) { $acaAppFailover } else { $null }
                    DefaultHealthPath       =   $acaShareSettings.DefaultHealthPath
                    ImageName               =   '{0}/{1}' -f $imageRepositoryPrefix, $componentName.ToLower()
                    ImageRepositoryPrefix   =   $imageRepositoryPrefix
                    ManagedIdentity         =   $managedId
                    HostName                =   Get-PublicHostName $EnvironmentName @Domain -SubProductName $componentName -IsMainUI:$isMainUI
                    OidcAppName             =   $oidcAppName
                    TrafficManagerPath      =   $acaShareSettings.DefaultHealthPath
                    TrafficManagerProtocol  =   'HTTPS'
                    Type                    =   $spInput.Type
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

                $availabilityFriendlyName = '{0} {1} - {2} health check' -f $ProductAbbreviation.ToUpper(), $spInput.Target, $nameQualifier

                @{
                    Enabled                     =   !$isScaleToZeroEnv
                    Frequency                   =   $availabilityTestFrequency
                    Locations                   =   $testLocations
                    MetricAlert                 =   @{
                        Description             =   'Alert rule for availability test "{0}"' -f $availabilityFriendlyName
                        Enabled                 =   !$isScaleToZeroEnv
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
                $targetSubProduct = $subProductsConventions[$spInput.Target]
                
                $tmEndpoints = switch($targetSubProduct.Type) {
                    'AcaApp' {
                        @{
                            Name                =   $targetSubProduct.Primary.ResourceName
                            Target              =   $targetSubProduct.Primary.IngressHostname
                            Priority            =   1
                        }
                        if ($hasFailover) {
                            @{
                                Name                =   $targetSubProduct.Failover.ResourceName
                                Target              =   $targetSubProduct.Failover.IngressHostname
                                Priority            =   2
                            }
                        }
                    }
                    default {
                        throw 'Traffic manager convention not yet defined'
                    }
                }

                $tmEndpoints | Where-Object Priority -eq 1 | ForEach-Object {
                    $_.EndpointLocation = $azurePrimaryRegion.Name
                    # health probe monitoring only makes sense if traffic can be routed to a failover cluster in the event the primary becomes unavailable.
                    # therefore when there is no failover, disable health probe (AlwaysServe='Enabled').
                    $_.AlwaysServe =   $hasFailover ? 'Disabled' : 'Enabled'
                }

                $tmEndpoints | Where-Object Priority -eq 2 | ForEach-Object {
                    $_.EndpointLocation = $azureSecondaryRegion.Name
                    # disable health probe (AlwaysServe='Enabled') for a failover endpoint, because:
                    # 1) to allow failover to scale to zero / idle (when this is an option)
                    # 2) it doesn't really make sense to test for availability of the failover cluster: if the primary, which is monitored, is marked as 
                    #    unavailable, then the failover is the only option to try and serve the traffic regardless of it's state
                    $_.AlwaysServe = 'Enabled'
                }

                $tmProtocol = $targetSubProduct.TrafficManagerProtocol ?? 'HTTP'
                $targetDomainParts = $targetSubProduct.HostName.Split('.') | Select-StringUntil { $_ -like "*$($Domain.ProductDomain)*" }
                @{
                    ResourceName        =   $targetDomainParts -join '-'
                    Path                =   $targetSubProduct.TrafficManagerPath
                    Port                =   $tmProtocol -eq 'HTTP' ? 80 : 443
                    Protocol            =   $tmProtocol
                    Endpoints           =   @() + $tmEndpoints
                    Type                =   $spInput.Type
                }
            }
            'Pbi' {
                $pbiTeamGroupNames = Get-TeamGroupNames -ProductName "$ProductAbbreviation-Pbi" -EnvironmentName $EnvironmentName
                $pbiTeamAadConventionParams = @{
                    ProductName         =   $ProductAbbreviation
                    EnvironmentName     =   $EnvironmentName
                    TeamGroupNames      =   $pbiTeamGroupNames
                    TeamGroupMemberOnly =   $true
                }
                $pbiTeamGroupMembership = Get-PbiAadSecurityGroupConvention @pbiTeamAadConventionParams | ForEach-Object { [PsCustomObject]$_ }
                $pbiGroups = Get-PbiAadSecurityGroupConvention $ProductAbbreviation $EnvironmentName $teamGroupNames | ForEach-Object {
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
    
    $prodSubscriptiondId = '4c98c256-bc60-40ba-8bcb-81ae94ac52d4'
    $containerRegistryNamePrefix = $CompanyName.Replace(' ', '').ToLower()
    $containerRegistryProd = @{
        ResourceName        =   "${containerRegistryNamePrefix}devopsprod"
        ResourceGroupName   =   'container-registry'
        SubscriptionId      =   $prodSubscriptiondId
    }
    $containerRegistryDev = @{
        ResourceName        =   "${containerRegistryNamePrefix}devops"
        ResourceGroupName   =   'Container_Registry'
        SubscriptionId      =   'c398eb55-b057-45f9-8fe3-cfb0034418f5'
    }
    $containerRegistries = @{
        Available   = $isEnvProdLike ? @($containerRegistryProd) : @($containerRegistryProd, $containerRegistryDev)
        Prod        = $containerRegistryProd
        Dev         = $containerRegistryDev
    }

    $sharedKeyVaultLocation = 'eastus'
    $sharedKeyVault = @{
        ResourceName            =   'kv-{0}-shared' -f $ProductAbbreviation
        ResourceGroupName       =   'rg-shared-{0}-{1}' -f $ProductAbbreviation, $sharedKeyVaultLocation
        ResourceLocation        =   $sharedKeyVaultLocation
        SubscriptionId          =   $prodSubscriptiondId
        EnablePurgeProtection   =   $false # consider enabling this for your workloads
    }
    
    $devCert = @{
        KeyVault        =   $sharedKeyVault + @{}
        ResourceName    =   @(
            (Get-PublicHostName dev @Domain).Split('.') | Select-Object -Skip 1
            'wildcardcert'
        ) -join '-'
    }
    $prodCert = @{
        KeyVault        =   $sharedKeyVault + @{}
        ResourceName    =   @(
            (Get-PublicHostName prod-na @Domain).Split('.') | Select-Object -Skip 1
            'wildcardcert'
        ) -join '-'
    }

    $results = @{
        TeamGroups              =   $teamGroupNames
        AppResourceGroup        =   $appReourceGroup
        Company                 =   @{
            Abbreviation    =   $CompanyAbbreviation
            Name            =   $CompanyName
        }
        ContainerRegistries     =   $containerRegistries
        DataResourceGroup       =   $dataResourceGroup
        EnvironmentName         =   $EnvironmentName
        IsEnvironmentProdLike   =   $isEnvProdLike
        Product                 =   @{
            Abbreviation    =   $ProductAbbreviation
            Name            =   $ProductName
        }
        SubProducts             =   $subProductsConventions
        TlsCertificates         =   @{
            Current         =   $isEnvProdLike ? $prodCert : $devCert
            Dev             =   $devCert
            Prod            =   $prodCert
        }
        IsTestEnv               =   $isTestEnv
    }
    
    if ($AsHashtable) {
        $results
    }
    else {
        $results | ConvertTo-Json -Depth 100
    }
}
