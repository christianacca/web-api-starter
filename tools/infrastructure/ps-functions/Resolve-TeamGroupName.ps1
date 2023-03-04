function Resolve-TeamGroupName {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('development', 'support-tier-1', 'support-tier-2')]
        [string] $AccessLevel,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )
    switch ($AccessLevel) {
        'development' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*development*').Name }
        'support-tier-1' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*tier1*').Name }
        'support-tier-2' { ($InputObject.Ad.AadSecurityGroup | Where-Object Name -like '*tier2*').Name }
    }
}