#!/usr/bin/env python
"""Generate the Contoso Bank 30-minute demo Facilitator Guide as a PDF (reportlab)."""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                                PageBreak, HRFlowable)

OUT = r"SQLAudit-Demo-Facilitator-Guide.pdf"

# ---- palette ---------------------------------------------------------------
BLUE = colors.HexColor("#0F6CBD")
DARK = colors.HexColor("#1B1B1B")
GREY = colors.HexColor("#5A5A5A")
LIGHT = colors.HexColor("#EAF2FB")
GREEN = colors.HexColor("#107C41")
AMBER = colors.HexColor("#B7791F")
RED = colors.HexColor("#B4232B")
LINE = colors.HexColor("#D7D7D7")

styles = getSampleStyleSheet()
def S(name, **kw):
    styles.add(ParagraphStyle(name, **kw))

S('CoverTitle', fontName='Helvetica-Bold', fontSize=26, leading=30, textColor=BLUE, alignment=TA_CENTER)
S('CoverSub', fontName='Helvetica', fontSize=14, leading=18, textColor=DARK, alignment=TA_CENTER)
S('CoverMeta', fontName='Helvetica', fontSize=10, leading=15, textColor=GREY, alignment=TA_CENTER)
S('H1', fontName='Helvetica-Bold', fontSize=15, leading=19, textColor=BLUE, spaceBefore=6, spaceAfter=4)
S('H2', fontName='Helvetica-Bold', fontSize=12, leading=16, textColor=DARK, spaceBefore=8, spaceAfter=3)
S('Body', fontName='Helvetica', fontSize=9.5, leading=13.5, textColor=DARK)
S('BodyGrey', fontName='Helvetica', fontSize=9, leading=12.5, textColor=GREY)
S('Say', fontName='Helvetica-Oblique', fontSize=9.5, leading=13.5, textColor=DARK)
S('Mono', fontName='Courier', fontSize=8.4, leading=11.5, textColor=colors.HexColor("#0B3D66"))
S('LabelW', fontName='Helvetica-Bold', fontSize=8.5, leading=11, textColor=colors.white)
S('Cell', fontName='Helvetica', fontSize=9, leading=12.5, textColor=DARK)
S('TimeBadge', fontName='Helvetica-Bold', fontSize=10, leading=12, textColor=colors.white, alignment=TA_CENTER)

story = []

def hr(space=4):
    story.append(Spacer(1, space))
    story.append(HRFlowable(width="100%", thickness=0.6, color=LINE))
    story.append(Spacer(1, space))

def para(txt, style='Body'):
    story.append(Paragraph(txt, styles[style]))

def bullets(items, style='Body'):
    for it in items:
        story.append(Paragraph(f"&bull;&nbsp;&nbsp;{it}", styles[style]))

def code(lines):
    if isinstance(lines, str):
        lines = [lines]
    txt = "<br/>".join(l.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;') for l in lines)
    t = Table([[Paragraph(txt, styles['Mono'])]], colWidths=[170*mm])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor("#F3F7FB")),
        ('BOX', (0,0), (-1,-1), 0.5, LINE),
        ('LEFTPADDING', (0,0), (-1,-1), 8), ('RIGHTPADDING', (0,0), (-1,-1), 8),
        ('TOPPADDING', (0,0), (-1,-1), 5), ('BOTTOMPADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t)
    story.append(Spacer(1, 3))

def labelrow(rows):
    """rows: list of (label, colorHex, flowable-or-text)."""
    data = []
    for label, col, content in rows:
        if isinstance(content, str):
            content = Paragraph(content, styles['Cell'])
        lab = Paragraph(label, styles['LabelW'])
        cellbg = Table([[lab]], colWidths=[20*mm])
        cellbg.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,-1), col),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('LEFTPADDING',(0,0),(-1,-1),5),('RIGHTPADDING',(0,0),(-1,-1),5),
            ('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4),
        ]))
        data.append([cellbg, content])
    t = Table(data, colWidths=[22*mm, 148*mm])
    t.setStyle(TableStyle([
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('BOX', (0,0), (-1,-1), 0.5, LINE),
        ('INNERGRID', (0,0), (-1,-1), 0.5, LINE),
        ('LEFTPADDING',(1,0),(1,-1),7),('RIGHTPADDING',(1,0),(1,-1),7),
        ('TOPPADDING',(1,0),(1,-1),5),('BOTTOMPADDING',(1,0),(1,-1),5),
    ]))
    story.append(t)
    story.append(Spacer(1, 7))

