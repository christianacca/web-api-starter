[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $EnvironmentName,
    [string] $SubscriptionId,
    [switch] $AsHashtable
)
process {
    $vars = switch ($EnvironmentName) {
        ({ ($PSItem -in 'dev', 'qa', 'rel', 'release') -or ($PSItem -like 'demo*') }) {
            @{
                # cli-devops-shared-web-api-starter-arm
                clientId        =   'e18be585-830e-408d-bafa-fe4d41a5e52e'
                principalId     =   '48dcc51c-d6f6-4152-9161-9f8c40e4cc1e' # <- object id of the service prinicpal (aka enterprise application) backing the App registration
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        ({$PSItem -in 'staging', 'prod-na', 'prod'}) {
            @{
                # cli-nadevopsproduction-prod-web-api-starter-arm
                clientId        =   '6a3a29da-76bf-4ee2-b2fc-a65ccf22f33e'
                principalId     =   '4992b5ae-98ff-460c-ab58-7a6d5552dc53' # <- object id of the service prinicpal (aka enterprise application) backing the App registration
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-emea' {
            @{
                # cli-emeadevopsproduction-prod-web-api-starter-arm
                clientId        =   '3d7a904f-568d-4dbf-abbd-2b8edd4f2ce6'
                principalId     =   '15be43a5-09a7-4c08-ac38-e1d16a27d7b1' # <- object id of the service prinicpal (aka enterprise application) backing the App registration
                tenantId        =   '77806292-ec65-4665-8395-93cb7c9dbd36'
                subscriptionId  =   '402f88b4-9dd2-49e3-9989-96c788e93372'
            }
        }
        'prod-apac' {
            @{
                # cli-apacdevopsproduction-prod-web-api-starter-arm
                clientId        =   'beec650e-3408-4191-8e63-7098190a2e7b'
                principalId     =   '8ff2423c-e6ec-4643-8000-8063f624a8b9' # <- object id of the service prinicpal (aka enterprise application) backing the App registration
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
