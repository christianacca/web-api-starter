function Get-CloudflareWafRuleExpr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string] $Path,
        [string] $HostHeader
    )
    begin {
        function GetPathExpr(
            [string] $Value
        ) {
            if ($Value.EndsWith('*')) {
                'starts_with(lower(http.request.uri.path), "{0}")' -f $Value.Substring(0, $Value.Length - 1)
            } elseif ($Value.StartsWith('*')) {
                'ends_with(lower(http.request.uri.path), "{0}")' -f $Value.Substring(1)
            } elseif ($Value.Contains('*')) {
                $pathSegments = $Value.Split('*')
                GetPathExpr ('{0}*' -f $pathSegments[0])
                GetPathExpr ('*{0}' -f $pathSegments[1])
            } else {
                'lower(http.request.uri.path) eq "{0}"' -f $Value.Substring(1)
            }
        }
    }
    process {
        $expressions = @(GetPathExpr $Path)
        if ($HostHeader) {
            $expressions = @(
                'http.host eq "{0}"' -f $HostHeader
            ) + $expressions
        }
        $result = $expressions -join ' and '
        [PsCustomObject]@{
            Path        = $Path
            Expression  = $expressions.Count -gt 1 ? "($result)" : $result
        }
    }
}