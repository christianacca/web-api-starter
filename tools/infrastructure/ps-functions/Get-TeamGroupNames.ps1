function Get-TeamGroupNames {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        
        [Parameter(Mandatory)]
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName
    )
    $productNameLower = $ProductName.ToLower()
    @{
        DevelopmentGroup    =   "sg.role.development.$productNameLower.$EnvironmentName".Replace('-', '')
        Tier1SupportGroup   =   "sg.role.supporttier1.$productNameLower.$EnvironmentName".Replace('-', '')
        Tier2SupportGroup   =   "sg.role.supporttier2.$productNameLower.$EnvironmentName".Replace('-', '')
    }
}