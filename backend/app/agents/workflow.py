"""
app/agents/workflow.py - LangGraph multi-agent recovery pipeline.

Pipeline: Orchestrator -> Reflection -> Support -> RiskEscalation -> END

STREAMING: run_recovery_pipeline_stream() is an async generator that yields
Server-Sent Event (SSE) strings so the Flutter frontend receives live progress
updates instead of waiting ~10–20 seconds for the full pipeline to complete.

SSE event types emitted (in order):
  {"event": "status",  "data": "analysing"}          <- pipeline started
  {"event": "status",  "data": "reflecting"}          <- Reflection agent running
  {"event": "status",  "data": "supporting"}          <- Support agent running
  {"event": "status",  "data": "finalising"}          <- Risk node running
  {"event": "result",  "data": { ...full payload } }  <- final JSON result
  {"event": "error",   "data": "message"}             <- only on unrecoverable failure
"""
import asyncio
import json
import re
from typing import TypedDict, Optional, AsyncGenerator
from langgraph.graph import StateGraph, END
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, SystemMessage

from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
from openai import RateLimitError, APITimeoutError

from app.config import get_settings
from app.utils.prompt_loader import render_prompt
from app.db.chroma_client import retrieve_similar_entries
from app.logging_config.logger import get_logger

logger   = get_logger(__name__)
settings = get_settings()


# ── Shared state ──────────────────────────────────────────────────────────────

class AgentState(TypedDict):
    user_id:       str
    user_name:     str
    recovery_type: str
    challenges:    list[str]
    current_entry: str
    mood_score:    Optional[int]
    streak:        int
    past_entries:  list[dict]
    detected_emotion:            str
    pattern_insight:             str
    relapse_risk_level:          str
    relapse_risk_reason:         str
    medication_fatigue_detected: bool
    stigma_detected:             bool
    recommendations:             list[str]
    alternative_suggestions:     list[str]
    encouragement_message:       str
    medication_support:          Optional[str]
    stigma_reassurance:          Optional[str]
    escalation_required:         bool
    escalation_reason:           Optional[str]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _get_llm(temperature: float = 0.3) -> ChatOpenAI:
    return ChatOpenAI(
        model=settings.openai_model,
        temperature=temperature,
        openai_api_key=settings.openai_api_key,
    )


def _parse_json_response(raw: str) -> dict:
    """Strip markdown fences and parse JSON. Returns {} on failure."""
    text  = re.sub(r"```(?:json)?", "", raw).strip().rstrip("`").strip()
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            pass
    logger.warning("Could not parse JSON from LLM response",
        extra={"preview": raw[:200]})
    return {}


def _sse(event: str, data) -> str:
    """
    Format a Server-Sent Event string.
    FastAPI StreamingResponse sends these verbatim over the HTTP connection.
    Flutter reads them via an SSE/http-streaming package.

    Format:
        event: <name>
        data: <json or plain string>
        (blank line — signals end of this event)
    """
    payload = data if isinstance(data, str) else json.dumps(data)
    return f"event: {event}\ndata: {payload}\n\n"


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(min=1, max=10),
    retry=retry_if_exception_type((RateLimitError, APITimeoutError)),
)
def _invoke_llm(llm: ChatOpenAI, messages: list) -> object:
    """Synchronous LLM call wrapped with tenacity retry."""
    return llm.invoke(messages)


def _build_initial_state(
    user_id, user_name, recovery_type, challenges,
    current_entry, mood_score, streak,
) -> AgentState:
    return {
        "user_id":       user_id,
        "user_name":     user_name,
        "recovery_type": recovery_type,
        "challenges":    challenges,
        "current_entry": current_entry,
        "mood_score":    mood_score,
        "streak":        streak,
        "past_entries":  [],
        "detected_emotion":            "",
        "pattern_insight":             "",
        "relapse_risk_level":          "low",
        "relapse_risk_reason":         "",
        "medication_fatigue_detected": False,
        "stigma_detected":             False,
        "recommendations":             [],
        "alternative_suggestions":     [],
        "encouragement_message":       "",
        "medication_support":          None,
        "stigma_reassurance":          None,
        "escalation_required":         False,
        "escalation_reason":           None,
    }


# ── Agent nodes ───────────────────────────────────────────────────────────────

def orchestrator_node(state: AgentState) -> AgentState:
    logger.info("Orchestrator: fetching RAG context",
        extra={"user_id": state["user_id"]})
    try:
        past_entries = retrieve_similar_entries(
            user_id=state["user_id"],
            query_text=state["current_entry"],
            n_results=5,
        )
    except Exception as exc:
        logger.warning("RAG retrieval failed", extra={"error": str(exc)})
        past_entries = []
    return {**state, "past_entries": past_entries}


