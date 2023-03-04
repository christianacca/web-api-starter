function Get-RootDomain {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName
    )
    begin {
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    }
    process {
        $isProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        if ($isProdLike) { 
            'mrisoftware.com' 
        } else { 
            'redmz.mrisoftware.com' 
        }
    }
}