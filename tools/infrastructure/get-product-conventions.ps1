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
        # TIP Use the following script to snapshpt the conventions which you can then compare with another snapshot
        # after making a change to the conventions:
        # New-Item ./out/infra-settings -Force -ItemType Directory | Out-Null; & ./tools/infrastructure/get-product-environment-names.ps1 | ForEach-Object { ./tools/infrastructure/get-product-conventions.ps1 -EnvironmentName $_ > ./out/infra-settings/$_.json }

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
            
            $githubAppConfig = & "$PSScriptRoot/get-product-github-app-config.ps1" -EnvironmentName $EnvironmentName
            
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
                    Github              =   @{ 
                        Type           = 'GithubApp'
                        Target         = 'Api'
                        Owner          = 'christianacca'
                        Repo           = 'web-api-starter'
                        AppId          = $githubAppConfig.AppId
                        InstallationId = $githubAppConfig.InstallationId
                        Pipeline       = $githubAppConfig.Pipeline
                    }
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
