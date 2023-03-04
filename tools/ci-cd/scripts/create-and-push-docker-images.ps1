[CmdletBinding()]
param(
    [string] $ImageRepo = 'mrisoftwaredevops.azurecr.io',
    [Parameter(Mandatory)] 
    [string] $BuildNumber,
    [switch] $PushImages
)
begin {
    Set-StrictMode -Version 'Latest'
    $callerEA = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'

    $imagePrefix = 'web-api-starter'

    function Invoke-Exe {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory, ValueFromPipeline)]
            [string] $Command
        )
        process {
            Write-Information "Executing: $Command"
            if ($PSCmdlet.ShouldProcess($Command)) {
                Invoke-Expression $Command
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Command failed with exit code $LASTEXITCODE; Cmd: $Command"
            }
        }
    }
}
process {
    try {
        if(-not(Test-Path -Path ./publish/**/*.dll) ) {
            'No projects found in the publish folder'
            return
        }

        Get-ChildItem ./publish -Directory |
            Where-Object { Get-ChildItem $_.FullName -Filter 'Dockerfile' } |
            Select-Object -Expand Name |
            ForEach-Object {
                # typically the first part of a project name is either MRI or the name of the solution;
                # either is redundant given the image prefix provides sufficient qualification
                $parts = $_.ToLower() -split '\.'
                $skip = if ($parts.Length -eq 1) { 0 } else { 1 }
                $service = ($parts | Select-Object -Skip $skip)  -join '-'
                [PsCustomObject]@{
                    DockerFile  =   "./publish/$_/Dockerfile"
                    Context     =   "./publish/$_"
                    Tags        =   @(
                        ('{0}/{1}/{2}:{3}' -f $ImageRepo, $imagePrefix, $service, $BuildNumber)
                        ('{0}/{1}/{2}:{3}' -f $ImageRepo, $imagePrefix, $service, 'latest')
                    )
                }
            } | 
            Tee-Object -Variable dockerBuilds |
            ForEach-Object {
                "docker build -f $($_.DockerFile)  $($_.Context) -t $($_.Tags | Join-String -Separator ' -t ')"
            } |
            Invoke-Exe
        
        if ($PushImages) {
            $dockerBuilds | Select-Object -ExpandProperty Tags | ForEach-Object { "docker push $_" } | Invoke-Exe    
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -EA $callerEA
    }
}
