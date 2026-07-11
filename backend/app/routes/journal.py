"""
app/routes/journal.py - Journal entry endpoints.

POST /journal            - submit entry, run AI pipeline, return insights (blocking)
POST /journal/stream     - submit entry, stream SSE progress events + final result
GET  /journal/insights   - paginated AI insight history
GET  /journal/test-auth  - debug endpoint to check authentication and data
GET  /journal/debug-progress - debug endpoint to check progress data
"""
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import StreamingResponse
from app.limiter import limiter
from app.utils.auth import get_current_user
from app.utils.models import (
    JournalEntryRequest, JournalEntryResponse,
    InsightsResponse, InsightItem,
)
from app.services.journal_service import create_journal_entry, create_journal_entry_stream
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger
import json

router = APIRouter(prefix="/journal", tags=["Journal"])
logger = get_logger(__name__)


# ── POST /journal  (original blocking endpoint — kept for compatibility) ──────

@router.post(
    "",
    response_model=JournalEntryResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a journal entry and receive AI-powered insights (blocking)",
)
@limiter.limit("10/minute")
async def post_journal_entry(
    request: Request,
    body: JournalEntryRequest,
    user_id: str = Depends(get_current_user),
):
    logger.info("=" * 80)
    logger.info("📝 POST /journal STARTED")
    logger.info(f"👤 User ID: {user_id}")
    logger.info(f"📝 Text length: {len(body.text)}")
    logger.info(f"😊 Mood score: {body.mood_score}")
    logger.info("=" * 80)

    try:
        result = await create_journal_entry(
            user_id=user_id,
            text=body.text,
            mood_score=body.mood_score,
        )

        logger.info("=" * 80)
        logger.info("✅ POST /journal SUCCESS")
        logger.info(f"📊 Result keys: {list(result.keys())}")
        logger.info(f"💡 Emotion: {result.get('detected_emotion')}")
        logger.info(f"📈 Risk level: {result.get('relapse_risk_level')}")
        logger.info(f"📝 Recommendations: {len(result.get('recommendations', []))}")
        logger.info("=" * 80)

        return JournalEntryResponse(**result)

    except ValueError as exc:
        logger.error(f"❌ ValueError: {exc}")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.error(f"❌ Journal pipeline error: {exc}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Something went wrong processing your entry. Please try again.",
        )


# ── POST /journal/stream  (new streaming endpoint) ───────────────────────────

