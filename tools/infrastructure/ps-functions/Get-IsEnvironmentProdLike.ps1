function Get-IsEnvironmentProdLike {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName
    )
    process {
        switch ($EnvironmentName) {
            { $_ -in 'ff', 'dev', 'qa', 'rel', 'release', 'demo'} {
                $false
            }
            Default {
                $true
            }
        }
    }
}