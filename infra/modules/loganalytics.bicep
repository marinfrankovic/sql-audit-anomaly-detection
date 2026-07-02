// Log Analytics workspace (central audit/telemetry sink). Optional Sentinel.
@description('Workspace name.')
param name string
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Enable Microsoft Sentinel (SecurityInsights) solution.')
param enableSentinel bool = false
@description('Retention in days. 90 so the preloaded 90-day demo history is queryable.')
param retentionInDays int = 90

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Microsoft Sentinel is simply the SecurityInsights solution linked to the workspace.
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = if (enableSentinel) {
  name: 'SecurityInsights(${workspace.name})'
  location: location
  tags: tags
  plan: {
    name: 'SecurityInsights(${workspace.name})'
    product: 'OMSGallery/SecurityInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: workspace.id
  }
}

output id string = workspace.id
output name string = workspace.name
output customerId string = workspace.properties.customerId
