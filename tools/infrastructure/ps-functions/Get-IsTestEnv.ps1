function Get-IsTestEnv {
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentName
    )
    process {
        $EnvironmentName -in 'ff', 'dev', 'qa', 'rel', 'release'
    }
}