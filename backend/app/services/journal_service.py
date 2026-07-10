"""
app/services/journal_service.py

Fixes applied in this version:
  FIX 2.2   — run_recovery_pipeline runs via asyncio.to_thread
  FIX 1.2-A — journal text encrypted at rest using Fernet before insert
  FIX RLS   — _save_entry, _save_insight, _update_streak all use service_role
               client so RLS never blocks backend writes
  FIX NULL  — _load_profile and _load_progress handle None response from
               .maybe_single() when no row exists yet for a new user
"""
import asyncio
import json
import uuid
from datetime import date, datetime, timezone
from typing import Optional, AsyncGenerator

from app.config import get_settings
from app.db.supabase_client import get_supabase
from app.db.chroma_client import upsert_journal_entry
from app.agents.workflow import run_recovery_pipeline, run_recovery_pipeline_stream
from app.utils.encryption import encrypt_text, decrypt_text
from app.logging_config.logger import get_logger

logger   = get_logger(__name__)
settings = get_settings()


# ── Shared helpers ────────────────────────────────────────────────────────────

def _load_profile(supabase, user_id: str) -> dict:
    try:
        res = (
            supabase.table("user_profiles")
            .select("*")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        # FIX NULL: .maybe_single() returns None when no row exists (new user)
        if res is None:
            return {}
        return res.data or {}
    except Exception as e:
        logger.warning("Profile fetch failed", extra={"error": str(e)})
        return {}


def _load_progress(supabase, user_id: str) -> dict:
    try:
        res = (
            supabase.table("user_progress")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        # FIX NULL: .maybe_single() returns None when no row exists (new user)
        if res is None:
            return {}
        return res.data or {}
    except Exception as e:
        logger.warning("Progress fetch failed", extra={"error": str(e)})
        return {}


def _save_entry(supabase, entry_id: str, user_id: str, text: str, mood_score):
    # FIX RLS: use service_role so RLS policy never blocks backend insert
    admin = get_supabase(service_role=True)
    encrypted = encrypt_text(text)
    admin.table("journal_entries").insert({
        "id":         entry_id,
        "user_id":    user_id,
        "text":       encrypted,
        "mood_score": mood_score,
    }).execute()

def _upsert_chroma(entry_id, user_id, text, mood_score):
    try:
        upsert_journal_entry(
            entry_id=entry_id,
            user_id=user_id,
            text=text,
            metadata={
                # FIX: ChromaDB does not accept None — convert to 0 if missing
                "mood_score": mood_score if mood_score is not None else 0,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
        )
    except Exception as exc:
        logger.warning("Chroma upsert failed (non-fatal)", extra={"error": str(exc)})


def _save_insight(supabase, user_id, entry_id, result: dict):
    # FIX RLS: use service_role so RLS never blocks backend insert
    admin = get_supabase(service_role=True)
    try:
        admin.table("ai_insights").insert({
            "user_id":                 user_id,
            "journal_entry_id":        entry_id,
            "detected_emotion":        str(result.get("detected_emotion", "")),
            "pattern_insight":         str(result.get("pattern_insight", "")),
            "recommendations":         list(result.get("recommendations", [])),
            "alternative_suggestions": list(result.get("alternative_suggestions", [])),
            "encouragement":           str(result.get("encouragement_message", "")),
            "relapse_risk_level":      str(result.get("relapse_risk_level", "low")),
        }).execute()
    except Exception as exc:
        logger.warning("AI insight save failed", extra={"error": str(exc)})


def _update_streak(supabase, user_id: str, progress: dict) -> int:
    today      = date.today()
    last_entry = progress.get("last_entry_date")
    old_streak = progress.get("current_streak", 0)

    if last_entry:
        try:
            last_date = date.fromisoformat(last_entry)
            diff      = (today - last_date).days
            if diff == 0:
                new_streak = old_streak
            elif diff == 1:
                new_streak = old_streak + 1
            else:
                new_streak = 1
        except Exception:
            new_streak = 1
    else:
        new_streak = 1

    # FIX RLS: use service_role so RLS never blocks backend upsert
    admin = get_supabase(service_role=True)
    try:
        admin.table("user_progress").upsert({
            "user_id":         user_id,
            "current_streak":  new_streak,
            "longest_streak":  max(progress.get("longest_streak", 0), new_streak),
            "total_entries":   progress.get("total_entries", 0) + 1,
            "last_entry_date": today.isoformat(),
        }).execute()
    except Exception as exc:
        logger.warning("Progress update failed", extra={"error": str(exc)})

    return new_streak


# ── Blocking version ──────────────────────────────────────────────────────────

async def create_journal_entry(
    user_id:    str,
    text:       str,
    mood_score: Optional[int],
) -> dict:

    supabase = get_supabase()
    profile  = _load_profile(supabase, user_id)
    progress = _load_progress(supabase, user_id)

    user_name     = profile.get("display_name") or "Friend"
    recovery_type = profile.get("recovery_type") or "both"
    challenges    = profile.get("challenges") or []

    entry_id = str(uuid.uuid4())
    try:
        _save_entry(supabase, entry_id, user_id, text, mood_score)
        logger.info("Journal entry saved", extra={"entry_id": entry_id})
    except Exception as exc:
        logger.error("Failed to save journal entry", extra={"error": str(exc)})
        raise

    _upsert_chroma(entry_id, user_id, text, mood_score)

    # FIX 2.2: run blocking LLM pipeline in thread pool — never blocks event loop
    result = await asyncio.to_thread(
        run_recovery_pipeline,
        user_id=user_id,
        user_name=user_name,
        recovery_type=recovery_type,
        challenges=challenges,
        current_entry=text,
        mood_score=mood_score,
        streak=progress.get("current_streak", 0),
    )

    _save_insight(supabase, user_id, entry_id, result)
    new_streak = _update_streak(supabase, user_id, progress)

    return {
        "entry_id":                entry_id,
        "detected_emotion":        str(result.get("detected_emotion", "")),
        "pattern_insight":         str(result.get("pattern_insight", "")),
        "relapse_risk_level":      str(result.get("relapse_risk_level", "low")),
        "recommendations":         list(result.get("recommendations", [])),
        "alternative_suggestions": list(result.get("alternative_suggestions", [])),
        "encouragement_message":   str(result.get("encouragement_message", "")),
        "streak":                  new_streak,
        "escalation_triggered":    bool(result.get("escalation_required", False)),
    }


# ── Streaming version ─────────────────────────────────────────────────────────

async def create_journal_entry_stream(
    user_id:    str,
    text:       str,
    mood_score: Optional[int],
) -> AsyncGenerator[str, None]:
    supabase = get_supabase()
    profile  = _load_profile(supabase, user_id)
    progress = _load_progress(supabase, user_id)

    user_name     = profile.get("display_name") or "Friend"
    recovery_type = profile.get("recovery_type") or "both"
    challenges    = profile.get("challenges") or []

    entry_id = str(uuid.uuid4())
    try:
        _save_entry(supabase, entry_id, user_id, text, mood_score)
        logger.info("Journal entry saved (stream)", extra={"entry_id": entry_id})
    except Exception as exc:
        logger.error("Failed to save journal entry (stream)", extra={"error": str(exc)})
        yield "event: error\ndata: Could not save your entry. Please try again.\n\n"
        return

    _upsert_chroma(entry_id, user_id, text, mood_score)

    async for sse_line in run_recovery_pipeline_stream(
        user_id=user_id,
        user_name=user_name,
        recovery_type=recovery_type,
        challenges=challenges,
        current_entry=text,
        mood_score=mood_score,
        streak=progress.get("current_streak", 0),
    ):
        if sse_line.startswith("event: result"):
            try:
                data_line       = [l for l in sse_line.split("\n") if l.startswith("data:")][0]
                pipeline_result = json.loads(data_line[len("data:"):].strip())

                _save_insight(supabase, user_id, entry_id, {
                    "detected_emotion":        pipeline_result.get("detected_emotion", ""),
                    "pattern_insight":         pipeline_result.get("pattern_insight", ""),
                    "relapse_risk_level":      pipeline_result.get("relapse_risk_level", "low"),
                    "recommendations":         pipeline_result.get("recommendations", []),
                    "alternative_suggestions": pipeline_result.get("alternative_suggestions", []),
                    "encouragement_message":   pipeline_result.get("encouragement_message", ""),
                })
                new_streak = _update_streak(supabase, user_id, progress)

                enriched = {**pipeline_result, "entry_id": entry_id, "streak": new_streak}
                yield f"event: result\ndata: {json.dumps(enriched)}\n\n"

            except Exception as exc:
                logger.error("Failed to enrich result SSE",
                    extra={"user_id": user_id, "error": str(exc)})
                yield sse_line
        else:
            yield sse_line