function ConvertTo-StringData {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [HashTable]$InputObject,
        [switch] $SortKeys
    )
    $keys = $SortKeys ? ($InputObject.Keys | Sort-Object) : $InputObject.Keys
    $keys | ForEach-Object { ('"{0}={1}"' -f  $_, $InputObject[$_].ToString().Replace('"', '""')) }
}

function Join-Hashtable {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Hashtable[]] $InputObject
    )
    begin {
        $result = @{}
    }
    process {
        foreach ($hashtable in $InputObject) {
            foreach ($key in $hashtable.Keys) {
                if (-not $result.ContainsKey($key)) {
                    $result[$key] = $hashtable[$key]
                }
            }
        }
    }
    end {
        $result
    }
}

function Select-Hashtable {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Hashtable] $InputObject,

        [Parameter(Mandatory, Position = 0)]
        [ScriptBlock] $Selector
    )
    $InputObject.Keys | Where-Object $Selector |
            ForEach-Object -Begin { $tmp = @{} } -Process { $tmp[$_] = $InputObject[$_] } -End { $tmp }
}