def reflection_node(state: AgentState) -> AgentState:
    logger.info("Reflection Agent: analysing entry",
        extra={"user_id": state["user_id"]})
    try:
        # FIX: past_entries from ChromaDB are flat dicts.
        # The template uses entry.metadata.created_at and entry.document
        # so we restructure them to match what the template expects.
        past_entries_formatted = [
            {
                "document": e.get("text", ""),
                "metadata": {
                    "created_at": e.get("created_at", "earlier"),
                    "mood_score": e.get("mood_score", ""),
                }
            }
            for e in state.get("past_entries", [])
        ]

        system_prompt = render_prompt(
            "reflection.j2",
            user_name=state["user_name"],
            recovery_type=state["recovery_type"],
            challenges=state["challenges"],
            current_entry="",
            past_entries=past_entries_formatted,   # FIX: use restructured entries
            mood_score=state.get("mood_score", "N/A"),
        )
        response = _invoke_llm(_get_llm(), [
            SystemMessage(content=system_prompt),
            HumanMessage(content=state["current_entry"]),
        ])
        parsed = _parse_json_response(response.content)
        logger.info("Reflection complete",
            extra={"user_id": state["user_id"],
                   "risk": parsed.get("relapse_risk_level"),
                   "emotion": parsed.get("detected_emotion")})
    except Exception as exc:
        logger.error("Reflection Agent failed",
            extra={"user_id": state["user_id"], "error": str(exc)})
        parsed = {}

    return {
        **state,
        "detected_emotion":            str(parsed.get("detected_emotion",           "Not detected")),
        "pattern_insight":             str(parsed.get("pattern_insight",            "No pattern detected yet.")),
        "relapse_risk_level":          str(parsed.get("relapse_risk_level",         "low")),
        "relapse_risk_reason":         str(parsed.get("relapse_risk_reason",        "")),
        "medication_fatigue_detected": bool(parsed.get("medication_fatigue_detected", False)),
        "stigma_detected":             bool(parsed.get("stigma_detected",             False)),
    }


def support_node(state: AgentState) -> AgentState:
    logger.info("Support Agent: generating response",
        extra={"user_id": state["user_id"]})
    try:
        system_prompt = render_prompt(
            "support.j2",
            user_name=state["user_name"],
            recovery_type=state["recovery_type"],
            challenges=state["challenges"],
            detected_emotion=state["detected_emotion"],
            pattern_insight=state["pattern_insight"],
            relapse_risk_level=state["relapse_risk_level"],
            medication_fatigue=state["medication_fatigue_detected"],
            stigma_detected=state["stigma_detected"],
            current_entry="",
            streak=state["streak"],
        )
        response = _invoke_llm(_get_llm(temperature=0.5), [
            SystemMessage(content=system_prompt),
            HumanMessage(content=state["current_entry"]),
        ])
        parsed = _parse_json_response(response.content)
        logger.info("Support Agent complete",
            extra={"user_id": state["user_id"]})
    except Exception as exc:
        logger.error("Support Agent failed",
            extra={"user_id": state["user_id"], "error": str(exc)})
        parsed = {}

    return {
        **state,
        "recommendations":         list(parsed.get("recommendations",         ["Take a moment to breathe and be kind to yourself."])),
        "alternative_suggestions": list(parsed.get("alternative_suggestions", [])),
        "encouragement_message":   str(parsed.get("encouragement_message",    "You showed up today. That is enough.")),
        "medication_support":      parsed.get("medication_support") or None,
        "stigma_reassurance":      parsed.get("stigma_reassurance") or None,
    }


def risk_escalation_node(state: AgentState) -> AgentState:
    risk = state.get("relapse_risk_level", "low").lower().strip()
    if risk not in ("low", "moderate", "high"):
        risk = "low"

    escalation_required = (risk == "high")
    reason = None

    if escalation_required:
        reason = (
            f"High relapse risk detected. "
            f"Reason: {state.get('relapse_risk_reason', 'see analysis')}. "
            f"Pattern: {state.get('pattern_insight', 'N/A')}."
        )
        logger.warning("HIGH RISK — escalation flagged",
            extra={"user_id": state["user_id"], "risk": risk, "reason": reason})
    else:
        logger.info("No escalation required",
            extra={"user_id": state["user_id"], "risk": risk})

    return {
        **state,
        "relapse_risk_level":  risk,
        "escalation_required": escalation_required,
        "escalation_reason":   reason,
    }


# ── Graph assembly ────────────────────────────────────────────────────────────

def build_recovery_graph() -> StateGraph:
    graph = StateGraph(AgentState)
    graph.add_node("orchestrator",    orchestrator_node)
    graph.add_node("reflection",      reflection_node)
    graph.add_node("support",         support_node)
    graph.add_node("risk_escalation", risk_escalation_node)
    graph.set_entry_point("orchestrator")
    graph.add_edge("orchestrator",    "reflection")
    graph.add_edge("reflection",      "support")
    graph.add_edge("support",         "risk_escalation")
    graph.add_edge("risk_escalation", END)
    return graph.compile()


recovery_graph = build_recovery_graph()


