function Get-IsEnvironmentProdLike {
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )
    process {
        $isProdLike = ($EnvironmentName -eq 'staging') -or ($EnvironmentName -like 'prod*') ? $true : $false
        $isProdLike
    }
}