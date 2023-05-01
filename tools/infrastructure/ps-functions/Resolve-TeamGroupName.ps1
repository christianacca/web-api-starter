function Resolve-TeamGroupName {
    param(
        [Parameter(Mandatory)]
        [string] $AccessLevel,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )
    $parsedAccessLevel = $AccessLevel.Contains('/') ? ($AccessLevel -split '/')[1].Trim() : $AccessLevel
    
    switch ($parsedAccessLevel) {
        'development' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*development*').Name }
        'support-tier-1' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*tier1*').Name }
        'support-tier-2' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*tier2*').Name }
    }
}