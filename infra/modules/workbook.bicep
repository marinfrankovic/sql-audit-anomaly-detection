// Deploys the Azure Workbook from the serialized JSON authored in /workbooks.
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Workbook display name shown in the portal.')
param workbookDisplayName string
@description('Log Analytics workspace resource id (default query scope for the workbook).')
param logAnalyticsId string
@description('Serialized workbook content (loaded from workbooks/SQLAuditAIBehaviorWorkbook.json).')
param serializedData string

// Deterministic GUID so redeploys update the same workbook instead of creating duplicates.
var workbookId = guid(resourceGroup().id, workbookDisplayName)

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookId
  location: location
  tags: union(tags, {
    'hidden-title': workbookDisplayName
  })
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: serializedData
    category: 'workbook'
    sourceId: logAnalyticsId
    version: '1.0'
  }
}

output workbookId string = workbook.id
output workbookName string = workbook.name
