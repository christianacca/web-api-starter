function Get-ArmOsChangeConflict {
    <#
      .SYNOPSIS
      Work out whether a failed ARM deployment failed only because a hosting plan's operating system can't be changed

      .DESCRIPTION
      Azure can't change the OS of an existing App Service plan (for example Windows Consumption to Flex Consumption, or
      back again) and fails the deployment with 'You cannot change the OS hosting your app'. The only way forward is to
      delete the app and plan and let the deployment re-create them.

      This function reads the error text printed by 'az deployment group create' and returns:
      * OnlyOsChange - $true when every error in the deployment is that OS change error. When any other error is present
        the caller must not delete anything
      * PlanNames    - the names of the hosting plans Azure reported the error against

      Returns $null when the text can't be read as a deployment error.

      .PARAMETER ErrorText
      The error output of a failed 'az deployment group create'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ErrorText
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        $osChangeMessage = 'You cannot change the OS hosting your app'
    }
    process {
        try {
            $start = $ErrorText.IndexOf('{')
            $end = $ErrorText.LastIndexOf('}')
            if ($start -lt 0 -or $end -le $start) {
                return $null
            }

            $parsed = try { $ErrorText.Substring($start, $end - $start + 1) | ConvertFrom-Json -Depth 50 } catch { $null }
            if (-not $parsed -or -not $parsed.PSObject.Properties['error']) {
                return $null
            }

            # the errors that matter are the leaves; the nodes above them only say that something below failed
            $leaves = [System.Collections.Generic.List[object]]::new()
            $visit = $null
            $visit = {
                param($node)
                $details = $node.PSObject.Properties['details']
                if ($details -and @($details.Value).Count -gt 0) {
                    foreach ($child in @($details.Value)) { & $visit $child }
                } else {
                    $leaves.Add($node)
                }
            }
            & $visit $parsed.error

            $osLeaves = @($leaves | Where-Object {
                $message = $_.PSObject.Properties['message']
                $message -and ([string]$message.Value).Contains($osChangeMessage)
            })

            $planNames = @($osLeaves | ForEach-Object {
                $target = $_.PSObject.Properties['target']
                if ($target -and ([string]$target.Value) -match 'Microsoft\.Web/(?:serverfarms|sites)/([^/]+)$') { $Matches[1] }
            } | Sort-Object -Unique)

            [PSCustomObject]@{
                OnlyOsChange    =   ($leaves.Count -gt 0 -and $osLeaves.Count -eq $leaves.Count)
                PlanNames       =   $planNames
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
