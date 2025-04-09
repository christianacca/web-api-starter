function Get-PublicHostName {
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
        
        [string] $TopLevelDomain = 'com',

        [Parameter(Mandatory)]
        [string] $CompanyDomain,
        
        [string] $NonProdSubDomain = 'devtest',

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
        $NonProdSubDomain = $NonProdSubDomain -eq 'UseProductDomain' ? '' : $NonProdSubDomain
        
        $isProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        $rootDomain = if ($isProdLike -or $SubDomainLevel -eq 2 -or $NonProdSubDomain -eq '') {
            "$CompanyDomain.$TopLevelDomain"
        } else {
            "$NonProdSubDomain.$CompanyDomain.$TopLevelDomain"
        }
        $productUrlSegment = ($NonProdSubDomain -eq '' -or($isProdLike -and $SubDomainLevel -eq 3) ? '.' : '-') + $ProductDomain
        $urlPrefix = $EnvironmentName.Replace('prod-', '')
        $subProductUrlSegment = $IsMainUI ? '' : "-$($SubProductName.ToLower())"
        
        '{0}{1}{2}.{3}' -f $urlPrefix, $subProductUrlSegment, $productUrlSegment, $rootDomain
    }
}