[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $EnvironmentName
)

process {
    $config = switch ($EnvironmentName) {
        'dev' {
            @{
                AppId          = '2800205'
                InstallationId = '108147870'
            }
        }
        ({$PSItem -in 'qa', 'rel', 'release'}) {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'demo' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'demo-na' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'demo-emea' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'demo-apac' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'staging' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        ({$PSItem -in 'prod-na', 'prod'}) {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'prod-emea' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
        'prod-apac' {
            @{
                AppId          = $null
                InstallationId = $null
            }
        }
    }
    
    $config
}
