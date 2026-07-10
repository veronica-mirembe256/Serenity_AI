"""
app/services/progress_service.py — progress, stats, and badge retrieval.
"""

from datetime import datetime, timedelta, timezone
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger

logger = get_logger(__name__)


def _safe_data(res):
    """Safely extract data from Supabase response."""
    if not res:
        return None
    if hasattr(res, "data"):
        return res.data
    return None


async def get_user_stats(user_id: str) -> dict:
    """Return progress stats, weekly summary, and badges for a user."""
    supabase = get_supabase()

    # ── Progress ───────────────────────────────────────────────────────────
    try:
        progress_res = (
            supabase.table("user_progress")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        progress = progress_res.data if progress_res and hasattr(progress_res, "data") else {}
    except Exception as e:
        logger.warning("Progress fetch failed", extra={"error": str(e)})
        progress = {}

    # ── Badges ─────────────────────────────────────────────────────────────
    try:
        badges_res = (
            supabase.table("user_badges")
            .select("*")
            .eq("user_id", user_id)
            .execute()
        )
        badges = badges_res.data if badges_res and hasattr(badges_res, "data") else []
    except Exception as e:
        logger.warning("Badges fetch failed", extra={"error": str(e)})
        badges = []

    # ── Weekly entries ─────────────────────────────────────────────────────
    try:
        seven_days_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()

        weekly_res = (
            supabase.table("journal_entries")
            .select("id, mood_score, created_at")
            .eq("user_id", user_id)
            .gte("created_at", seven_days_ago)
            .execute()
        )

        weekly_entries = weekly_res.data if weekly_res and hasattr(weekly_res, "data") else []
    except Exception as e:
        logger.warning("Weekly entries fetch failed", extra={"error": str(e)})
        weekly_entries = []

    mood_scores = [e.get("mood_score") for e in weekly_entries if e.get("mood_score") is not None]
    avg_mood = round(sum(mood_scores) / len(mood_scores), 1) if mood_scores else None

    # ── Latest insight ─────────────────────────────────────────────────────
    try:
        insight_res = (
            supabase.table("ai_insights")
            .select("relapse_risk_level, detected_emotion, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )

        insight_data = insight_res.data if insight_res and hasattr(insight_res, "data") else []
        latest_insight = insight_data[0] if insight_data else {}
       

    except Exception as e:
        logger.warning("Insight fetch failed", extra={"error": str(e)})
        latest_insight = {}

    logger.info("Stats retrieved", extra={"user_id": user_id})

    return {
        "current_streak": progress.get("current_streak", 0),
        "longest_streak": progress.get("longest_streak", 0),
        "total_entries": progress.get("total_entries", 0),
        "sobriety_start_date": progress.get("sobriety_start_date"),
        "last_entry_date": progress.get("last_entry_date"),
        "weekly_summary": {
            "entries_this_week": len(weekly_entries),
            "average_mood": avg_mood,
        },
        "latest_risk_level": latest_insight.get("relapse_risk_level", "unknown"),
        "latest_emotion": latest_insight.get("detected_emotion"),
        "badges": [
            {
                "badge": b.get("badge"),
                "label": b.get("label"),
                "awarded_at": b.get("awarded_at"),
            }
            for b in badges
        ],
    }