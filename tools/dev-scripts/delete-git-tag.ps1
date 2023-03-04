<#
    .SYNOPSIS Deletes git tag locally and from the remote origin
    
    .EXAMPLE
    141..145 | ForEach-Object { ./tools/dev-scripts/delete-git-tag.ps1  "app-cc-troubleshoot-helm-upgrade-$_" }
#>


param(
    [string] $Name
)
git push --delete origin $Name
git tag -d $Name