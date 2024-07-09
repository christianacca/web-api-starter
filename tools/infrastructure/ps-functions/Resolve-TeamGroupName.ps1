function Resolve-TeamGroupName {
    param(
        [Parameter(Mandatory)]
        [string] $AccessLevel,

        [string] $SubProductName,

        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Alias('Convention')]
        [Hashtable] $InputObject
    )
    $parsedAccessLevel = $AccessLevel.Contains('/') ? ($AccessLevel -split '/')[1].Trim() : $AccessLevel

    $teamGroups = ($SubProductName ?? '') -in '', 'global' ? $InputObject.TeamGroups :$InputObject.SubProducts[$SubProductName].TeamGroups
    
    $searchTerm = switch ($parsedAccessLevel) {
        'development' { '*development*' }
        'support-tier-1' { '*tier1*' }
        'support-tier-2' { '*tier2*' }
    }
    $teamGroups.Values | Where-Object { $_ -like $searchTerm } | Select-Object -First 1
}