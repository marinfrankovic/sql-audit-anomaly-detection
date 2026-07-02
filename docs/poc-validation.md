# PoC Validation Guide

Exact checks with KQL/CLI. ✔ = expected. The environment is demo-ready immediately due to preloaded
history; live checks (5-8) populate after you run the setup/activity scripts.

## 1. Deployment complete
```powershell
az resource list --resource-group rg-sqlaudit-demo --query "[].{name:name,type:type}" -o table
```
✔ Log Analytics, Key Vault, SQL server+DB, VM (+NIC/PIP/NSG/VNet), DCR, Action Group, 7 alerts, 2
workbooks, Azure OpenAI, Function App (+ storage, App Insights, plan), Sentinel solution.

## 2. Preloaded 90-day history exists
```kusto
SqlAuditPoC_CL | summarize Events=count(), Days=dcount(bin(TimeGenerated,1d)) 
```
✔ Thousands of events across ~90 days.

## 3. SQL audit records exist (after live activity)
```kusto
SQLSecurityAuditEvents | where TimeGenerated > ago(1h)
| project TimeGenerated, DatabaseName, DatabasePrincipalName, ActionName, ObjectName, Statement
| order by TimeGenerated desc
```

## 4. SQL VM audit records exist
```kusto
Event | where TimeGenerated > ago(1h) and Source has "MSSQL"
| project TimeGenerated, Computer, EventID, RenderedDescription | order by TimeGenerated desc
```

## 5. UnifiedSqlAudit works (history + live)
```kusto
UnifiedSqlAudit | where EventTime > ago(2d)
| summarize Events=count() by SourceType | order by Events desc
```
✔ Includes `History` (and `AzureSQL`/`SqlServerVM` once live activity runs).

## 6. Sensitive table access
```kusto
UnifiedSqlAudit | where IsSensitiveObject | summarize count() by UserName, ObjectName | order by count_ desc
```

## 7. High-risk statements detected (deterministic)
```kusto
// see kql/deterministic-detections.kql D1
SQLSecurityAuditEvents | where Statement matches regex @"(?i)\b(DROP|TRUNCATE|GRANT|REVOKE|ALTER\s+ROLE|ADD\s+MEMBER)\b"
```

## 8. Baseline anomaly detection works (KQL-ML)
```kusto
SqlAuditPoC_CL | where Action_s=='BATCH COMPLETED'
| make-series Q=count() default=0 on TimeGenerated in range(ago(90d), now(), 1d) by UserName_s
| extend (a,s,b)=series_decompose_anomalies(Q, 1.5)
```
✔ Anomalies flagged on the recent (deviation/major) days.

## 9. Query volume anomaly
```kusto
union isfuzzy=true (SQLSecurityAuditEvents | where ActionName=='BATCH COMPLETED'),
                   (SqlAuditPoC_CL | where Action_s=='BATCH COMPLETED' | extend ServerPrincipalName=UserName_s)
| summarize c=count() by ServerPrincipalName, bin(TimeGenerated,5m) | where c>=50
```

## 10. First-time sensitive object access
```kusto
let base = SqlAuditPoC_CL | where TimeGenerated between (ago(90d)..ago(2d)) and ObjectName_s has 'SensitiveCustomerData' | distinct UserName_s, ObjectName_s;
SqlAuditPoC_CL | where TimeGenerated > ago(2d) and ObjectName_s has 'SensitiveCustomerData'
| join kind=leftanti base on UserName_s, ObjectName_s
```

## 11. Break-glass usage detected
```kusto
union isfuzzy=true (SQLSecurityAuditEvents | where tolower(ServerPrincipalName)=='breakglass_admin'),
                   (SqlAuditPoC_CL | where tolower(UserName_s)=='breakglass_admin')
```

## 12. AI summary generated
```powershell
./scripts/run-ai-analysis.ps1 ; Get-Content ./outputs/demo-ai-summary.md
```
✔ Executive summary + top risky users/objects + recommended actions.

## 13. Workbook deployed
```powershell
az resource list -g rg-sqlaudit-demo --resource-type Microsoft.Insights/workbooks -o table
```
✔ Two workbooks; the AI Behavior workbook tiles/timeline are populated from history.

## 14. Alerts deployed
```powershell
az monitor scheduled-query list -g rg-sqlaudit-demo --query "[].{name:name,enabled:enabled}" -o table
```
✔ 7 enabled rules.

## 15. Optional Sentinel tables available
```kusto
union isfuzzy=true (SecurityIncident | count), (BehaviorAnalytics | count)
```
✔ Tables resolve (may be empty until analytics/UEBA are configured).

## 16. Optional UEBA context (friendly fallback)
Run `kql/sentinel-ueba-correlation.kql` — returns UEBA context or the message
"UEBA context is optional and depends on Sentinel onboarding and supported data sources."
