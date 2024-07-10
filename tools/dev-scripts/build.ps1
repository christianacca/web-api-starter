    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $BuildNumber,
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
            Invoke-Exe { dotnet build -c Release }
            Invoke-Exe { dotnet test -c Release --no-build }
            Invoke-Exe { dotnet publish -c Release --no-build }
            ./tools/ci-cd/scripts/create-sql-migration-script.ps1
            Write-Information 'Create published artifacts directory'
            ./tools/ci-cd/scripts/create-published-artifacts-directory.ps1

            if ($DockerPush.IsPresent) {
                $convention = & "./tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
                $registryName = $convention.ContainerRegistries.Dev.ResourceName
                $registryInstance = "$registryName.azurecr.io"
                Write-Information "Conect to Azure Container Registry '$registryInstance'"
                Invoke-Exe { az acr login -n $registryName }
                ./tools/ci-cd/scripts/create-and-push-docker-images.ps1 -ImageRepo $registryInstance -BuildNumber $BuildNumber -PushImages -EA Stop   
            }
        }
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
