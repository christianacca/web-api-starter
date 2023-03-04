function Get-AADGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string] $GroupName
    )
    begin {
        Set-StrictMode -Version 'Latest'
        $callerEA = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
    }
    process {
        try {
            $members = Get-AzADGroup -DisplayName $GroupName -EA Stop | Get-AzADGroupMember -EA Stop
            
            $members |
                Where-Object OdataType -eq '#microsoft.graph.user' |
                Select-Object UserPrincipalName, @{ N="Type"; E={ 'User' }}
            
            $members |
                Where-Object OdataType -eq '#microsoft.graph.servicePrincipal' |
                Select-Object @{ N="ApplicationId"; E={ $_.AppId }}, @{ N="Type"; E={ 'ServicePrincipal' }}
            
            $members |
                Where-Object OdataType -eq '#microsoft.graph.group' |
                Select-Object @{ N="Name"; E={ $_.DisplayName }}, @{ N="Type"; E={ 'Group' }}
        } 
        catch {
            Write-Error -ErrorRecord $_ -EA $callerEA
        }
    }
}
