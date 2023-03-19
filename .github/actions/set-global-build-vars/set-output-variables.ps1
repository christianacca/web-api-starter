[CmdletBinding()]
param(
    [string] $GitTagSuffix
)
begin {
    $prodReleaseBranchPrefix = 'release'
    $prodReleaseType = $prodReleaseBranchPrefix
    $tagDelimiter = '-'

    function Get-BuildType {
        param([string] $BuildTag)
        $BuildTag.StartsWith($prodReleaseBranchPrefix + $tagDelimiter) ? $prodReleaseType : 'ci'
    }

}
process {

    $vars = if ($env:GITHUB_REF_TYPE  -eq 'tag') {
        $refSegments = $env:GITHUB_REF_NAME -split $tagDelimiter
        $buildTag = ($refSegments | Select-Object -Skip 1) -join $tagDelimiter
        $buildType = Get-BuildType $buildTag
        $buildNumber = ($refSegments | Select-Object -Last 1) -split '_' | Select-Object -First 1
        $releaseNumber = if ($buildType -eq $prodReleaseType) {
            $refSegments | Select-Object -Skip 2 -First 1
        } else {
            '0.0'
        }
        @{
            buildNumber     =   $buildNumber
            buildTag        =   $buildTag
            buildType       =   $buildType
            buildVersion    =   "$releaseNumber.0.$buildNumber"
            createRelease   =   'false'
            gitTag          =   $env:GITHUB_REF_NAME
            runBuild        =   'false'
        }
    } else {
        $buildNumber = $env:GITHUB_RUN_NUMBER
        $buildTag = '{0}{1}{2}{3}' -f $env:GITHUB_REF_NAME.Replace('/', $tagDelimiter), $tagDelimiter, $buildNumber, ($env:GITHUB_RUN_ATTEMPT -eq '1' ? '' : "_$env:GITHUB_RUN_ATTEMPT")
        $buildType = Get-BuildType $buildTag
        $GitTagSuffix = !$GitTagSuffix ? 'app' : $GitTagSuffix

        $releaseNumber = if ($buildType -eq $prodReleaseType) {
            $env:GITHUB_REF_NAME -split '/' | Select-Object -Skip 1 -First 1
        } else {
            '0.0'
        }

        $createRelease = if($env:GITHUB_EVENT_NAME -in 'push', 'workflow_dispatch') {
            'true'
        } elseif ($env:GITHUB_EVENT_NAME -eq 'create') {
            $buildType -eq $prodReleaseType ? 'true' : 'false'
        } else {
            'false'
        }
        # note: if github actions ever adds branch filters for the 'create' event this `runBuild` variable can be removed
        $runBuild = $env:GITHUB_EVENT_NAME -eq 'create' ? $createRelease : 'true'

        @{
            buildNumber     =   $buildNumber
            buildTag        =   $buildTag
            buildType       =   $buildType
            buildVersion    =   "$releaseNumber.0.$buildNumber"
            createRelease   =   $createRelease
            gitTag          =   '{0}{1}{2}' -f $GitTagSuffix, $tagDelimiter, $buildTag
            runBuild        =   $runBuild
        }
    }

    $convention = & "./tools/infrastructure/get-product-conventions.ps1" -EnvironmentName dev -AsHashtable
    if ($vars.buildType -eq $prodReleaseType) {
        $vars.acrEnvironment = 'prod-artifacts'
        $vars.acrName = '{0}.azurecr.io' -f $convention.Aks.ProdRegistryName
    } else {
        $vars.acrEnvironment = 'dev'
        $vars.acrName = '{0}.azurecr.io' -f $convention.Aks.RegistryName
    }
    $vars
    $vars.Keys | ForEach-Object {
        ('{0}={1}' -f $_, $vars[$_]) >> $env:GITHUB_OUTPUT
    }
}
