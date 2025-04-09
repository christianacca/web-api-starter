function Get-TeamGroupNames {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        
        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )
    $productNameLower = $ProductName.ToLower()
    @{
        DevelopmentGroup    =   "sg.role.development.$productNameLower.$EnvironmentName".Replace('-', '')
        Tier1SupportGroup   =   "sg.role.supporttier1.$productNameLower.$EnvironmentName".Replace('-', '')
        Tier2SupportGroup   =   "sg.role.supporttier2.$productNameLower.$EnvironmentName".Replace('-', '')
    }
}