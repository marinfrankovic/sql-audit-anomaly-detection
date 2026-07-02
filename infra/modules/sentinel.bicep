// Microsoft Sentinel onboarding on the Log Analytics workspace, plus optional
// UEBA / Entity Analytics settings. Sentinel is used here for identity/entity
// behavioural ENRICHMENT — it is NOT the primary SQL-audit anomaly detector.
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Name of the existing Log Analytics workspace to onboard.')
param logAnalyticsName string
@description('Enable UEBA / Entity Analytics settings (requires supported data sources).')
param enableUEBA bool = false

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

// SecurityInsights solution links Sentinel to the workspace (portal visibility).
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${logAnalyticsName})'
  location: location
  tags: tags
  plan: {
    name: 'SecurityInsights(${logAnalyticsName})'
    product: 'OMSGallery/SecurityInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: workspace.id
  }
}

// Modern onboarding state (idempotent alongside the solution).
resource onboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  scope: workspace
  name: 'default'
  properties: {}
  dependsOn: [
    sentinelSolution
  ]
}

// Entity Analytics (enables entity pages/insights) — optional.
resource entityAnalytics 'Microsoft.SecurityInsights/settings@2023-12-01-preview' = if (enableUEBA) {
  scope: workspace
  name: 'EntityAnalytics'
  kind: 'EntityAnalytics'
  properties: {
    entityProviders: [
      'AzureActiveDirectory'
    ]
  }
  dependsOn: [
    onboarding
  ]
}

// UEBA settings — data sources that UEBA baselines identity/entity behaviour on.
// NOTE: UEBA baselines these supported sources, NOT SQLSecurityAuditEvents directly.
resource ueba 'Microsoft.SecurityInsights/settings@2023-12-01-preview' = if (enableUEBA) {
  scope: workspace
  name: 'Ueba'
  kind: 'Ueba'
  properties: {
    dataSources: [
      'AuditLogs'
      'AzureActivity'
      'SigninLogs'
      'SecurityEvent'
    ]
  }
  dependsOn: [
    entityAnalytics
  ]
}

output sentinelEnabled bool = true
output uebaEnabled bool = enableUEBA
