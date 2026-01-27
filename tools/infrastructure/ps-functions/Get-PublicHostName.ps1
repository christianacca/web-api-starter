function Get-PublicHostName {
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
        
        [string] $TopLevelDomain = 'com',

        [Parameter(Mandatory)]
        [string] $CompanyDomain,
        
        [string] $DefaultRegion,
        
        [string] $DevTestSubDomain = 'devtest',
        [string] $PreProdSubDomain = 'preprod',
        [string] $ProdSubDomain = 'cloud',

        [Parameter(Mandatory)]
        [string] $ProductDomain,
        
        [string] $SubProductName = '',
        
        [ValidateRange(1, 3)]
        [int] $SubDomainLevel = 3,
    
        [switch] $IsMainUI
    )
    begin {
        . "$PSScriptRoot/Get-IsPublicHostNameProdLike.ps1"
    }
    process {
        $isProdLike = Get-IsPublicHostNameProdLike $EnvironmentName
        $isPreProd = $EnvironmentName -eq 'staging'

        # Validate DefaultRegion is provided when EnvironmentName is staging and SubDomainLevel is 3
        if ($isPreProd -and $SubDomainLevel -eq 3 -and [string]::IsNullOrWhiteSpace($DefaultRegion)) {
            throw "DefaultRegion parameter is required when EnvironmentName is 'staging' and SubDomainLevel is 3"
        }
        
        # Determine the root domain structure based on SubDomainLevel
        switch ($SubDomainLevel) {
            1 {
                # SubDomainLevel 1: No environment subdomain, dash separator
                $rootDomain = "$CompanyDomain.$TopLevelDomain"
                $productSeparator = '-'
            }
            2 {
                # SubDomainLevel 2: No environment subdomain, dot separator
                $rootDomain = "$CompanyDomain.$TopLevelDomain"
                $productSeparator = '.'
            }
            3 {
                # SubDomainLevel 3: With environment subdomain, dot separator
                $envSubdomain = if ($isPreProd) {
                    $PreProdSubDomain
                } elseif ($isProdLike) {
                    $ProdSubDomain
                } else {
                    $DevTestSubDomain
                }
                $rootDomain = "$envSubdomain.$CompanyDomain.$TopLevelDomain"
                $productSeparator = '.'
            }
        }
        
        $productUrlSegment = "$productSeparator$ProductDomain"
        $urlPrefix = if ($isPreProd -and $SubDomainLevel -eq 3) {
            $DefaultRegion
        } else {
            $EnvironmentName.Replace('prod-', '')
        }
        $subProductUrlSegment = $IsMainUI ? '' : "-$($SubProductName.ToLower())"
        
        '{0}{1}{2}.{3}' -f $urlPrefix, $subProductUrlSegment, $productUrlSegment, $rootDomain
    }
}