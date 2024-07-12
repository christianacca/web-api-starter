function ConvertTo-StringData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [HashTable]$InputObject,
        [switch] $SortKeys
    )
    process {
        $keys = $SortKeys ? ($InputObject.Keys | Sort-Object) : $InputObject.Keys
        $keys | ForEach-Object { ('"{0}={1}"' -f  $_, $InputObject[$_].ToString().Replace('"', '""')) }
    }
}