def step_header(time_text, title):
    badge = Table([[Paragraph(time_text, styles['TimeBadge'])]], colWidths=[26*mm], rowHeights=[8*mm])
    badge.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), BLUE),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    ttl = Paragraph(f"<b>{title}</b>", ParagraphStyle('st', fontName='Helvetica-Bold', fontSize=13, leading=16, textColor=DARK))
    t = Table([[badge, ttl]], colWidths=[28*mm, 142*mm])
    t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'MIDDLE'), ('LEFTPADDING',(1,0),(1,0),6)]))
    story.append(Spacer(1, 2))
    story.append(t)
    story.append(Spacer(1, 4))

# ---------------------------------------------------------------------------
# COVER
# ---------------------------------------------------------------------------
story.append(Spacer(1, 45*mm))
para("Contoso Bank", 'CoverTitle')
para("AI-Augmented SQL Audit &amp; User Behavior Anomaly Detection", 'CoverTitle')
story.append(Spacer(1, 6))
para("30-Minute Customer Demo &mdash; Facilitator Guide", 'CoverSub')
story.append(Spacer(1, 14))
box = Table([[Paragraph('&ldquo;Today we are proving that Contoso Bank can see <b>who</b> accessed <b>what database '
                        'records</b>, <b>when</b>, <b>from where</b>, and whether the behaviour looks '
                        '<b>normal or abnormal</b> &mdash; even when the user has legitimate elevated access.&rdquo;',
                        ParagraphStyle('q', fontName='Helvetica-Oblique', fontSize=12, leading=17,
                                       textColor=DARK, alignment=TA_CENTER))]], colWidths=[150*mm])
box.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),LIGHT), ('BOX',(0,0),(-1,-1),0.5,BLUE),
                         ('LEFTPADDING',(0,0),(-1,-1),12),('RIGHTPADDING',(0,0),(-1,-1),12),
                         ('TOPPADDING',(0,0),(-1,-1),10),('BOTTOMPADDING',(0,0),(-1,-1),10)]))
story.append(box)
story.append(Spacer(1, 30))
para("Role: Facilitator / Presenter &nbsp;|&nbsp; Duration: 30 minutes &nbsp;|&nbsp; Audience: Contoso Bank", 'CoverMeta')
para("Environment: resource group <b>rg-sqlaudit-demo</b> (Sweden Central) &mdash; deployed &amp; demo-ready", 'CoverMeta')
para("Three layers: Deterministic KQL &bull; KQL-ML anomaly detection &bull; Azure OpenAI (read-only) explanation", 'CoverMeta')
story.append(PageBreak())

# ---------------------------------------------------------------------------
# BEFORE YOU START
# ---------------------------------------------------------------------------
para("Before you start (facilitator prep)", 'H1')
para("Do this 10&ndash;15 minutes before the meeting. The environment is already deployed and the 90-day "
     "history, baselines, anomaly scores and AI examples are <b>preloaded</b> &mdash; you never generate "
     "training data in front of the customer.", 'Body')
story.append(Spacer(1, 4))
para("Checklist", 'H2')
bullets([
    "Sign in to the Azure portal and pin the resource group <b>rg-sqlaudit-demo</b>.",
    "Open <b>Monitor &rarr; Workbooks &rarr; Contoso Bank SQL Audit &amp; AI Behavior Analytics PoC</b>. Set <b>Time Range = Last 30 days</b>. Confirm tiles and charts are populated.",
    "Open <b>Log Analytics workspace</b> (log-sqlaudit-&hellip;) &rarr; <b>Logs</b>, ready to paste KQL.",
    "Open a PowerShell terminal at the root of the project folder.",
    "(Optional, recommended) 10 minutes before, generate fresh live events on the VM so they appear during the demo:",
])
code([
    "./scripts/run-poc-scenarios.ps1 -Setup      # one-time: VM schema, personas, audit, mock data",
    "./scripts/generate-wow-detections.ps1       # scenarios 0-9 on the SQL Server VM",
])
para("If you skip the optional step, the demo still works entirely from the <b>preloaded history</b> and the "
     "workbook &mdash; use the fallback KQL in each step.", 'BodyGrey')
