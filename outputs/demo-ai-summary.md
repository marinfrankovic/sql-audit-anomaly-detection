# Preloaded AI Investigation Examples (demo-ready)

_Seeded during deployment by generate-ai-baseline-data.ps1. Regenerate live findings with run-ai-analysis.ps1._

## DBA after-hours sensitive access - dba_user
**Finding:** dba_user read VIP salary/credit/risk fields in auditdemo.SensitiveCustomerData at 22:xx UTC, outside the expected 08-18 window. Privileged access is allowed, but the timing and VIP data target make this unusual for this user.

**Evidence:** UserName=dba_user; ObjectName=auditdemo.SensitiveCustomerData; Statement includes SalaryBand/CreditScore/InternalRiskComment; after-hours; RiskCategory=SensitiveDataAccess

**Recommended action:** Confirm an approved maintenance/task window; compare to peer DBAs; review whether VIP fields were required.

## Break-glass account used - breakglass_admin
**Finding:** breakglass_admin was used to read admin.AccessRequests. Break-glass accounts should only be used during an approved incident.

**Evidence:** UserName=breakglass_admin; ObjectName=admin.AccessRequests; RiskCategory=BreakGlass

**Recommended action:** Verify an approved incident record exists; rotate break-glass credentials after use.

## Suspicious DELETE on financial object - suspicious_user
**Finding:** suspicious_user issued a DELETE against payments.WireTransfers. Destructive statements against money-movement data are high risk.

**Evidence:** UserName=suspicious_user; ObjectName=payments.WireTransfers; Statement includes DELETE; RiskCategory=DataModification

**Recommended action:** Confirm change ticket; validate the rows targeted; review the account entitlements.

