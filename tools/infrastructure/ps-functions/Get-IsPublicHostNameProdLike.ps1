function Get-IsPublicHostNameProdLike {
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )
    begin {
        . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"
    }
    process {
        $isProdLike = (Get-IsEnvironmentProdLike $EnvironmentName) -or $EnvironmentName -like 'demo*'
        $isProdLike
    }
}