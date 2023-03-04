function Get-DotnetUserSecrets {
    <#
    .SYNOPSIS
    Returns dotnet project user secrets
      
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserSecretsId
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"

    }
    process {
        try
        {

            $result = @{ }
            $secretsFileContent = Invoke-Exe {
                dotnet user-secrets list --id $UserSecretsId
            }
            if ($secretsFileContent -eq 'No secrets configured for this application.') {
                $result
                return
            }

            $secretsFileContent | ForEach-Object {
                $keyValue = $_.Split('=')
                $key = $keyValue[0].Replace(':', '_').Trim()
                $value = (($keyValue | Select-Object -Last ($keyValue.Length - 1)) -join '=').Trim()
                $result[$key] = $value
            }
            $result
        }
        catch
        {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
