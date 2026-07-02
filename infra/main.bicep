// =============================================================================
//  SQL Auditing & User Behavior Anomaly Detection PoC — main deployment
//  Scope: subscription (creates the resource group, then deploys all resources)
//  Deploys: Log Analytics, Key Vault, Azure SQL (server+db+auditing),
//           Windows SQL VM, Azure Monitor Agent + DCR, Action Group,
//           Log Search Alerts and an Azure Workbook.
// =============================================================================
targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment (used for tagging and name generation).')
param environmentName string

@minLength(1)
@description('Primary Azure region for all resources. PoC targets Sweden Central.')
param location string = 'swedencentral'

@description('Name of the resource group to create/use.')
param resourceGroupName string = 'rg-sqlaudit-demo'

@minLength(3)
@description('Local administrator username for the Windows SQL VM.')
param adminUsername string = 'sqlvmadmin'

@secure()
@minLength(12)
@description('Local administrator password for the Windows SQL VM. Stored in Key Vault.')
param adminPassword string

@minLength(3)
@description('Azure SQL administrator login name.')
param sqlAdminLogin string = 'sqladministrator'

@secure()
@minLength(12)
@description('Azure SQL administrator password. Stored in Key Vault.')
param sqlAdminPassword string

@description('Email address that receives alert notifications (Action Group).')
param alertEmail string

@description('Enable Microsoft Sentinel on the Log Analytics workspace (identity/entity enrichment layer).')
param enableSentinel bool = true

@description('Deploy the Azure SQL PaaS database. Disable on subscriptions whose policy forces Entra-only SQL auth (the VM SQL Server carries the persona demo).')
param enableAzureSql bool = true

@description('Enable Microsoft Sentinel UEBA settings (requires supported data sources; off by default).')
param enableUEBA bool = false

@description('Deploy an Azure OpenAI / Azure AI Foundry resource for the read-only AI Analyst layer.')
param enableAzureOpenAI bool = true

@description('Azure OpenAI model deployment name used by the AI Analyst (cost-conscious default).')
param openAiModelDeploymentName string = 'gpt-5-mini'

@description('Azure OpenAI model name to deploy.')
param openAiModelName string = 'gpt-5-mini'

@description('Azure OpenAI model version.')
param openAiModelVersion string = '2025-08-07'

@description('Deploy the read-only AI Analyst Function App (requires enableAzureOpenAI).')
param deployAiAnalystFunction bool = true

@description('Optional public client IP allowed through SQL and VM firewalls for the demo. Leave empty to skip.')
param clientIpAddress string = ''

@description('Size of the Windows SQL VM. v2 B-series is used because v1 B-series is not available in Sweden Central.')
param vmSize string = 'Standard_B4s_v2'

// AI Analyst Function is only deployed when both the flag and Azure OpenAI are enabled.
var deployFunction = deployAiAnalystFunction && enableAzureOpenAI

// ---- Naming --------------------------------------------------------------
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  project: 'sqlaudit-poc'
  environment: 'poc'
  workload: 'sql-audit-uba'
}

var names = {
  logAnalytics: 'log-sqlaudit-${resourceToken}'
  keyVault: 'kv${resourceToken}'
  sqlServer: 'sql-sqlaudit-${resourceToken}'
  sqlDatabase: 'PocBankingAuditDb'
  vm: 'vm-sqlpoc'
  actionGroup: 'ag-sqlaudit-poc'
  dcr: 'dcr-sqlvm-appevents'
  workbook: 'wb-sqlaudit-poc'
  openAi: 'oai-sqlaudit-${resourceToken}'
  functionApp: 'func-aianalyst-${resourceToken}'
  functionStorage: 'stfunc${resourceToken}'
  appInsights: 'appi-aianalyst-${resourceToken}'
  appServicePlan: 'plan-aianalyst-${resourceToken}'
}

// ---- Resource group ------------------------------------------------------
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---- Log Analytics -------------------------------------------------------
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'loganalytics'
  scope: rg
  params: {
    name: names.logAnalytics
    location: location
    tags: tags
    enableSentinel: false // Sentinel is deployed by sentinel.bicep below.
  }
}

// ---- Microsoft Sentinel (optional identity/entity enrichment) --------------
module sentinel 'modules/sentinel.bicep' = if (enableSentinel) {
  name: 'sentinel'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    enableUEBA: enableUEBA
  }
  dependsOn: [
    logAnalytics
  ]
}

// ---- Key Vault (stores admin secrets) ------------------------------------
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    name: names.keyVault
    location: location
    tags: tags
    sqlAdminPassword: sqlAdminPassword
    vmAdminPassword: adminPassword
  }
}

