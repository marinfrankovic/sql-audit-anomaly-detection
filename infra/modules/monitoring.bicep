// Monitoring wiring: Action Group (email), Data Collection Rule for Windows
// Application events, the Azure Monitor Agent extension on the VM, and the DCR
// association that links the VM to the rule. SQL Server Audit on the VM writes to
// the Windows Application log, which the DCR forwards to the Event table in LA.
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Action Group short/display name.')
param actionGroupName string
@description('Alert notification email address.')
param alertEmail string
@description('Data Collection Rule name.')
param dcrName string
@description('Log Analytics workspace resource id.')
param logAnalyticsId string
@description('Name of the VM to attach AMA + DCR to.')
param vmName string

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' existing = {
  name: vmName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'sqlauditpoc'
    enabled: true
    emailReceivers: [
      {
        name: 'PocOperator'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Data Collection Rule: collect the Windows Application event log (where SQL Server
// Audit writes) and route it to the Event table in Log Analytics.
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'applicationEvents'
          streams: [
            'Microsoft-Event'
          ]
          xPathQueries: [
            // All Application-log events (SQL Server Audit uses the MSSQLSERVER source).
            'Application!*'
            // Security-log events (successful/failed logins if audit policy raises them).
            'Security!*[System[(band(Keywords,13510798882111488))]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'laDestination'
          workspaceResourceId: logAnalyticsId
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Event'
        ]
        destinations: [
          'laDestination'
        ]
      }
    ]
  }
}

// Azure Monitor Agent on the SQL VM.
resource ama 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Associate the VM with the DCR.
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcra-sqlvm-appevents'
  scope: vm
  properties: {
    dataCollectionRuleId: dcr.id
  }
  dependsOn: [
    ama
  ]
}

output actionGroupId string = actionGroup.id
output actionGroupName string = actionGroup.name
output dcrId string = dcr.id
