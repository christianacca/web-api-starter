function Get-PbiAadSecurityGroupConvention {
    param(
        [Parameter(Mandatory)]
        [string] $ProductName,
        
        [ValidateSet('ff', 'dev', 'qa', 'rel', 'release', 'demo', 'staging', 'prod-na', 'prod-emea', 'prod-apac')]
        [string] $EnvironmentName = 'dev',

        [Parameter(Mandatory)]
        [Hashtable] $TeamGroupNames,
    
        [switch] $TeamGroupMemberOnly
    )

    Set-StrictMode -Version 'Latest'
    
    . "$PSScriptRoot/Get-IsEnvironmentProdLike.ps1"

    $productNameLower = $ProductName.ToLower()

    $isEnvProdLike = Get-IsEnvironmentProdLike $EnvironmentName
    $isTestEnv = $EnvironmentName -in 'ff', 'dev', 'qa', 'rel', 'release'

    $adPbiGroupNamePrefix = 'sg.365.pbi'
    $adPbiWksGroupNamePrefix = $('{0}.workspace.{1}.{2}' -f $adPbiGroupNamePrefix, $productNameLower, $EnvironmentName).Replace('-', '')
    $adPbiReportGroupNamePrefix = $('{0}.report.{1}.{2}' -f $adPbiGroupNamePrefix, $productNameLower, $EnvironmentName).Replace('-', '')
    $adPbiDatasetGroupNamePrefix = $('{0}.dataset.{1}.{2}' -f $adPbiGroupNamePrefix, $productNameLower, $EnvironmentName).Replace('-', '')
    $pbiGroup = @(switch ($EnvironmentName) {
        { $isTestEnv } {
            @{
                Name            = "$adPbiWksGroupNamePrefix.admin";
                PbiRole         = 'Admin'
                Member          = @{ Name = $TeamGroupNames.DevelopmentGroup; Type = 'Group' }
            }
        }
        'demo' {
            @{
                Name            = "$adPbiReportGroupNamePrefix.admin";
                PbiRole         = 'Admin'
                Member          = @{ Name = $TeamGroupNames.Tier2SupportGroup; Type = 'Group' }
            }
            @{
                Name            = "$adPbiDatasetGroupNamePrefix.admin";
                PbiRole         = 'Admin'
                Member          = @{ Name = $TeamGroupNames.Tier2SupportGroup; Type = 'Group' }
            }
            @{
                Name            = "$adPbiReportGroupNamePrefix.contributor";
                PbiRole         = 'Contributor'
                Member          = @(
                    @{ Name = $TeamGroupNames.DevelopmentGroup; Type = 'Group' }
                    @{ Name = $TeamGroupNames.Tier1SupportGroup; Type = 'Group' }
                    $TeamGroupMemberOnly ? @() : @{ Name = "$adPbiReportGroupNamePrefix.admin"; Type = 'Group' }
                )
            }
            @{
                Name            = "$adPbiDatasetGroupNamePrefix.contributor";
                PbiRole         = 'Contributor'
                Member          = @(
                    @{ Name = $TeamGroupNames.DevelopmentGroup; Type = 'Group' }
                    $TeamGroupMemberOnly ? @() : @{ Name = "$adPbiDatasetGroupNamePrefix.admin"; Type = 'Group' }
                )
            }
            @{
                Name            = "$adPbiDatasetGroupNamePrefix.viewer";
                PbiRole         = 'Viewer'
                Member          = @(
                    @{ Name = $TeamGroupNames.Tier1SupportGroup; Type = 'Group' }
                    $TeamGroupMemberOnly ? @() : @{ Name = "$adPbiDatasetGroupNamePrefix.contributor"; Type = 'Group' }
                )
            }
        }
        { $isEnvProdLike } {
            @{
                Name            = "$adPbiReportGroupNamePrefix.admin";
                PbiRole         = 'Admin'
                Member          = @{ Name = $TeamGroupNames.Tier2SupportGroup; Type = 'Group' }
            }
            @{
                Name            = "$adPbiDatasetGroupNamePrefix.admin";
                PbiRole         = 'Admin'
                Member          = @{ Name = $TeamGroupNames.Tier2SupportGroup; Type = 'Group' }
            }
            @{
                Name            = "$adPbiReportGroupNamePrefix.contributor";
                PbiRole         = 'Contributor'
                Member          = @(
                    @{ Name = $TeamGroupNames.Tier1SupportGroup; Type = 'Group' }
                    $TeamGroupMemberOnly ? @() : @{ Name = "$adPbiReportGroupNamePrefix.admin"; Type = 'Group' }
                )
            }
            @{
                Name            = "$adPbiDatasetGroupNamePrefix.viewer";
                PbiRole         = 'Viewer'
                Member          = @(
                    @{ Name = $TeamGroupNames.Tier1SupportGroup; Type = 'Group' }
                    $TeamGroupMemberOnly ? @() : @{ Name = "$adPbiDatasetGroupNamePrefix.admin"; Type = 'Group' }
                )
            }
        }
        Default {
            Write-Output @() -NoEnumerate
        }
    }) + @{
        Name            = "$adPbiWksGroupNamePrefix.app";
        PbiRole         = 'Admin'
        Member          = @()
    }

    $pbiGroup
}
