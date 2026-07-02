// Read-only AI Analyst API — Linux Consumption Python Function App.
// Uses a system-assigned managed identity to call Azure OpenAI and to query
// Log Analytics. No secrets are stored in code or app settings.
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Function App name.')
param functionAppName string
@description('Storage account name (function runtime).')
param storageAccountName string
@description('Application Insights name.')
param appInsightsName string
@description('App Service (Consumption) plan name.')
param appServicePlanName string
@description('Log Analytics workspace resource id (App Insights + role scope).')
param logAnalyticsId string
@description('Log Analytics workspace name (for Logs Reader role scope).')
param logAnalyticsName string
@description('Log Analytics workspace customer (GUID) id for the Logs query client.')
param logAnalyticsCustomerId string
@description('Azure OpenAI endpoint (empty if OpenAI disabled).')
param openAiEndpoint string = ''
@description('Azure OpenAI account name (for role assignment). Empty if disabled.')
param openAiAccountName string = ''
@description('Azure OpenAI deployment name.')
param openAiDeploymentName string = 'gpt-4o-mini'

var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893' // Log Analytics Reader

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsId
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  // azd uses this tag to match the service in azure.yaml and deploy the code.
  tags: union(tags, { 'azd-service-name': 'aianalyst' })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}' }
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}' }
        { name: 'WEBSITE_CONTENTSHARE', value: toLower(functionAppName) }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'ENABLE_ORYX_BUILD', value: 'true' }
        // AI Analyst configuration (no secrets — managed identity is used).
        { name: 'AZURE_OPENAI_ENDPOINT', value: openAiEndpoint }
        { name: 'AZURE_OPENAI_DEPLOYMENT', value: openAiDeploymentName }
        { name: 'AZURE_OPENAI_API_VERSION', value: '2025-04-01-preview' }
        { name: 'LOG_ANALYTICS_WORKSPACE_ID', value: logAnalyticsCustomerId }
      ]
    }
  }
}

// Storage access for the function runtime (identity-based where possible).
resource storageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Read-only access to Log Analytics for the AI Analyst (query only).
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}
resource logReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, functionApp.id, logAnalyticsReaderRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services OpenAI User on the OpenAI account (only when provided).
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!empty(openAiAccountName)) {
  name: openAiAccountName
}
resource openAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(openAiAccountName)) {
  name: guid(functionApp.id, openAiUserRoleId, openAiAccountName)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionPrincipalId string = functionApp.identity.principalId
