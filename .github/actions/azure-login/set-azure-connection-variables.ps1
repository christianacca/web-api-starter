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
                clientId        =   '312a0659-e472-4dda-9812-ea560c53512a'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   'b57ad61a-cc38-4b33-93d2-ed6920edea32'
            }
        }
        ({$PSItem -in 'staging', 'prod-na'}) {
            @{
                clientId        =   '312a0659-e472-4dda-9812-ea560c53512a'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   'b57ad61a-cc38-4b33-93d2-ed6920edea32'
            }
        }
        'prod-emea' {
            @{
                clientId        =   '312a0659-e472-4dda-9812-ea560c53512a'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   'b57ad61a-cc38-4b33-93d2-ed6920edea32'
            }
        }
        'prod-apac' {
            @{
                clientId        =   '312a0659-e472-4dda-9812-ea560c53512a'
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   'b57ad61a-cc38-4b33-93d2-ed6920edea32'
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
