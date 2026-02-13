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
                Pipeline = @('dev')
            }
        }
        'qa' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa')
            }
        }
        ({$PSItem -in 'rel', 'release'}) {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'rel')
            }
        }
        'demo' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'demo')
            }
        }
        'demo-na' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'demo-na')
            }
        }
        'demo-emea' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'demo-emea')
            }
        }
        'demo-apac' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'demo-apac')
            }
        }
        'staging' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'staging')
            }
        }
        ({$PSItem -in 'prod-na', 'prod'}) {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'staging', 'prod-na')
            }
        }
        'prod-emea' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'staging', 'prod-emea')
            }
        }
        'prod-apac' {
            @{
                AppId          = $null
                InstallationId = $null
                Pipeline       = @('dev', 'qa', 'staging', 'prod-apac')
            }
        }
    }
    
    $config
}
