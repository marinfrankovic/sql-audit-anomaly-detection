"""
Read-only AI Analyst API for the Contoso Bank SQL Audit & Behavior Analytics PoC.

Design & safety boundaries (see /docs/ai-behavior-analytics-design.md):
  * READ-ONLY. This API never executes SQL and never modifies Azure resources.
  * The model is grounded ONLY in evidence supplied in the request body (already
    retrieved by KQL) — it must not invent events.
  * Authentication to Azure OpenAI uses the Function App's managed identity
    (DefaultAzureCredential) — no keys or secrets are stored in code or settings.
  * Content-safety: the deployed model uses the default Azure OpenAI content
    filter (RAI policy 'Microsoft.DefaultV2'). We additionally instruct the model
    not to emit secrets or destructive SQL.

Endpoints:
  GET  /api/health
  POST /api/analyze/anomaly            -> explain a single anomaly record
  POST /api/analyze/daily-summary      -> executive daily risk summary
  POST /api/kql/generate               -> generate a READ-ONLY KQL query
  POST /api/demo/executive-summary     -> 3-minute demo narrative
"""
import json
import logging
import os

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# ---- System prompt (mirrors /ai/prompts/sql-security-analyst-system-prompt.txt) ----
SYSTEM_PROMPT = (
    "You are a read-only SQL security analyst for a regulated financial services "
    "customer (Contoso Bank). You analyze SQL audit events and anomaly outputs. You MUST NOT "
    "invent events; use ONLY the evidence provided. You explain why activity is normal, "
    "unusual, or high risk, and you cite supporting fields: UserName, EventTime, "
    "DatabaseName, ObjectName, Statement, ClientIp, RiskCategory, DetectionName. "
    "Privileged access is not automatically suspicious — focus on whether it is unusual "
    "for the user, object, timing, volume, or operation. You recommend investigation "
    "steps for a human analyst; you never execute actions. You are read-only: never "
    "propose destructive SQL (DELETE/DROP/ALTER/GRANT/UPDATE/INSERT/TRUNCATE) or Azure "
    "resource changes. Never output secrets, connection strings, credentials, or tokens."
)

# Extra guard rail appended to the KQL generation task.
KQL_GUARD = (
    "Generate a READ-ONLY Kusto (KQL) query for Azure Log Analytics only. The query must "
    "only read data (SQLSecurityAuditEvents / Event / UnifiedSqlAudit). Never produce "
    "T-SQL, never produce destructive or mutating statements, and never reference secrets."
)

_client = None
_deployment = None


def _get_client():
    """Lazily construct an Azure OpenAI client using managed identity (no keys)."""
    global _client, _deployment
    if _client is not None:
        return _client, _deployment

    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "").strip()
    _deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini").strip()
    api_version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21").strip()
    if not endpoint:
        raise RuntimeError("AZURE_OPENAI_ENDPOINT is not configured (AI layer disabled).")

    # Import here so the module still loads (e.g. /health) when packages are absent.
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider
    from openai import AzureOpenAI

    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
    )
    _client = AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version=api_version,
    )
    return _client, _deployment


def _complete(user_prompt: str, temperature: float = 0.1, max_tokens: int = 900) -> str:
    """Call the chat model with the fixed system prompt. Read-only, low temperature.

    Newer models (gpt-5 family) only support the default temperature and use
    max_completion_tokens, so we fall back gracefully across model generations.
    """
    client, deployment = _get_client()
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_prompt},
    ]
    try:
        resp = client.chat.completions.create(
            model=deployment,
            max_completion_tokens=max_tokens,
            messages=messages,
        )
    except Exception:  # noqa: BLE001 - retry with legacy params for older models
        resp = client.chat.completions.create(
            model=deployment,
            temperature=temperature,
            max_tokens=max_tokens,
            messages=messages,
        )
    return resp.choices[0].message.content or ""


def _evidence_from(req: func.HttpRequest) -> str:
    """Return the request's 'evidence' as compact JSON (already-retrieved KQL rows)."""
    try:
        body = req.get_json()
    except ValueError:
        body = {}
    evidence = body.get("evidence", body)
    # Bound the size to avoid oversized prompts / cost blow-ups.
    text = json.dumps(evidence, default=str)[:24000]
    return text, body


def _json_response(payload: dict, status: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps(payload, default=str), status_code=status, mimetype="application/json"
    )


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    configured = bool(os.environ.get("AZURE_OPENAI_ENDPOINT"))
    return _json_response({"status": "ok", "aiConfigured": configured})


@app.route(route="analyze/anomaly", methods=["POST"])
def analyze_anomaly(req: func.HttpRequest) -> func.HttpResponse:
    evidence, _ = _evidence_from(req)
    prompt = (
        "Explain the following SQL audit anomaly. Use ONLY this evidence; do not invent "
        "events; cite fields.\n\nEvidence (JSON):\n" + evidence +
        "\n\nProduce: (1) what happened, (2) why it triggered, (3) evidence cited, "
        "(4) a likely benign explanation, (5) a read-only investigation step. Under 200 words."
    )
    try:
        return _json_response({"analysis": _complete(prompt)})
    except Exception as ex:  # noqa: BLE001
        logging.exception("analyze_anomaly failed")
        return _json_response({"error": str(ex)}, status=500)


@app.route(route="analyze/daily-summary", methods=["POST"])
def daily_summary(req: func.HttpRequest) -> func.HttpResponse:
    evidence, _ = _evidence_from(req)
    prompt = (
        "Produce a daily SQL risk executive summary for Contoso Bank security leadership. Use ONLY "
        "this evidence; do not invent events; cite fields.\n\nEvidence (JSON):\n" + evidence +
        "\n\nProduce: (1) executive summary, (2) top risky users, (3) top risky objects, "
        "(4) prioritised read-only investigation actions. If evidence is empty, say no "
        "notable risk was observed."
    )
    try:
        return _json_response({"summary": _complete(prompt)})
    except Exception as ex:  # noqa: BLE001
        logging.exception("daily_summary failed")
        return _json_response({"error": str(ex)}, status=500)


@app.route(route="kql/generate", methods=["POST"])
def kql_generate(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        body = {}
    question = str(body.get("question", "")).strip()
    if not question:
        return _json_response({"error": "Provide a 'question'."}, status=400)
    prompt = (
        KQL_GUARD + "\n\nQuestion: " + question +
        "\n\nReturn the KQL query, then a short explanation of what it does. "
        "The query MUST be read-only."
    )
    try:
        return _json_response({"result": _complete(prompt, temperature=0.0)})
    except Exception as ex:  # noqa: BLE001
        logging.exception("kql_generate failed")
        return _json_response({"error": str(ex)}, status=500)


@app.route(route="demo/executive-summary", methods=["POST"])
def demo_executive_summary(req: func.HttpRequest) -> func.HttpResponse:
    evidence, _ = _evidence_from(req)
    prompt = (
        "Write a 3-minute executive narrative for a customer demo, based ONLY on this "
        "evidence of recent anomalies. Do not invent events; cite the key fields. Tone: "
        "confident, factual, non-alarmist.\n\nEvidence (JSON):\n" + evidence
    )
    try:
        return _json_response({"narrative": _complete(prompt, max_tokens=700)})
    except Exception as ex:  # noqa: BLE001
        logging.exception("demo_executive_summary failed")
        return _json_response({"error": str(ex)}, status=500)
