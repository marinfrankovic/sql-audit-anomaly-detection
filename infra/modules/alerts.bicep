// Log Search (scheduled query) alert rules over the unified SQL audit data.
// All rules run on short intervals suitable for a live demo and notify the Action Group.
@description('Location.')
param location string
@description('Tags.')
param tags object
@description('Log Analytics workspace resource id (alert scope).')
param logAnalyticsId string
@description('Action Group resource id to notify.')
param actionGroupId string

// Common evaluation cadence for the PoC (fast feedback during a demo).
var evaluationFrequency = 'PT5M'
var windowSize = 'PT10M'

// --------------------------------------------------------------------------
// 1. Failed Login Burst — several failed authentications from the same principal.
// --------------------------------------------------------------------------
resource alertFailedLoginBurst 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-FailedLoginBurst'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Failed Login Burst'
    description: 'Multiple failed database authentications from the same user in a short window.'
    severity: 2
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| where ActionName in ("DATABASE AUTHENTICATION FAILED", "LOGIN FAILED")
| summarize FailedLogins = count() by ServerPrincipalName, bin(TimeGenerated, 5m)
| where FailedLogins >= 5
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 2. High-Risk SQL Statement — DELETE/DROP/ALTER/GRANT against key objects.
// --------------------------------------------------------------------------
resource alertHighRiskStatement 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-HighRiskStatement'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — High-Risk SQL Statement'
    description: 'Destructive or privilege-changing statement detected in audit stream.'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| where Statement matches regex @"(?i)\b(DROP|ALTER\s+TABLE|TRUNCATE|GRANT|REVOKE|ALTER\s+ROLE|ADD\s+MEMBER|ALTER\s+AUTHORIZATION)\b"
    or (Statement matches regex @"(?i)\bDELETE\b" and Statement matches regex @"(?i)(Transactions|PaymentInstructions|WireTransfers)")
| project TimeGenerated, ServerPrincipalName, DatabaseName, ObjectName, ActionName, Statement
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 3. Sensitive Table Access by Non-Privileged User.
// --------------------------------------------------------------------------
resource alertSensitiveByNonPriv 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-SensitiveAccessNonPrivileged'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Sensitive Table Access by Non-Privileged User'
    description: 'A non-privileged principal accessed a sensitive object (e.g. SensitiveCustomerData).'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| extend Principal = tolower(ServerPrincipalName)
| where (ObjectName has_any ("SensitiveCustomerData", "FraudSignals", "WireTransfers", "CustomerRiskScores", "SanctionsScreening")
        or Statement has_any ("SensitiveCustomerData", "FraudSignals", "WireTransfers", "CustomerRiskScores", "SanctionsScreening"))
| where Principal in ("normal_user", "reporting_user", "app_user")
| project TimeGenerated, ServerPrincipalName, DatabaseName, ObjectName, ActionName, Statement
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 4. Privileged After-Hours Sensitive Access.
// --------------------------------------------------------------------------
resource alertPrivilegedAfterHours 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-PrivilegedAfterHoursSensitive'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Privileged After-Hours Sensitive Access'
    description: 'A privileged user (DBA/admin) touched sensitive data outside business hours.'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| extend Principal = tolower(ServerPrincipalName)
| extend HourUtc = datetime_part("Hour", TimeGenerated)
| where Principal in ("dba_user", "privileged_admin", "breakglass_admin")
| where (ObjectName has "SensitiveCustomerData"
        or Statement has_any ("SalaryBand", "CreditScore", "InternalRiskComment", "NationalIdentifier"))
| where HourUtc < 6 or HourUtc >= 18
| project TimeGenerated, ServerPrincipalName, DatabaseName, ObjectName, Statement
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 5. Break-glass Account Used.
// --------------------------------------------------------------------------
resource alertBreakGlass 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-BreakGlassUsed'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Break-glass Account Used'
    description: 'Any activity by the emergency break-glass account should be reviewed immediately.'
    severity: 0
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| where tolower(ServerPrincipalName) == "breakglass_admin" or Statement has "breakglass_admin"
| project TimeGenerated, ServerPrincipalName, DatabaseName, ObjectName, ActionName, Statement
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 6. Permission Escalation.
// --------------------------------------------------------------------------
resource alertPermissionEscalation 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-PermissionEscalation'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Permission Escalation'
    description: 'GRANT / ALTER ROLE / ADD MEMBER / role-membership change detected.'
    severity: 1
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| where ActionName has_any ("ADD MEMBER", "DATABASE ROLE MEMBER CHANGE", "SERVER ROLE MEMBER CHANGE", "PERMISSION CHANGE")
    or Statement matches regex @"(?i)\b(GRANT|ALTER\s+ROLE|ADD\s+MEMBER|sp_addrolemember)\b"
| project TimeGenerated, ServerPrincipalName, DatabaseName, ObjectName, ActionName, Statement
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// --------------------------------------------------------------------------
// 7. Query Volume Spike — one principal runs an unusually high count of statements.
// --------------------------------------------------------------------------
resource alertQueryVolumeSpike 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'SQLPoC-QueryVolumeSpike'
  location: location
  tags: tags
  properties: {
    displayName: 'SQL PoC — Query Volume Spike'
    description: 'Potential data exfiltration: a single principal runs a high volume of statements.'
    severity: 2
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      logAnalyticsId
    ]
    criteria: {
      allOf: [
        {
          query: '''
SQLSecurityAuditEvents
| where ActionName == "BATCH COMPLETED"
| summarize StatementCount = count() by ServerPrincipalName, bin(TimeGenerated, 5m)
| where StatementCount >= 50
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'ServerPrincipalName'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output alertNames array = [
  alertFailedLoginBurst.name
  alertHighRiskStatement.name
  alertSensitiveByNonPriv.name
  alertPrivilegedAfterHours.name
  alertBreakGlass.name
  alertPermissionEscalation.name
  alertQueryVolumeSpike.name
]
