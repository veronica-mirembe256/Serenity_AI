"""
app/routes/progress.py

FIX: Added None checks on all .maybe_single() responses.
When a new user has no progress row yet, Supabase returns None
not an object with .data — this was crashing the endpoint.
"""
from fastapi import APIRouter, Depends, HTTPException
from app.utils.auth import get_current_user
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/progress", tags=["Progress"])
logger = get_logger(__name__)


def _safe(res) -> dict:
    """Safely extract .data from a Supabase response — handles None."""
    if res is None:
        return {}
    data = getattr(res, "data", None)
    if data is None:
        return {}
    return data


@router.get("/chart", summary="Real daily mood and entry count for the last 30 days")
async def get_chart_data(
    user_id: str = Depends(get_current_user),
):
    supabase = get_supabase()
    try:
        res = (
            supabase.table("v_daily_progress")
            .select("entry_date, entry_count, avg_mood")
            .eq("user_id", user_id)
            .order("entry_date", desc=False)
            .execute()
        )
        rows = res.data if res and res.data else []
    except Exception as exc:
        logger.error("Chart data fetch failed",
            extra={"user_id": user_id, "error": str(exc)})
        # Return empty chart rather than crashing
        rows = []

    return {
        "chart":      rows,
        "total_days": len(rows),
    }


@router.get("/stats", summary="Streak, total entries, latest risk level")
async def get_stats(
    user_id: str = Depends(get_current_user),
):
    supabase = get_supabase()
    try:
        progress_res = (
            supabase.table("user_progress")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        insight_res = (
            supabase.table("ai_insights")
            .select("relapse_risk_level, detected_emotion, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error("Stats fetch failed",
            extra={"user_id": user_id, "error": str(exc)})
        raise HTTPException(500, detail="Could not fetch stats.")

    # FIX: use _safe() so None responses don't crash with AttributeError
    progress = _safe(progress_res)
    insights = insight_res.data if insight_res and insight_res.data else []
    latest   = insights[0] if insights else {}

    return {
        "current_streak":    progress.get("current_streak", 0),
        "longest_streak":    progress.get("longest_streak", 0),
        "total_entries":     progress.get("total_entries", 0),
        "last_entry_date":   progress.get("last_entry_date"),
        "latest_risk_level": latest.get("relapse_risk_level", "low"),
        "latest_emotion":    latest.get("detected_emotion"),
        # These fields are expected by the Flutter ProgressStats model
        "sobriety_start_date": progress.get("sobriety_start_date"),
        "weekly_summary": {
            "entries_this_week": progress.get("total_entries", 0),
            "average_mood":      None,
        },
        "badges": [],
    }