story.append(Spacer(1, 4))
para("Golden rules", 'H2')
bullets([
    "Lead with the <b>business question</b> (normal vs abnormal), not the plumbing.",
    "Privileged access is not automatically suspicious &mdash; the value is detecting access that is <b>unusual</b> for the user, object, timing, or volume.",
    "If an alert has not fired yet, run its KQL directly (fallbacks are provided). Never wait in silence.",
    "The AI layer <b>explains evidence</b>; it never invents events, never runs SQL, never changes anything.",
])
hr()
para("Agenda", 'H1')
agenda = [
    ["Time", "Segment", "What you show"],
    ["0:00 - 2:00", "Opening / framing", "The business question"],
    ["2:00 - 5:00", "Architecture", "Diagram: 3 layers, Azure-only"],
    ["5:00 - 8:00", "Raw audit evidence", "90-day history + UnifiedSqlAudit"],
    ["8:00 - 12:00", "Workbook executive view", "Tiles, timeline, users, sensitive data"],
    ["12:00 - 17:00", "Run WOW scenarios", "Live detections on the VM"],
    ["17:00 - 21:00", "Anomaly detections", "AnomalyScore, RiskCategory, why"],
    ["21:00 - 25:00", "AI-assisted investigation", "AI explains the evidence"],
    ["25:00 - 28:00", "Alerting & SOC handoff", "Alerts, Action Group, Sentinel"],
    ["28:00 - 30:00", "Close / production", "Value + next steps"],
]
t = Table(agenda, colWidths=[24*mm, 46*mm, 100*mm])
t.setStyle(TableStyle([
    ('BACKGROUND',(0,0),(-1,0),BLUE), ('TEXTCOLOR',(0,0),(-1,0),colors.white),
    ('FONTNAME',(0,0),(-1,0),'Helvetica-Bold'), ('FONTSIZE',(0,0),(-1,-1),8.6),
    ('FONTNAME',(0,1),(-1,-1),'Helvetica'), ('TEXTCOLOR',(0,1),(-1,-1),DARK),
    ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white, colors.HexColor('#F3F7FB')]),
    ('GRID',(0,0),(-1,-1),0.4,LINE), ('VALIGN',(0,0),(-1,-1),'MIDDLE'),
    ('LEFTPADDING',(0,0),(-1,-1),6),('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4),
]))
story.append(t)
story.append(PageBreak())

# ---------------------------------------------------------------------------
# STEPS
# ---------------------------------------------------------------------------
def step(time_text, title, open_click, say, do, expected, fallback=None, keep=False):
    step_header(time_text, title)
    rows = [
        ("OPEN /<br/>CLICK", BLUE, open_click),
        ("SAY", GREEN, Paragraph(say, styles['Say'])),
        ("DO", DARK, do),
        ("EXPECT", AMBER, expected),
    ]
    if fallback:
        rows.append(("FALL-<br/>BACK", RED, fallback))
    labelrow(rows)

# --- 1
step("0:00-2:00", "Opening &amp; framing",
     "Nothing on screen yet (or the title slide / architecture diagram).",
     "&ldquo;Contoso Bank already collects logs. The real question is different: can we tell whether database access "
     "<b>behaviour</b> is normal or abnormal &mdash; especially for privileged users who are <i>allowed</i> "
     "to touch sensitive data? Today we&rsquo;ll show who accessed what records, when, from where, and whether "
     "it looked normal &mdash; and then let AI explain the evidence.&rdquo;",
     "Introduce yourself and set the 30-minute agenda in one sentence. Keep it business-first.",
     "The room understands this is about behaviour analytics, not just logging.")

# --- 2
step("2:00-5:00", "Architecture (Azure-only, cost-conscious)",
     "Open <b>architecture.drawio</b> (in the repo) or the diagram slide.",
     "&ldquo;Everything runs in Azure. On the left, two SQL sources &mdash; a cloud database and a SQL Server on "
     "a VM that stands in for on-prem. Both stream audit data into one Log Analytics workspace, where we "
     "normalise it into a single model called <b>UnifiedSqlAudit</b>. From there we run <b>three layers</b>: "
     "deterministic rules, KQL machine-learning anomaly detection, and an optional read-only AI analyst. "
     "Alerts feed the SOC, and Microsoft Sentinel can enrich identity context.&rdquo;",
     "Trace the left-to-right flow with your cursor: sources &rarr; Log Analytics &rarr; the three layers "
     "&rarr; workbook / alerts. Point at the &lsquo;90-day history seed&rsquo; box.",
     "Customer sees the defence-in-depth story and that the demo is ready now (history preloaded).",
     "If asked &lsquo;is this just for cloud SQL?&rsquo; &mdash; point at the VM path: the same pipeline works "
     "for server-based SQL via the Azure Monitor Agent.")

