[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $EnvironmentName,
    [string] $SubscriptionId
)
process {
    $vars = switch ($EnvironmentName) {
        ({$PSItem -in 'dev', 'qa', 'rel', 'release', 'demo'}) {
            @{
                clientId        =   '07cb941f-c07e-42b4-af68-54e0c453cb11'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        ({$PSItem -in 'staging', 'prod-na'}) {
            @{
                clientId        =   'f53508da-ac2f-4d4a-8023-a748f01b3a19'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-emea' {
            @{
                clientId        =   '37846e59-fc2d-4ffa-a4a9-6a4ec0ec698a'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-apac' {
            @{
                clientId        =   '99c721f9-953d-4f22-ad57-fc4f115b3c15'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
    }
    if ($SubscriptionId) {
        $vars.subscriptionId = $SubscriptionId
    }
    $vars.Keys | ForEach-Object {
        '::set-output name={0}::{1}' -f $_, $vars[$_]
    }
}
