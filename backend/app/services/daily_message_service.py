"""
app/services/daily_message_service.py

FIX: Added None checks for .maybe_single() responses — when a new user
has no progress row yet, Supabase returns None not an empty object.
FIX: LLM-generated message using daily_message.j2 with rule-based fallback.
"""
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger
from app.config import get_settings

logger   = get_logger(__name__)
settings = get_settings()


def _safe(res) -> dict:
    """Safely extract .data from a Supabase response — handles None."""
    if res is None:
        return {}
    data = getattr(res, "data", None)
    if data is None:
        return {}
    return data


def _rule_based_message(
    name: str,
    streak: int,
    recovery: str,
    challenges: list,
    goals: list,
) -> str:
    """Fallback message when LLM call fails or is not configured."""
    parts = [f"Good to see you, {name} 💚"]

    if streak == 0:
        parts.append("Today is a fresh start — no pressure, just presence.")
    elif streak < 3:
        parts.append(f"You're building momentum with a {streak}-day streak.")
    else:
        parts.append(f"Strong work — {streak} days of consistency.")

    if recovery == "addiction":
        parts.append("Focus today: protect your progress, not perfection.")
    elif recovery == "mental_health":
        parts.append("Focus today: emotional awareness over emotional control.")
    else:
        parts.append("Focus today: balance and stability in your day.")

    if isinstance(challenges, list):
        if "anxiety" in challenges:
            parts.append("If anxiety shows up, slow your breathing first.")
        if "stress" in challenges:
            parts.append("Don't carry everything at once today.")
        if "loneliness" in challenges:
            parts.append("Connection matters — even small interactions help.")
        if "urges" in challenges:
            parts.append("Urges pass — you've already proven that before.")
        if "sleep" in challenges:
            parts.append("Rest is part of recovery too.")

    if goals:
        parts.append("Keep one of your goals in mind today — even a small step counts.")

    return " ".join(parts)


async def generate_daily_message(user_id: str) -> dict:
    supabase = get_supabase(service_role=True)

    # ── Load profile ──────────────────────────────────────────────────────────
    try:
        res     = (
            supabase.table("user_profiles")
            .select("display_name,recovery_type,challenges,goals")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile = _safe(res)
    except Exception as e:
        logger.warning("Profile load failed", extra={"error": str(e)})
        profile = {}

    name       = profile.get("display_name") or "Friend"
    recovery   = profile.get("recovery_type") or "both"
    challenges = profile.get("challenges") or []
    goals      = profile.get("goals") or []

    # ── Load progress ─────────────────────────────────────────────────────────
    try:
        res      = (
            supabase.table("user_progress")
            .select("current_streak,longest_streak,total_entries")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        progress = _safe(res)
    except Exception as e:
        logger.warning("Progress load failed", extra={"error": str(e)})
        progress = {}

    streak = progress.get("current_streak", 0)

    # ── Load last entry summary (for prompt context) ────────────────────────────
    # FIX: daily_message.j2 references last_entry_summary but it was never
    # passed in, causing "'last_entry_summary' is undefined" and silently
    # falling back to the rule-based message every time.
    last_entry_summary = ""
    try:
        res = (
            supabase.table("ai_insights")
            .select("pattern_insight,detected_emotion,created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(1)
            .maybe_single()
            .execute()
        )
        latest_insight = _safe(res)
        if latest_insight:
            last_entry_summary = latest_insight.get("pattern_insight") or ""
    except Exception as e:
        logger.warning("Last entry summary load failed", extra={"error": str(e)})

    # ── Try LLM-generated message ─────────────────────────────────────────────
    final_message = None
    try:
        from app.utils.prompt_loader import render_prompt
        from langchain_openai import ChatOpenAI
        from langchain_core.messages import HumanMessage

        prompt = render_prompt(
            "daily_message.j2",
            user_name=name,
            recovery_type=recovery,
            challenges=challenges,
            goals=goals,
            streak=streak,
            last_entry_summary=last_entry_summary,
        )
        llm      = ChatOpenAI(
            model=settings.openai_model,
            temperature=0.7,
            openai_api_key=settings.openai_api_key,
        )
        response      = llm.invoke([HumanMessage(content=prompt)])
        final_message = response.content.strip()
        logger.info("LLM daily message generated", extra={"user_id": user_id})
    except Exception as e:
        logger.warning(
            "LLM daily message failed — using rule-based fallback",
            extra={"user_id": user_id, "error": str(e)},
        )

    # ── Fallback to rule-based ────────────────────────────────────────────────
    if not final_message:
        final_message = _rule_based_message(
            name, streak, recovery, challenges, goals)

    return {
        "message":    final_message,
        "streak":     streak,
        "mood_trend": recovery,
        "user_name":  name,
    }