# --- 3
step("5:00-8:00", "Raw audit evidence + 90 days of history",
     "Switch to <b>Log Analytics &rarr; Logs</b>.",
     "&ldquo;First, the evidence. We already have 90 days of behaviour &mdash; baselines exist <i>today</i>, so "
     "nothing has to &lsquo;learn&rsquo; during this call. Here is every audited action, normalised: who, what "
     "object, what action, and a risk category.&rdquo;",
     "Paste and run the two queries below (one at a time).",
     "First query renders ~90 daily bars (the last few days rise). Second query lists recent actions with "
     "UserName, ObjectName, RiskCategory, AnomalyScore.",
     "If a query errors, widen the time picker to 90 days and re-run; custom-log data is retained 90 days.")
para("Query 1 &mdash; daily volume across the 90-day history (run this first, on its own):", 'BodyGrey')
code([
    "SqlAuditPoC_CL | where isnotempty(EventTime_t)",
    "| summarize Events=count() by bin(EventTime_t, 1d) | render columnchart",
])
para("Query 2 &mdash; recent actions by risk (run this second, on its own):", 'BodyGrey')
code([
    "UnifiedSqlAudit",
    "| project EventTime, SourceType, UserName, ObjectName, Action, RiskCategory, AnomalyScore",
    "| order by AnomalyScore desc | take 50",
])
para("Facilitator tip: Query 1 reads the preloaded history table <b>SqlAuditPoC_CL</b> and bins by "
     "<b>EventTime_t</b> (the business event time, which spans the full 90 days). Query 2 uses the saved "
     "<b>UnifiedSqlAudit</b> function (normalised view over the history) &mdash; both are created at deployment "
     "and work from the start.", 'BodyGrey')
story.append(PageBreak())

# --- 4
step("8:00-12:00", "Workbook &mdash; executive view",
     "Switch to <b>Monitor &rarr; Workbooks &rarr; Contoso Bank SQL Audit &amp; AI Behavior Analytics PoC</b> "
     "(Time Range = Last 30 days).",
     "&ldquo;This is what a Contoso Bank security lead sees on day one. Total audit events, total anomalies, "
     "high-risk and privileged anomalies, sensitive-object accesses, and break-glass usage &mdash; all "
     "populated already. Below, the activity timeline and the query-volume baseline versus actual, then "
     "the top users and sensitive-data access.&rdquo;",
     "Scroll slowly through sections 1&ndash;4. Pause on the <b>query volume baseline vs actual</b> chart and "
     "on <b>Sensitive Data Access</b>.",
     "Tiles and charts are filled from the preloaded history &mdash; a credible, populated dashboard.",
     "If a tile looks empty, confirm the Time Range is 30 days and the correct workspace is selected in the "
     "workbook parameters.")

# --- 5
step("12:00-17:00", "Run the WOW scenarios (live)",
     "Bring the <b>PowerShell terminal</b> to the front (in the repo folder).",
     "&ldquo;Now let&rsquo;s create some behaviour live and watch the system react. I&rsquo;ll run a set of "
     "safe, scripted scenarios &mdash; a DBA reading VIP salary data after hours, a suspicious DELETE on wire "
     "transfers, a permission escalation, and a break-glass login.&rdquo;",
     "Run the command below. As it prints each scenario, read the one-line &lsquo;why it matters&rsquo;.",
     "Console prints each scenario (what it does, why it matters, validation KQL, alert name). Events reach "
     "Log Analytics in ~2&ndash;5 minutes.",
     "If live ingestion lags, don&rsquo;t wait &mdash; the same detections already exist in the preloaded "
     "current-day data. Demo them from the workbook / KQL instead.")
code([
    "./scripts/generate-wow-detections.ps1 -Target Both",
])

