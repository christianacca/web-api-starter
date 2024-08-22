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

function Select-StringAfter {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ScriptBlock] $After,
    
        [switch] $IncludeAfter
    )
    begin {
        $found = $false
    }
    process {
        if ($found) {
            $InputObject
        } elseif (. $After) {
            $found = $true
            if ($IncludeAfter) {
                $InputObject
            }
        }
    }
}