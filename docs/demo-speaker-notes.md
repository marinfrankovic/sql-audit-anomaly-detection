# Demo Speaker Notes (with fallbacks)

For each step: **what to say · what to click · what to run · expected output · fallback · business
value.** Fallback queries are mandatory — if an alert or live event is delayed, run the KQL directly.

---

## Step 1 — Framing
- **Say:** "Can we tell if database access behaviour is normal or abnormal — especially for
  privileged users?"
- **Click:** architecture diagram.
- **Value:** Moves the conversation from "we have logs" to "we understand behaviour."

## Step 2 — 90 days already exist
- **Run:**
  ```kusto
  SqlAuditPoC_CL | summarize Events=count() by bin(TimeGenerated,1d) | render columnchart
  ```
- **Expected:** ~90 daily bars; the last few days rise.
- **Fallback:** `SqlAuditPoC_CL | count` (should be thousands).
- **Value:** No waiting for ML — baselines are preloaded.

## Step 3 — Unified evidence
- **Click:** Log Analytics → Logs.
- **Run:**
  ```kusto
  UnifiedSqlAudit | where EventTime > ago(2d)
  | project EventTime, SourceType, UserName, ObjectName, Action, RiskCategory, AnomalyScore
  | order by AnomalyScore desc
  ```
- **Fallback (no saved function):** paste `kql/normalization.kql` body first.
- **Value:** One normalized model across cloud SQL + server SQL + history.

## Step 4 — Executive workbook
- **Click:** Workbook → TimeRange 30 days.
- **Expected:** tiles, timeline, volume baseline vs actual, top users all populated.
- **Fallback:** if a tile is blank, widen TimeRange or check the workspace picker.
- **Value:** Behaviour analytics dashboard, ready on day one.

## Step 5 — WOW scenarios
- **Run:** `./scripts/generate-wow-detections.ps1 -Target Azure -RunAi`
- **Expected:** console prints each scenario's meta; audit rows appear in ~2-5 min.
- **Fallback:** the preloaded current-day anomalies already show these detections — demo from the
  workbook if live ingestion lags.
- **Value:** Repeatable, safe (DELETEs roll back), non-destructive.

## Step 6 — DBA after-hours (Scenario 1 / Detection 1)
- **Say:** "The DBA is allowed in, but reading VIP salary/credit data after hours is unusual."
- **Fallback:**
  ```kusto
  SQLSecurityAuditEvents | where ServerPrincipalName=='dba_user' and ObjectName has 'SensitiveCustomerData'
  ```
- **Value:** Detects *unusual* privileged access, not just access.

## Step 7 — Suspicious DELETE (Scenario 3)
- **Fallback:** `SQLSecurityAuditEvents | where Statement has 'DELETE' and Statement has 'WireTransfers'`
- **Value:** Destructive statements on money-movement data are flagged.

## Step 8 — Permission escalation (Scenario 4)
- **Fallback:** `SQLSecurityAuditEvents | where Statement matches regex @'(?i)\b(GRANT|REVOKE)\b' and Statement has 'suspicious_user'`
- **Value:** Who grants access to whom, captured.

## Step 9 — Break-glass (Scenario 5)
- **Fallback:** `SQLSecurityAuditEvents | where ServerPrincipalName=='breakglass_admin'`
- **Value:** Emergency-account use is Sev0.

## Step 10 — Volume anomaly (Scenario 6 / Detection A)
- **Fallback:**
  ```kusto
  SQLSecurityAuditEvents | where ServerPrincipalName=='suspicious_user' and ActionName=='BATCH COMPLETED'
  | summarize count() by bin(TimeGenerated,5m)
  ```
- **Value:** Time-series baseline flags spikes automatically.

## Step 11 — AI investigation
- **Run:** `./scripts/run-ai-analysis.ps1`
- **Expected:** `outputs/demo-ai-summary.md` with executive summary, top risky users/objects,
  recommended actions.
- **Fallback:** if the AI Function is not deployed, the preloaded `outputs/demo-ai-summary.md`
  examples are shown.
- **Value:** AI explains the evidence; read-only, grounded, cites fields.

## Step 12 — Alerts / SOC
- **Click:** Monitor → Alerts.
- **Fallback:** run `kql/deterministic-detections.kql` to show triggering events immediately.
- **Value:** Feeds SOC; Sentinel/UEBA enriches identity context when enabled.

## Step 13 — Close
- **Say:** "From audit logging to behaviour analytics: who accessed what, whether it was expected,
  and why it matters."
