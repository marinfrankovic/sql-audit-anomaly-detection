// Azure SQL logical server + database with server-level auditing streamed to
// Log Analytics (SQLSecurityAuditEvents table). Serverless GP tier for low cost.
@description('Logical server name (globally unique, lowercase).')
param serverName string
@description('Database name.')
param databaseName string
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('SQL administrator login.')
param sqlAdminLogin string
@secure()
@description('SQL administrator password.')
param sqlAdminPassword string
@description('Log Analytics workspace resource id.')
param logAnalyticsId string
@description('Optional client IP allowed through the SQL firewall.')
param clientIpAddress string = ''

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Allow Azure services (and the SQL VM / azd host running in Azure) to reach the server.
resource allowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Optional: allow the demo operator's workstation IP.
resource allowClient 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (!empty(clientIpAddress)) {
  parent: sqlServer
  name: 'AllowClientIp'
  properties: {
    startIpAddress: clientIpAddress
    endIpAddress: clientIpAddress
  }
}

// Serverless General Purpose database — auto-pauses to minimise PoC cost.
resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 34359738368 // 32 GB
    autoPauseDelay: 60
    minCapacity: json('0.5')
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Server-level auditing, targeting Azure Monitor (Log Analytics).
resource auditingSettings 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    isManagedIdentityInUse: false
    auditActionsAndGroups: [
      'BATCH_COMPLETED_GROUP'
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'DATABASE_PERMISSION_CHANGE_GROUP'
      'DATABASE_ROLE_MEMBER_CHANGE_GROUP'
      'SCHEMA_OBJECT_CHANGE_GROUP'
      'SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP'
    ]
  }
}

// When server auditing targets Azure Monitor, the diagnostic setting that ships the
// SQLSecurityAuditEvents category is placed on the server's *master* database.
resource masterDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = {
  parent: sqlServer
  name: 'master'
}

resource auditDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sqlAuditToLogAnalytics'
  scope: masterDb
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
    ]
  }
  dependsOn: [
    auditingSettings
  ]
}

// Database-level diagnostics (query performance / errors) for richer demo context.
resource dbDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sqlDbDiagnostics'
  scope: database
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
      {
        category: 'Errors'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
    ]
  }
}

output serverName string = sqlServer.name
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = database.name
output serverPrincipalId string = sqlServer.identity.principalId