# --- 6
step("17:00-21:00", "Show the anomaly detections",
     "Back to the <b>workbook &rarr; WOW Detections</b> and <b>Investigation View</b> "
     "(or run the KQL below in Logs).",
     "&ldquo;Notice we are not only matching static rules. The system compares behaviour to each user&rsquo;s "
     "own baseline &mdash; unusual object, unusual time, unusual volume, unusual role-to-data relationship. "
     "Each row has a <b>RiskCategory</b>, an <b>AnomalyScore</b>, and a plain-language <b>BehaviorExplanation</b> "
     "of why it stood out.&rdquo;",
     "In the Investigation View, sort by AnomalyScore. Point at a DBA after-hours row and a break-glass row. "
     "Toggle the <b>Show only anomalies</b> parameter.",
     "High-scoring rows surface break-glass, DBA after-hours sensitive access, suspicious DELETE, escalation.",
     "Fallback KQL (paste in Logs) &mdash; always populated from the preloaded history:")
code([
    "UnifiedSqlAudit",
    "| where DetectionName != 'None'",
    "| project EventTime, UserName, ObjectName, DetectionName, RiskCategory, AnomalyScore",
    "| order by AnomalyScore desc | take 50",
])
story.append(PageBreak())

# --- 7
step("21:00-25:00", "AI-assisted investigation",
     "Bring the <b>terminal</b> forward.",
     "&ldquo;An analyst doesn&rsquo;t want 10,000 rows &mdash; they want to know what to look at first and why. "
     "This is a <b>read-only</b> AI analyst. It only uses the evidence we retrieved, it cites the exact fields, "
     "and it never runs SQL or changes anything. Let&rsquo;s ask it to summarise today&rsquo;s risk.&rdquo;",
     "Run the command. Then open <b>outputs/demo-ai-summary.md</b> and read the executive summary, the top "
     "risky user, the evidence cited, and the recommended next step.",
     "A concise AI summary: why the activity is suspicious, supporting fields (UserName, EventTime, ObjectName, "
     "RiskCategory&hellip;), a benign alternative, and an investigation step.",
     "If the AI call is unavailable, open the <b>preloaded</b> outputs/demo-ai-summary.md (seeded at deployment) "
     "&mdash; it contains ready examples for the same anomalies.")
code([
    "./scripts/run-ai-analysis.ps1",
    "# then open:  outputs/demo-ai-summary.md",
])
para("Talk track: &ldquo;The AI does not replace audit or detection. It explains the evidence &mdash; grounded "
     "in the data, read-only, and safe for a regulated environment.&rdquo;", 'Say')

# --- 8
step("25:00-28:00", "Alerting &amp; SOC handoff",
     "Open <b>Monitor &rarr; Alerts</b> (and, if enabled, Microsoft Sentinel).",
     "&ldquo;Every deterministic detection is also an alert. Seven rules run on a short interval and notify an "
     "Action Group by email &mdash; break-glass is the highest severity. In production these feed your SOC, and "
     "Microsoft Sentinel UEBA adds identity and entity context when it&rsquo;s onboarded.&rdquo;",
     "Show the 7 <b>SQLPoC-*</b> alert rules and the Action Group email target. Mention the 5-minute cadence.",
     "Customer sees the operational path from detection to notification to SOC.",
     "If no alert has fired yet, open a rule and click <b>View query</b> / run its KQL to show the triggering "
     "events immediately.")

# --- 9
step("28:00-30:00", "Close &amp; production discussion",
     "Return to the workbook or the architecture diagram.",
     "&ldquo;So &mdash; who accessed what records, when, from where, whether it was expected, and why it "
     "matters. That&rsquo;s the move from database <b>audit logging</b> to database <b>behaviour analytics</b>. "
     "For production we&rsquo;d add private networking, Entra-only SQL auth, Microsoft Defender for SQL, longer "
     "retention, Sentinel analytics with UEBA, and AI governance.&rdquo;",
     "Recap the value in one breath; invite questions; agree a next step (e.g. a scoped pilot on a real Contoso Bank "
     "database).",
     "Clear close with a concrete next action.")

