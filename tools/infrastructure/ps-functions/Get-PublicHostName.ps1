function Get-PublicHostName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,
        
        [string] $TopLevelDomain = 'com',

        [Parameter(Mandatory)]
        [string] $CompanyDomain,

        [Parameter(Mandatory)]
        [string] $ProductDomain,
        
        [string] $SubProductName = '',
        
        [ValidateRange(2, 3)]
        [int] $SubDomainLevel = 3,
    
        [switch] $IsMainUI
    )
    begin {
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    }
    process {
        $isProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        $rootDomain = if ($isProdLike -or $SubDomainLevel -eq 2) {
            "$CompanyDomain.$TopLevelDomain"
        } else {
            "devtest.$CompanyDomain.$TopLevelDomain"
        }
        $productUrlSegment = ($isProdLike -and $SubDomainLevel -eq 3 ? '.' : '-') + $ProductDomain
        $urlPrefix = $EnvironmentName.Replace('prod-', '')
        $subProductUrlSegment = $IsMainUI ? '' : "-$($SubProductName.ToLower())"
        
        '{0}{1}{2}.{3}' -f $urlPrefix, $subProductUrlSegment, $productUrlSegment, $rootDomain
    }
}