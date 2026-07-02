// Azure OpenAI (Azure AI Foundry-compatible) account + a single, cost-conscious
// chat model deployment used by the read-only AI Analyst layer.
@description('Azure OpenAI account name (globally unique).')
param name string
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Model deployment name referenced by the AI Analyst.')
param modelDeploymentName string = 'gpt-5-mini'
@description('Model name.')
param modelName string = 'gpt-5-mini'
@description('Model version.')
param modelVersion string = '2025-08-07'
@description('Deployment SKU (GlobalStandard for the gpt-5 family).')
param skuName string = 'GlobalStandard'
@description('Deployment capacity in thousands of tokens/min (kept small for PoC cost).')
param capacity int = 10

resource openAi 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    // Entra ID token auth is preferred; local (key) auth left enabled for PoC simplicity.
    disableLocalAuth: false
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAi
  name: modelDeploymentName
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

output id string = openAi.id
output name string = openAi.name
output endpoint string = openAi.properties.endpoint
output deploymentName string = modelDeployment.name
