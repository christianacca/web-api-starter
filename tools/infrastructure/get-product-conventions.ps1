<#
      .SYNOPSIS
      Returns the product conventions (resource names, settings, RBAC assignments, etc.) for a given environment.
      Output is a JSON string by default, or a hashtable when -AsHashtable is specified.

      .PARAMETER EnvironmentName
      The name of the environment to return conventions for. Use get-product-environment-names.ps1 to list valid values.

      .PARAMETER AsHashtable
      Return the conventions as a hashtable instead of a JSON string.

      .EXAMPLE
      ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev
    
      Description
      -----------
      Returns all product conventions for the dev environment as a JSON string.

      .EXAMPLE
      ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev > ./out/infra-settings/dev.json
    
      Description
      -----------
      Saves the conventions for the dev environment to a JSON file. Use the default JSON output (omit -AsHashtable)
      when you want to save to a file or pipe to another tool that expects JSON.

      .EXAMPLE
      ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName prod-na -AsHashtable | ForEach-Object { $_.ConfigStores.Current }
    
      Description
      -----------
      Returns the ConfigStores.Current section as a hashtable for the prod-na environment. EG:
      
      Name                           Value
      ----                           -----
      ResourceName                   appcs-was-prod
      ResourceGroupName              rg-shared-was-eastus
      HostName                       appcs-was-prod.azconfig.io
      ReplicaLocations               {uksouth, australiaeast}

      .EXAMPLE
      New-Item ./out/infra-settings -Force -ItemType Directory | Out-Null
      & ./tools/infrastructure/get-product-environment-names.ps1 | ForEach-Object {
          ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName $_ > ./out/infra-settings/$_.json
      }
    
      Description
      -----------
      Snapshots the conventions for all environments to individual JSON files under ./out/infra-settings/.
      Useful for comparing conventions before and after making changes.

      .EXAMPLE
      ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName dev -AsHashtable | ForEach-Object { $_.SubProducts.Values } | Select-Object -Property Type, ResourceName
    
      Description
      -----------
      Returns the Type and ResourceName of every sub-product for the dev environment. EG:
      
      Type             ResourceName
      ----             ------------
      StorageAccount   stpbireportwasdev
      AcaEnvironment   acaenv-was-dev-eus
      ManagedIdentity  id-was-dev-acr-pull
      AppInsights      appi-was-dev-eus
      SqlServer        sql-was-dev-eus
      SqlDatabase      sqldb-was-dev
      FunctionApp      func-was-dev-eus-internal-api
      AcaApp           ca-was-dev-eus-api
      TrafficManager   traf-was-dev-api
      AcaApp           ca-was-dev-eus-app
      TrafficManager   traf-was-dev-app
      KeyVault         kv-was-dev-eus

      .LINK
      ./tools/infrastructure/print-product-convention-table.ps1
      Use print-product-convention-table.ps1 to query a section of the conventions across ALL environments at once, returned as a formatted table or array.

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
        
        [switch] $AsHashtable
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "$PSScriptRoot/ps-functions/Get-ResourceConvention.ps1"
    }
    process {

        try {

            $environments = & "$PSScriptRoot/get-product-environment-names.ps1"
            if ($EnvironmentName -notin $environments) {
                throw "EnvironmentName '$EnvironmentName' is not valid. Valid values are: $($environments -join ', ')"
            }

            # we're deploying to eastus2 mainly because the eastus is often out of capacity for provisioning
            # Azure SQL databases. The eastus2 region is a good alternative.
            $envRegion = $EnvironmentName -split '-' | Select-Object -Skip 1 -First 1
            $azureRegion = if ($null -eq $envRegion -or $envRegion -eq 'na') {
                @{
                    Primary     =   @{ Name = 'eastus2'; Abbreviation = 'eus2' }
                    Secondary   =   @{ Name = 'centralus'; Abbreviation = 'cus' }
                }
            }
            
            $conventionsParams = @{
                CompanyName             =   'CLC Software'
                ProductName             =   'Web API Starter'
#                ProductAbbreviation     =   'was-cc'
                Domain                  = @{
                    TopLevelDomain      =   'co.uk' # <- default is 'com'
                    CompanyDomain       =   'codingdemo' # <- default is CompanyName lowercased with spaces removed
#                    DevTestSubDomain    =   'xyz' # <- default is 'devtest'. only applies when `SubDomainLevel` equals 3
#                    PreProdSubDomain    =   'xyz' # <- default is 'preprod'. only applies when `SubDomainLevel` equals 3
#                    ProdSubDomain       =   'xyz' # <- default is 'cloud'. only applies when `SubDomainLevel` equals 3
#                    ProductDomain       =   'xyz' # <- default is ProductAbbreviation
                    # example of 1 level 'na-api-product.company.com'
                    # example of 2 levels 'na-api.product.company.com', 'dev-api.product.company.com'
                    # example of 3 levels 'na-api.product.cloud.company.com', 'dev-api.product.devtest.company.com'
                    SubDomainLevel      =   1 # <- default is 3
                }
                EnvironmentName         =   $EnvironmentName
                SubProducts             =   [ordered]@{
                    PbiReportStorage    =   @{ 
                        Type                =   'StorageAccount'
                        AccountNamePrefix   =   'pbireport'
                        DefaultStorageTier  =   'Cool'
                        Usage               =   'Blob'
                    }
                    Aca                 =   @{
                        # set to $false when you want to deploy without first having to create a custom domain and SSL certificate
                        IsCustomDomainEnabled   =   $true
                        Type = 'AcaEnvironment'
                    }
                    AcrPull             =   @{ Type = 'ManagedIdentity' }
                    AppInsights         =   @{ Type = 'AppInsights' }
                    Sql                 =   @{ Type = 'SqlServer' }
                    Db                  =   @{ Type = 'SqlDatabase' }
                    InternalApi         =   @{ Type = 'FunctionApp'; StorageUsage = 'Queue' }
                    # IMPORTANT: 'Api' should match the name of the c# project in the solution, as this value is 
                    # used in create-and-push-docker-images.ps1 to determine part of the ACR repository name for the docker image for this project
                    Api                 =   @{
                        AdditionalManagedId = 'AcrPull'
                        # example of defining whitelist paths in WAF
#                        WafWhitelist    = @(
#                            @{
#                                Path            = '/api/pbireports/*/import', '/api/internal/*'
#                                RulesToSkip     = 'OWASP Core Ruleset'
#                                Type            = 'cloudflare'
#                            }
#                        )
                        Type                = 'AcaApp'
                    }
                    ApiTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'Api' }
                    ApiAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'Api' }
                    # example of an extended health check:
#                    ApiExtendedAvailabilityTest =   @{ Type = 'AvailabilityTest'; IsExtendedCheck = $true; Path = '/health-extended'; Target = 'Api' }
                    App                 = @{
                        AdditionalManagedId = 'AcrPull'
                        Type = 'AcaApp'
                    }
                    AppAvailabilityTest =   @{ Type = 'AvailabilityTest'; Target = 'App' }
                    AppTrafficManager   =   @{ Type = 'TrafficManager'; Target = 'App' }
                    KeyVault            =   @{ Type = 'KeyVault' }
#                     Web                 =   @{ Type = 'AcaApp'; IsMainUI = $true }
                }
                CliPrincipals           =   & "$PSScriptRoot/get-product-azure-connections.ps1" -PropertyName principalId
                Subscriptions           =   & "$PSScriptRoot/get-product-azure-connections.ps1" -PropertyName subscriptionId
                AzureRegion             =   $azureRegion
                Options                 = @{
                    # set to true if your product stores some/all of its configuration in azure configuration store service
                    DeployConfigStore       =   $true
                    # Azure container registry (ACR) service is usually a service shared by multiple apps and
                    # therefore maintained by other teams. However, to for the purposes of demo'ing this starter
                    # template we're going to deploy these here
                    DeployContainerRegistry =   $true
                    # Azure key vault for storing TLS certificates is usally a service shared by multiple apps in 
                    # the case of a central department managing DNS via say Cloudflare. Therefore a service that is
                    # maintained by other teams. However, to for the purposes of demo'ing this starter template
                    # we're going to deploy these here
                    DeployTlsCertKeyVault   =   $true
                }                
            }

            Get-ResourceConvention @conventionsParams -AsHashtable:$AsHashtable

            # If you need to override conventions, comment out the above line, and follow the example below...

#            $convention = Get-ResourceConvention @conventionsParams -AsHashtable
#
#            $convention.ContainerRegistries.Dev.ResourceGroupName = 'Container_Registry'
#            $convention.ContainerRegistries.Prod.ResourceGroupName = 'container-registry'
#
#            if ($AsHashtable) {
#                $convention
#            } else {
#                $convention | ConvertTo-Json -Depth 100
#            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
