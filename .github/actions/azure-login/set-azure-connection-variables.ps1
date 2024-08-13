[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $EnvironmentName,
    [string] $SubscriptionId,
    [switch] $AsHashtable
)
process {
    $vars = switch ($EnvironmentName) {
        ({$PSItem -in 'dev', 'qa', 'rel', 'release', 'demo'}) {
            @{
                clientId        =   'e18be585-830e-408d-bafa-fe4d41a5e52e'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        ({$PSItem -in 'staging', 'prod-na'}) {
            @{
                clientId        =   '6a3a29da-76bf-4ee2-b2fc-a65ccf22f33e'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-emea' {
            @{
                clientId        =   '3d7a904f-568d-4dbf-abbd-2b8edd4f2ce6'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-apac' {
            @{
                clientId        =   'beec650e-3408-4191-8e63-7098190a2e7b'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
    }
    if ($SubscriptionId) {
        $vars.subscriptionId = $SubscriptionId
    }
    if ($AsHashtable) {
        $vars
    } else {
        $vars.Keys | ForEach-Object {
            ('{0}={1}' -f $_, $vars[$_]) >> $env:GITHUB_OUTPUT
        }
    }
}
