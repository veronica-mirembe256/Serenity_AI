"""
app/routes/journal.py - Journal entry endpoints.

POST /journal            - submit entry, run AI pipeline, return insights (blocking)
POST /journal/stream     - submit entry, stream SSE progress events + final result
GET  /journal/insights   - paginated AI insight history
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
    logger.info("POST /journal", extra={"user_id": user_id, "mood_score": body.mood_score})
    try:
        result = await create_journal_entry(
            user_id=user_id,
            text=body.text,
            mood_score=body.mood_score,
        )
        return JournalEntryResponse(**result)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    except Exception as exc:
        logger.error("Journal pipeline error",
            extra={"user_id": user_id, "error": str(exc)})
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
    """
    Streams Server-Sent Events (SSE) as the AI pipeline progresses.

    The client receives a sequence of events over a single long-lived HTTP
    connection, then the connection closes automatically after the final
    result event.

    Event sequence:
        event: status  data: analysing    <- entry saved, pipeline starting
        event: status  data: reflecting   <- Reflection agent running
        event: status  data: supporting   <- Support agent running
        event: status  data: finalising   <- Risk node running
        event: result  data: { ... }      <- complete JSON payload (same shape
                                             as the blocking endpoint response)

    Flutter integration:
        Use the `http` package with a streamed request, or the `eventsource`
        package. Parse each "data:" line as JSON. On event=="result" parse the
        payload and update your Riverpod state.

    Headers set on the response:
        Content-Type:    text/event-stream
        Cache-Control:   no-cache
        X-Accel-Buffering: no   <- disables nginx proxy buffering so events
                                    are delivered immediately, not batched
    """
    logger.info("POST /journal/stream",
        extra={"user_id": user_id, "mood_score": body.mood_score})

    return StreamingResponse(
        create_journal_entry_stream(
            user_id=user_id,
            text=body.text,
            mood_score=body.mood_score,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control":     "no-cache",
            "X-Accel-Buffering": "no",   # critical for nginx deployments
        },
    )


# ── GET /journal/insights ─────────────────────────────────────────────────────

@router.get(
    "/insights",
    response_model=InsightsResponse,
    summary="Retrieve AI insight history",
)
async def get_insights(
    limit:  int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0,  ge=0),
    user_id: str = Depends(get_current_user),
):
    supabase = get_supabase()
    try:
        res = (
            supabase.table("ai_insights")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
    except Exception as exc:
        logger.error("Insights fetch failed", extra={"error": str(exc)})
        raise HTTPException(status_code=500, detail="Could not fetch insights.")

    rows     = res.data or []
    insights = []

    for r in rows:
        try:
            alt = r.get("alternative_suggestions") or []
            if not alt:
                raw = r.get("raw_response") or {}
                alt = raw.get("alternative_suggestions") or []

            insights.append(InsightItem(
                id=r["id"],
                journal_entry_id=r.get("journal_entry_id"),
                detected_emotion=r.get("detected_emotion", ""),
                pattern_insight=r.get("pattern_insight", ""),
                relapse_risk_level=r.get("relapse_risk_level", "low"),
                recommendations=r.get("recommendations") or [],
                alternative_suggestions=alt,
                encouragement=r.get("encouragement", ""),
                created_at=r["created_at"],
            ))
        except Exception as exc:
            logger.warning("Skipping malformed insight row",
                extra={"row_id": r.get("id"), "error": str(exc)})

    logger.info("GET /journal/insights",
        extra={"user_id": user_id, "count": len(insights)})
    return InsightsResponse(insights=insights, total=len(insights))