hr()
# ---- soundbites & objections ----
para("Talk-track soundbites (use anywhere)", 'H1')
bullets([
    "&ldquo;Privileged access is not automatically suspicious. The value is detecting privileged access that is "
    "unusual for the user, object, timing, or operation.&rdquo;",
    "&ldquo;We are not only detecting failed logins &mdash; we are detecting behaviour that deviates from "
    "expected job function.&rdquo;",
    "&ldquo;Every claim on screen is backed by an immutable audit record. One source of truth for audit, "
    "compliance and the SOC.&rdquo;",
    "&ldquo;The AI explains the evidence and helps an analyst decide what to investigate first &mdash; it never "
    "invents events and never changes anything.&rdquo;",
], 'Say')
story.append(Spacer(1, 6))
para("Likely questions &amp; short answers", 'H1')
qa = [
    ["Question", "Short answer"],
    ["Is my query text exposed to AI?",
     "Only already-retrieved KQL rows are sent, in-tenant. In production you restrict RBAC and can mask "
     "statement text before it reaches the model."],
    ["Does UEBA baseline SQL audit directly?",
     "No. UEBA baselines supported identity sources (Entra sign-ins, Azure Activity, Security Events) and adds "
     "entity context. The SQL anomaly detection is our KQL layer."],
    ["How much does this cost?",
     "Small: serverless / burstable compute, a cost-conscious model (gpt-5-mini), pay-as-you-go Log Analytics. "
     "Everything tears down with one command."],
    ["Is the data real?",
     "No &mdash; 100% synthetic banking data. No real personal data anywhere."],
    ["Can it block access?",
     "This PoC is detect-and-explain (read-only). Blocking/automation is a production design choice."],
]
t = Table(qa, colWidths=[52*mm, 118*mm])
t.setStyle(TableStyle([
    ('BACKGROUND',(0,0),(-1,0),DARK), ('TEXTCOLOR',(0,0),(-1,0),colors.white),
    ('FONTNAME',(0,0),(-1,0),'Helvetica-Bold'), ('FONTSIZE',(0,0),(-1,-1),8.6),
    ('FONTNAME',(0,1),(-1,-1),'Helvetica'), ('TEXTCOLOR',(0,1),(-1,-1),DARK),
    ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white, colors.HexColor('#F3F7FB')]),
    ('GRID',(0,0),(-1,-1),0.4,LINE), ('VALIGN',(0,0),(-1,-1),'TOP'),
    ('LEFTPADDING',(0,0),(-1,-1),6),('RIGHTPADDING',(0,0),(-1,-1),6),
    ('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4),
]))
story.append(t)
story.append(Spacer(1, 8))

para("After the demo &mdash; cleanup (optional)", 'H1')
para("The environment is cost-conscious and safe to leave for follow-ups. To remove everything:", 'Body')
code(["azd down --purge     # deletes rg-sqlaudit-demo and all resources"])

para("Appendix &mdash; KQL cheat sheet (paste into Logs)", 'H1')
code([
    "// 90-day history overview (bin by the business event time)",
    "SqlAuditPoC_CL | where isnotempty(EventTime_t) | summarize count() by bin(EventTime_t,1d) | render columnchart",
    "",
    "// Break-glass usage",
    "UnifiedSqlAudit | where tolower(UserName)=='breakglass_admin'",
    "",
    "// DBA after-hours sensitive access",
    "UnifiedSqlAudit | where DetectionName == 'DBA after-hours sensitive access'",
    "",
    "// Suspicious DELETE on wire transfers",
    "UnifiedSqlAudit | where DetectionName == 'Suspicious DELETE on financial object'",
    "",
    "// Top anomalies by score",
    "UnifiedSqlAudit | where DetectionName != 'None'",
    "| project EventTime, UserName, ObjectName, DetectionName, RiskCategory, AnomalyScore",
    "| order by AnomalyScore desc | take 25",
])

# ---------------------------------------------------------------------------
def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(LINE); canvas.setLineWidth(0.5)
    canvas.line(20*mm, 12*mm, 190*mm, 12*mm)
    canvas.setFont('Helvetica', 7.5); canvas.setFillColor(GREY)
    canvas.drawString(20*mm, 7*mm, "Contoso Bank \u2014 AI-Augmented SQL Audit & User Behavior Anomaly Detection \u00b7 Facilitator Guide")
    canvas.drawRightString(190*mm, 7*mm, "Page %d" % doc.page)
    canvas.restoreState()

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=20*mm, rightMargin=20*mm,
                        topMargin=16*mm, bottomMargin=16*mm,
                        title="Contoso Bank SQL Audit Demo - Facilitator Guide", author="Microsoft")
doc.build(story, onFirstPage=footer, onLaterPages=footer)
print("WROTE", OUT, os.path.getsize(OUT), "bytes")