@router.post(
    "/stream",
    summary="Submit a journal entry and stream SSE progress + result",
    response_class=StreamingResponse,
)
@limiter.limit("10/minute")
async def post_journal_entry_stream(
    request: Request,
    body: JournalEntryRequest,
    user_id: str = Depends(get_current_user),
):
    logger.info("=" * 80)
    logger.info("📡 POST /journal/stream STARTED")
    logger.info(f"👤 User ID: {user_id}")
    logger.info(f"📝 Text length: {len(body.text)}")
    logger.info(f"😊 Mood score: {body.mood_score}")
    logger.info("=" * 80)

    return StreamingResponse(
        create_journal_entry_stream(
            user_id=user_id,
            text=body.text,
            mood_score=body.mood_score,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control":     "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


# ── GET /journal/debug-progress (DEBUG endpoint) ─────────────────────────────

@router.get(
    "/debug-progress",
    summary="Debug endpoint to check progress data",
)
async def debug_progress(user_id: str = Depends(get_current_user)):
    """
    Debug endpoint that returns information about the user's progress.
    Useful for diagnosing issues with streak and entry counts not updating.
    """
    logger.info("=" * 80)
    logger.info("🔍 GET /journal/debug-progress STARTED")
    logger.info(f"👤 User ID from token: {user_id}")
    logger.info("=" * 80)

    supabase = get_supabase()
    result = {
        "user_id": user_id,
        "progress": None,
        "journal_entries_count": 0,
        "journal_entries_sample": [],
        "insights_count": 0,
        "insights_sample": [],
        "all_progress_records": [],
    }

    try:
        # Get progress
        progress_res = (
            supabase.table("user_progress")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        result["progress"] = progress_res.data if progress_res and progress_res.data else None
        logger.info(f"📊 Progress exists: {result['progress'] is not None}")
        if result["progress"]:
            logger.info(f"📊 Progress data: {result['progress']}")

    except Exception as exc:
        logger.error(f"❌ Progress fetch failed: {exc}")
        result["progress_error"] = str(exc)

    try:
        # Get all progress records (to see if any exist)
        all_progress = (
            supabase.table("user_progress")
            .select("*")
            .limit(10)
            .execute()
        )
        result["all_progress_records"] = all_progress.data if all_progress and all_progress.data else []
        logger.info(f"📊 All progress records in DB: {len(result['all_progress_records'])}")

    except Exception as exc:
        logger.error(f"❌ All progress fetch failed: {exc}")
        result["all_progress_error"] = str(exc)

    try:
        # Get journal entries count
        journal_res = (
            supabase.table("journal_entries")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        result["journal_entries_count"] = journal_res.count if hasattr(journal_res, 'count') else 0
        logger.info(f"📓 Journal entries count: {result['journal_entries_count']}")

        # Get sample journal entries
        if result["journal_entries_count"] > 0:
            sample_journal = (
                supabase.table("journal_entries")
                .select("id, text, mood_score, created_at")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(3)
                .execute()
            )
            result["journal_entries_sample"] = sample_journal.data if sample_journal and sample_journal.data else []
            logger.info(f"📓 Sample journal entries: {len(result['journal_entries_sample'])}")

    except Exception as exc:
        logger.error(f"❌ Journal fetch failed: {exc}")
        result["journal_error"] = str(exc)

    try:
        # Get insights count
        insights_res = (
            supabase.table("ai_insights")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        result["insights_count"] = insights_res.count if hasattr(insights_res, 'count') else 0
        logger.info(f"💡 Insights count: {result['insights_count']}")

        # Get sample insights
        if result["insights_count"] > 0:
            sample_insights = (
                supabase.table("ai_insights")
                .select("id, detected_emotion, relapse_risk_level, created_at")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(3)
                .execute()
            )
            result["insights_sample"] = sample_insights.data if sample_insights and sample_insights.data else []
            logger.info(f"💡 Sample insights: {len(result['insights_sample'])}")

    except Exception as exc:
        logger.error(f"❌ Insights fetch failed: {exc}")
        result["insights_error"] = str(exc)

    logger.info("=" * 80)
    logger.info("✅ GET /journal/debug-progress COMPLETE")
    logger.info(f"📊 Result: {json.dumps(result, default=str)[:500]}...")
    logger.info("=" * 80)

    return result


# ── GET /journal/test-auth (DEBUG endpoint) ──────────────────────────────────

@router.get(
    "/test-auth",
    summary="Debug endpoint to check authentication and data",
)
async def test_auth(user_id: str = Depends(get_current_user)):
    """
    Debug endpoint that returns information about the current user's authentication
    and data in the database. Useful for diagnosing issues with insights not showing.
    """
    logger.info("=" * 80)
    logger.info("🔍 GET /journal/test-auth STARTED")
    logger.info(f"👤 User ID from token: {user_id}")
    logger.info("=" * 80)

    supabase = get_supabase()
    result = {
        "user_id": user_id,
        "profile": None,
        "journal_entries_count": 0,
        "insights_count": 0,
        "insights_data": [],
        "all_insights_sample": [],
    }

    try:
        # Get user profile
        profile_res = (
            supabase.table("user_profiles")
            .select("*")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        result["profile"] = profile_res.data if profile_res and profile_res.data else None
        logger.info(f"📋 Profile exists: {result['profile'] is not None}")

    except Exception as exc:
        logger.error(f"❌ Profile fetch failed: {exc}")
        result["profile_error"] = str(exc)

    try:
        # Get journal entries count
        journal_res = (
            supabase.table("journal_entries")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        result["journal_entries_count"] = journal_res.count if hasattr(journal_res, 'count') else 0
        logger.info(f"📓 Journal entries count: {result['journal_entries_count']}")

        # Get sample journal entries
        if result["journal_entries_count"] > 0:
            sample_journal = (
                supabase.table("journal_entries")
                .select("id, text, mood_score, created_at")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(3)
                .execute()
            )
            result["journal_entries_sample"] = sample_journal.data if sample_journal and sample_journal.data else []

    except Exception as exc:
        logger.error(f"❌ Journal fetch failed: {exc}")
        result["journal_error"] = str(exc)

    try:
        # Get insights count
        insights_res = (
            supabase.table("ai_insights")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        result["insights_count"] = insights_res.count if hasattr(insights_res, 'count') else 0
        logger.info(f"💡 Insights count: {result['insights_count']}")

        # Get the actual insights
        if result["insights_count"] > 0:
            insights_data = (
                supabase.table("ai_insights")
                .select("*")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .limit(10)
                .execute()
            )
            result["insights_data"] = insights_data.data if insights_data and insights_data.data else []
            logger.info(f"📊 Retrieved {len(result['insights_data'])} insights")

    except Exception as exc:
        logger.error(f"❌ Insights fetch failed: {exc}")
        result["insights_error"] = str(exc)

    try:
        # Get sample of all insights (to check if any exist at all)
        all_insights = (
            supabase.table("ai_insights")
            .select("id, user_id, detected_emotion, created_at")
            .limit(5)
            .execute()
        )
        result["all_insights_sample"] = all_insights.data if all_insights and all_insights.data else []
        logger.info(f"📊 Sample of all insights in DB: {len(result['all_insights_sample'])}")

    except Exception as exc:
        logger.error(f"❌ All insights fetch failed: {exc}")
        result["all_insights_error"] = str(exc)

    logger.info("=" * 80)
    logger.info("✅ GET /journal/test-auth COMPLETE")
    logger.info(f"📊 Result: {json.dumps(result, default=str)[:500]}...")
    logger.info("=" * 80)

    return result


# ── GET /journal/insights ─────────────────────────────────────────────────────

@router.get(
    "/insights",
    response_model=InsightsResponse,
    summary="Retrieve AI insight history",
)
async def get_insights(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user_id: str = Depends(get_current_user),
):
    logger.info("=" * 80)
    logger.info("📖 GET /journal/insights STARTED")
    logger.info(f"👤 User ID from token: {user_id}")
    logger.info(f"📊 Limit: {limit}, Offset: {offset}")
    logger.info("=" * 80)

    # FIX: use service_role client — regular client was silently blocked by
    # RLS SELECT policy, always returning 0 rows despite successful inserts
    supabase = get_supabase(service_role=True)

    try:
        # First, check if user has any insights
        count_res = (
            supabase.table("ai_insights")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        )
        total_count = count_res.count if hasattr(count_res, 'count') else 0
        logger.info(f"📊 Total insights in DB for user {user_id}: {total_count}")

        # If no insights, check if user has journal entries
        if total_count == 0:
            journal_res = (
                supabase.table("journal_entries")
                .select("id", count="exact")
                .eq("user_id", user_id)
                .execute()
            )
            journal_count = journal_res.count if hasattr(journal_res, 'count') else 0
            logger.info(f"📓 User has {journal_count} journal entries")

            # If there are journal entries but no insights, check if insights exist with different user_id
            if journal_count > 0:
                all_insights_res = (
                    supabase.table("ai_insights")
                    .select("user_id, journal_entry_id, detected_emotion")
                    .limit(10)
                    .execute()
                )
                all_insights = all_insights_res.data if all_insights_res and all_insights_res.data else []
                logger.info(f"🔍 Sample insights in DB (any user): {all_insights}")

        # Now get the actual data
        res = (
            supabase.table("ai_insights")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )

        logger.info(f"📦 Response data length: {len(res.data) if res and hasattr(res, 'data') and res.data else 0}")

    except Exception as exc:
        logger.error(f"❌ Insights fetch failed: {exc}", exc_info=True)
        raise HTTPException(status_code=500, detail="Could not fetch insights.")

    rows = res.data if res and hasattr(res, 'data') else []
    logger.info(f"📊 Retrieved {len(rows)} rows from database")

    if rows:
        logger.info(f"🔍 First row keys: {list(rows[0].keys())}")
        logger.info(f"🔍 First row sample: {json.dumps(rows[0], default=str)[:500]}...")
    else:
        logger.warning("⚠️ No rows returned from database query!")

    insights = []
    for idx, r in enumerate(rows):
        try:
            alt = r.get("alternative_suggestions") or []
            if not alt:
                raw = r.get("raw_response") or {}
                alt = raw.get("alternative_suggestions") or []

            insight = InsightItem(
                id=r.get("id", ""),
                journal_entry_id=r.get("journal_entry_id"),
                detected_emotion=r.get("detected_emotion", ""),
                pattern_insight=r.get("pattern_insight", ""),
                relapse_risk_level=r.get("relapse_risk_level", "low"),
                recommendations=r.get("recommendations") or [],
                alternative_suggestions=alt,
                encouragement=r.get("encouragement", ""),
                created_at=r.get("created_at", ""),
            )
            insights.append(insight)
            logger.info(f"✅ Processed insight {idx + 1}: {insight.detected_emotion}")

        except Exception as exc:
            logger.error(f"❌ Skipping malformed insight row {idx}: {exc}")
            logger.error(f"❌ Row data: {r}")

    logger.info("=" * 80)
    logger.info(f"✅ Returning {len(insights)} insights to frontend")
    logger.info(f"📊 First insight: {insights[0].detected_emotion if insights else 'None'}")
    logger.info("=" * 80)

    return InsightsResponse(insights=insights, total=len(insights))