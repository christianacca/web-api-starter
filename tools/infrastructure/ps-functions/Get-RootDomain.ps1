function Get-RootDomain {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $CompanyDomain = 'mrisoftware'
    )
    begin {
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    }
    process {
        $isProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        if ($isProdLike) { 
            "$CompanyDomain.com"
        } else { 
            "redmz.$CompanyDomain.com"
        }
    }
}