    [CmdletBinding()]
    param(
        [string] $BuildNumber = '0.0.1',
        [string] $RegistryName = 'mrisoftwaredevops',
        [switch] $DockerPush
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        . "./tools/infrastructure/ps-functions/Invoke-Exe.ps1"
    }
    process {
        try {
            Invoke-Exe { 
                dotnet build -c Release
                dotnet test -c Release --no-build
                dotnet publish -c Release --no-build
            }
            ./tools/ci-cd/scripts/create-sql-migration-script.ps1
            Write-Information 'Create published artifacts directory'
            ./tools/ci-cd/scripts/create-published-artifacts-directory.ps1

            if ($DockerPush.IsPresent) {
                Write-Information 'Conect to Azure Container Registry'
                Invoke-Exe { az acr login -n $RegistryName }
                ./tools/ci-cd/scripts/create-and-push-docker-images.ps1 -ImageRepo "$RegistryName.azurecr.io" -BuildNumber $BuildNumber -EA Stop   
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
