function Invoke-EnsureHttpSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ScriptBlock] $ScriptBlock
    )
    process {
        $response = Invoke-Command $ScriptBlock -EA Stop
        if ($response.StatusCode -gt 399 -or $response.StatusCode -lt 200) {
            throw "Problem executing AZ REST API. StatusCode: $($response.StatusCode); Content: $($response.Content)"
        }
        $response.Content
    }
}