@description('The name of the logical server.')
param serverName string = '${resourceGroup().name}-sql'

@description('The name of the database.')
param databaseName string = '${serverName}-db'

@description('Location for all resources.')
param location string = resourceGroup().location

resource database 'Microsoft.Sql/servers/databases@2021-05-01-preview' = {
  name: '${serverName}/${databaseName}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}
