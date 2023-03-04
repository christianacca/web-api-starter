function Get-PublicHostName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName,

        [Parameter(Mandatory)]
        [string] $ProductName,

        [Parameter(Mandatory)]
        [string] $SubProductName,
    
        [switch] $IsMainUI
    )
    begin {
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
        . "$PSScriptRoot/Get-RootDomain.ps1"
    }
    process {
        $isProdLike = Get-IsEnvironmentProdLike $EnvironmentName
        $rootDomain = Get-RootDomain $EnvironmentName
        $productUrlSegment = ($isProdLike ? '.' : '-') + $ProductName
        $urlPrefix = $EnvironmentName.Replace('prod-', '')
        $subProductUrlSegment = $IsMainUI ? '' : "-$($SubProductName.ToLower())"
        
        '{0}{1}{2}.{3}' -f $urlPrefix, $subProductUrlSegment, $productUrlSegment, $rootDomain
    }
}