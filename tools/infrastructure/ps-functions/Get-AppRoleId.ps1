function Get-AppRoleId {
    param(
        [Parameter(Mandatory)]
        [string] $AppRoleName,

        [Parameter(Mandatory)]
        [string] $ADAppName
    )
    begin {
        . "$PSScriptRoot/Get-Guid.ps1"
    }
    process {
        Get-Guid "$AppRoleName-$ADAppName"
    }
}