// ---- Azure SQL (logical server + database + auditing to LA) ---------------
module sqlAzure 'modules/sql-azure.bicep' = if (enableAzureSql) {
  name: 'sql-azure'
  scope: rg
  params: {
    serverName: names.sqlServer
    databaseName: names.sqlDatabase
    location: location
    tags: tags
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    logAnalyticsId: logAnalytics.outputs.id
    clientIpAddress: clientIpAddress
  }
}

// ---- Windows SQL Server VM (Developer edition image) ----------------------
module sqlVm 'modules/sql-vm.bicep' = {
  name: 'sql-vm'
  scope: rg
  params: {
    vmName: names.vm
    location: location
    tags: tags
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    clientIpAddress: clientIpAddress
  }
}

// ---- Monitoring: Action Group + DCR + AMA + association --------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    actionGroupName: names.actionGroup
    alertEmail: alertEmail
    dcrName: names.dcr
    logAnalyticsId: logAnalytics.outputs.id
    vmName: sqlVm.outputs.vmName
  }
}

// ---- Alerts: Log Search (scheduled query) rules ---------------------------
module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsId: logAnalytics.outputs.id
    actionGroupId: monitoring.outputs.actionGroupId
  }
}

// ---- Workbook (AI Behavior Analytics - the demo workbook) -----------------
module workbookAi 'modules/workbook.bicep' = {
  name: 'workbook-ai'
  scope: rg
  params: {
    location: location
    tags: tags
    workbookDisplayName: 'Contoso Bank SQL Audit & AI Behavior Analytics PoC'
    logAnalyticsId: logAnalytics.outputs.id
    serializedData: loadTextContent('../workbooks/SQLAuditAIBehaviorWorkbook.json')
  }
}

// ---- Azure OpenAI / AI Foundry (optional AI Analyst layer) -----------------
module aiOpenAi 'modules/ai-foundry-openai.bicep' = if (enableAzureOpenAI) {
  name: 'ai-openai'
  scope: rg
  params: {
    name: names.openAi
    location: location
    tags: tags
    modelDeploymentName: openAiModelDeploymentName
    modelName: openAiModelName
    modelVersion: openAiModelVersion
  }
}

// ---- AI Analyst Function App (optional, read-only) -------------------------
module functionApp 'modules/functionapp-ai-analyst.bicep' = if (deployFunction) {
  name: 'functionapp-ai-analyst'
  scope: rg
  params: {
    location: location
    tags: tags
    functionAppName: names.functionApp
    storageAccountName: names.functionStorage
    appInsightsName: names.appInsights
    appServicePlanName: names.appServicePlan
    logAnalyticsId: logAnalytics.outputs.id
    logAnalyticsName: names.logAnalytics
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    openAiEndpoint: enableAzureOpenAI ? aiOpenAi.outputs.endpoint : ''
    openAiAccountName: enableAzureOpenAI ? names.openAi : ''
    openAiDeploymentName: openAiModelDeploymentName
  }
}

// ---- Outputs (surfaced by azd into the environment) -----------------------
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_TENANT_ID string = subscription().tenantId
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.id
output LOG_ANALYTICS_CUSTOMER_ID string = logAnalytics.outputs.customerId
output LOG_ANALYTICS_NAME string = logAnalytics.outputs.name
output KEY_VAULT_NAME string = keyVault.outputs.name
output SQL_SERVER_NAME string = enableAzureSql ? sqlAzure.outputs.serverName : ''
output SQL_SERVER_FQDN string = enableAzureSql ? sqlAzure.outputs.serverFqdn : ''
output SQL_DATABASE_NAME string = enableAzureSql ? sqlAzure.outputs.databaseName : ''
output SQL_ADMIN_LOGIN string = sqlAdminLogin
output ENABLE_AZURE_SQL bool = enableAzureSql
output VM_NAME string = sqlVm.outputs.vmName
output VM_PUBLIC_IP string = sqlVm.outputs.publicIp
output VM_SQL_DATABASE_NAME string = 'PocBankingAuditDbOnVm'
output ACTION_GROUP_ID string = monitoring.outputs.actionGroupId
output ENABLE_SENTINEL bool = enableSentinel
output ENABLE_UEBA bool = enableUEBA
output ENABLE_AZURE_OPENAI bool = enableAzureOpenAI
output AZURE_OPENAI_ENDPOINT string = enableAzureOpenAI ? aiOpenAi.outputs.endpoint : ''
output AZURE_OPENAI_DEPLOYMENT_NAME string = openAiModelDeploymentName
output AI_ANALYST_FUNCTION_NAME string = deployFunction ? functionApp.outputs.functionAppName : ''
output AI_ANALYST_FUNCTION_URL string = deployFunction ? functionApp.outputs.functionAppUrl : ''
output SERVICE_AIANALYST_NAME string = deployFunction ? functionApp.outputs.functionAppName : ''
