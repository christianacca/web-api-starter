function Select-StringUntil {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ScriptBlock] $Until
    )
    begin {
        $result = @()
        $found = $false
    }
    process {
        if (-not($found)) {
            $found = (. $Until)
            $result = $result + @($InputObject)
        }
    }
    end {
        $result
    }
}