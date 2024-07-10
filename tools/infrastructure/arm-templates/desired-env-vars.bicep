@description('List of environment variables that are required for this deployment')
param envVars array

@description('List of existing environment variables already deployed')
param existingEnvVars array

@description('(Optional) Name of environment variable that will be set that maintains the names of the environment variables to diff against the next deployment')
param metadataKeyName string = '__DeployMetadata__InfraVarKeys'

import { findFirstBy, unionBy } from 'utils.bicep'

// definition of environment variables is often split between infrastructure and application concerns. 
// because of this split of maintance, we need to ensure that when we set the desired state of environment vars here, we preserve
// the existing env vars that are maintained by other concerns. the following logic achieves this.


var previousEnvVarsKeys = split(findFirstBy(existingEnvVars, 'name', metadataKeyName).?value ?? '', ',')
var requiredEnvVarKeys = sort(map(envVars, ev => ev.name), (a, b) => a < b)
var obsoleteEnvKeys = union(
  [...filter(previousEnvVarsKeys, key => !contains(requiredEnvVarKeys, key))],
  empty(requiredEnvVarKeys) ? [metadataKeyName] : []
)

var metadataEnvVars = empty(requiredEnvVarKeys) ? [] : [{ 
  name: metadataKeyName, value: join(requiredEnvVarKeys, ',') 
}]

var desiredEnvVars = sort(
  filter(unionBy([...envVars, ...metadataEnvVars], existingEnvVars, 'name'), ev => !contains(obsoleteEnvKeys, ev.name)),
  (a, b) => a.name < b.name
)

output desiredEnvVars array = desiredEnvVars
