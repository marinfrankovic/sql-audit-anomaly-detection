// Key Vault storing PoC admin secrets. RBAC-authorization enabled (no access policies).
@description('Key Vault name (globally unique, <=24 chars).')
param name string
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Tenant id.')
param tenantId string = subscription().tenantId

@secure()
@description('Azure SQL admin password to store as a secret.')
param sqlAdminPassword string

@secure()
@description('VM local admin password to store as a secret.')
param vmAdminPassword string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource sqlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
    contentType: 'Azure SQL administrator password'
  }
}

resource vmSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'vm-admin-password'
  properties: {
    value: vmAdminPassword
    contentType: 'Windows SQL VM local admin password'
  }
}

output id string = keyVault.id
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