# ── Blocking entry point (kept for tests / internal callers) ─────────────────

def run_recovery_pipeline(
    user_id:       str,
    user_name:     str,
    recovery_type: str,
    challenges:    list[str],
    current_entry: str,
    mood_score:    int | None,
    streak:        int,
) -> AgentState:
    initial_state = _build_initial_state(
        user_id, user_name, recovery_type, challenges,
        current_entry, mood_score, streak,
    )
    logger.info("Recovery pipeline started (blocking)", extra={"user_id": user_id})
    try:
        result = recovery_graph.invoke(initial_state)
    except Exception as exc:
        logger.error("Pipeline failed — returning safe defaults",
            extra={"user_id": user_id, "error": str(exc)})
        result = {
            **initial_state,
            "detected_emotion":      "Could not analyse at this time.",
            "pattern_insight":       "Please try submitting again.",
            "encouragement_message": "You reached out. That takes courage. Please try again.",
        }
    logger.info("Recovery pipeline completed",
        extra={"user_id": user_id,
               "risk": result.get("relapse_risk_level"),
               "escalate": result.get("escalation_required")})
    return result


# ── STREAMING entry point ─────────────────────────────────────────────────────

async def run_recovery_pipeline_stream(
    user_id:       str,
    user_name:     str,
    recovery_type: str,
    challenges:    list[str],
    current_entry: str,
    mood_score:    int | None,
    streak:        int,
) -> AsyncGenerator[str, None]:
    """
    Async generator — yields SSE-formatted strings as each pipeline stage
    completes. Use with FastAPI's StreamingResponse:

        return StreamingResponse(
            run_recovery_pipeline_stream(...),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    Each LLM node (reflection, support) is run via asyncio.to_thread so the
    event loop is never blocked. Status events are yielded between stages so
    the Flutter UI can update its loading indicator in real time.

    SSE sequence the Flutter side receives:
        event: status  data: analysing    (immediate — confirms receipt)
        event: status  data: reflecting   (~0-1s)
        event: status  data: supporting   (~3-8s after reflection)
        event: status  data: finalising   (~3-8s after support)
        event: result  data: {...}        (final JSON payload)
    """
    initial_state = _build_initial_state(
        user_id, user_name, recovery_type, challenges,
        current_entry, mood_score, streak,
    )
    state = initial_state

    # Stage 0 — confirm receipt immediately
    yield _sse("status", "analysing")

    # Stage 1 — orchestrator (ChromaDB lookup, no LLM, fast)
    try:
        state = await asyncio.to_thread(orchestrator_node, state)
    except Exception as exc:
        logger.warning("Orchestrator failed in stream", extra={"error": str(exc)})
        state = {**state, "past_entries": []}

    # Stage 2 — reflection (LLM call ~3-8s)
    yield _sse("status", "reflecting")
    try:
        state = await asyncio.to_thread(reflection_node, state)
    except Exception as exc:
        logger.error("Reflection failed in stream",
            extra={"user_id": user_id, "error": str(exc)})
        state = {
            **state,
            "detected_emotion":            "Not detected",
            "pattern_insight":             "No pattern detected yet.",
            "relapse_risk_level":          "low",
            "relapse_risk_reason":         "",
            "medication_fatigue_detected": False,
            "stigma_detected":             False,
        }

    # Stage 3 — support (LLM call ~3-8s)
    yield _sse("status", "supporting")
    try:
        state = await asyncio.to_thread(support_node, state)
    except Exception as exc:
        logger.error("Support failed in stream",
            extra={"user_id": user_id, "error": str(exc)})
        state = {
            **state,
            "recommendations":         ["Take a moment to breathe and be kind to yourself."],
            "alternative_suggestions": [],
            "encouragement_message":   "You showed up today. That is enough.",
            "medication_support":      None,
            "stigma_reassurance":      None,
        }

    # Stage 4 — risk escalation (no LLM, instant)
    yield _sse("status", "finalising")
    try:
        state = await asyncio.to_thread(risk_escalation_node, state)
    except Exception as exc:
        logger.error("Risk node failed in stream",
            extra={"user_id": user_id, "error": str(exc)})

    # Stage 5 — emit final result
    result_payload = {
        "detected_emotion":        state.get("detected_emotion", ""),
        "pattern_insight":         state.get("pattern_insight", ""),
        "relapse_risk_level":      state.get("relapse_risk_level", "low"),
        "recommendations":         state.get("recommendations", []),
        "alternative_suggestions": state.get("alternative_suggestions", []),
        "encouragement_message":   state.get("encouragement_message", ""),
        "medication_support":      state.get("medication_support"),
        "stigma_reassurance":      state.get("stigma_reassurance"),
        "escalation_triggered":    state.get("escalation_required", False),
    }
    yield _sse("result", result_payload)

    logger.info("Streaming pipeline completed",
        extra={"user_id": user_id,
               "risk": state.get("relapse_risk_level"),
               "escalate": state.get("escalation_required")})