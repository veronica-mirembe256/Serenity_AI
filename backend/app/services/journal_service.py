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
        if res is None:
            return {}
        return res.data or {}
    except Exception as e:
        logger.warning(f"⚠️ Profile fetch failed: {e}")
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
        if res is None:
            return {}
        return res.data or {}
    except Exception as e:
        logger.warning(f"⚠️ Progress fetch failed: {e}")
        return {}


def _save_entry(supabase, entry_id: str, user_id: str, text: str, mood_score):
    logger.info(f"💾 Saving entry {entry_id} for user {user_id}")
    admin = get_supabase(service_role=True)
    encrypted = encrypt_text(text)
    try:
        admin.table("journal_entries").insert({
            "id":         entry_id,
            "user_id":    user_id,
            "text":       encrypted,
            "mood_score": mood_score,
        }).execute()
        logger.info(f"✅ Entry {entry_id} saved successfully")
    except Exception as e:
        logger.error(f"❌ Failed to save entry {entry_id}: {e}")
        raise

def _upsert_chroma(entry_id, user_id, text, mood_score):
    logger.info(f"💾 Upserting chroma for {entry_id}")
    try:
        upsert_journal_entry(
            entry_id=entry_id,
            user_id=user_id,
            text=text,
            metadata={
                "mood_score": mood_score if mood_score is not None else 0,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        logger.info(f"✅ Chroma upserted for {entry_id}")
    except Exception as exc:
        logger.warning(f"⚠️ Chroma upsert failed (non-fatal): {exc}")


def _save_insight(supabase, user_id, entry_id, result: dict):
    logger.info("=" * 80)
    logger.info(f"💾 SAVING INSIGHT for entry {entry_id}")
    logger.info(f"👤 User: {user_id}")
    logger.info(f"📊 Result keys: {list(result.keys())}")
    logger.info(f"💡 Emotion: {result.get('detected_emotion')}")
    logger.info(f"📈 Risk: {result.get('relapse_risk_level')}")
    logger.info(f"📝 Recommendations: {len(result.get('recommendations', []))}")
    logger.info(f"💬 Encouragement: {result.get('encouragement_message', '')[:50]}...")
    logger.info("=" * 80)

    admin = get_supabase(service_role=True)
    try:
        data = {
            "user_id":                 user_id,
            "journal_entry_id":        entry_id,
            "detected_emotion":        str(result.get("detected_emotion", "")),
            "pattern_insight":         str(result.get("pattern_insight", "")),
            "recommendations":         list(result.get("recommendations", [])),
            "alternative_suggestions": list(result.get("alternative_suggestions", [])),
            "encouragement":           str(result.get("encouragement_message", "")),
            "relapse_risk_level":      str(result.get("relapse_risk_level", "low")),
        }

        logger.info(f"📦 Inserting data: {json.dumps(data, default=str)}")

        response = admin.table("ai_insights").insert(data).execute()

        logger.info(f"✅ Insight saved successfully for entry {entry_id}")
        logger.info(f"📦 Response: {response}")

        # Verify the insight was saved
        verify = (
            admin.table("ai_insights")
            .select("*")
            .eq("journal_entry_id", entry_id)
            .maybe_single()
            .execute()
        )
        if verify and verify.data:
            logger.info(f"✅ Verified insight exists with ID: {verify.data.get('id')}")
        else:
            logger.error(f"❌ WARNING: Insight not found after save!")

    except Exception as exc:
        logger.error(f"❌ AI insight save failed: {exc}", exc_info=True)
        logger.error(f"❌ Data that failed: {data}")


def _update_streak(supabase, user_id: str, progress: dict) -> int:
    today = date.today()
    last_entry = progress.get("last_entry_date")
    old_streak = progress.get("current_streak", 0)
    old_total = progress.get("total_entries", 0)

    # Calculate new streak
    if last_entry:
        try:
            last_date = date.fromisoformat(last_entry)
            diff = (today - last_date).days
            if diff == 0:
                new_streak = old_streak  # Same day, streak stays the same
            elif diff == 1:
                new_streak = old_streak + 1  # Next day, streak increases
            else:
                new_streak = 1  # Gap in entries, reset streak
        except Exception:
            new_streak = 1
    else:
        new_streak = 1

    new_total = old_total + 1
    new_longest = max(progress.get("longest_streak", 0), new_streak)

    logger.info(f"🔄 Updating streak for user {user_id}:")
    logger.info(f"   Old streak: {old_streak}, New streak: {new_streak}")
    logger.info(f"   Old total: {old_total}, New total: {new_total}")
    logger.info(f"   Last entry: {last_entry}")
    logger.info(f"   Today: {today}")

    admin = get_supabase(service_role=True)
    try:
        # First try to update existing record
        update_data = {
            "user_id": user_id,
            "current_streak": new_streak,
            "longest_streak": new_longest,
            "total_entries": new_total,
            "last_entry_date": today.isoformat(),
        }

        # Use upsert to handle both insert and update
        result = admin.table("user_progress").upsert(
            update_data,
            on_conflict="user_id"  # This handles the conflict on user_id
        ).execute()

        logger.info(f"✅ Streak updated successfully: {result.data if hasattr(result, 'data') else 'No data'}")

        # Verify the update
        verify = (
            admin.table("user_progress")
            .select("*")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if verify and verify.data:
            logger.info(f"✅ Verified progress: {verify.data}")
        else:
            logger.error("❌ Progress verification failed - no record found!")

    except Exception as exc:
        logger.error(f"❌ Progress update failed: {exc}", exc_info=True)
        # Try to insert directly if upsert fails
        try:
            admin.table("user_progress").insert({
                "user_id": user_id,
                "current_streak": new_streak,
                "longest_streak": new_longest,
                "total_entries": new_total,
                "last_entry_date": today.isoformat(),
            }).execute()
            logger.info(f"✅ Progress inserted successfully")
        except Exception as insert_exc:
            logger.error(f"❌ Progress insert also failed: {insert_exc}")

    return new_streak


# ── Blocking version ──────────────────────────────────────────────────────────

async def create_journal_entry(
    user_id:    str,
    text:       str,
    mood_score: Optional[int],
) -> dict:

    logger.info("=" * 80)
    logger.info("🚀 create_journal_entry STARTED")
    logger.info(f"👤 User ID: {user_id}")
    logger.info(f"📝 Text length: {len(text)}")
    logger.info("=" * 80)

    # FIX: use service_role client — the anon client was silently blocked by
    # RLS SELECT policies, so _load_profile/_load_progress always returned {}
    # and every entry silently fell back to "Friend" / recovery_type="both" /
    # streak=0, defeating personalisation even though the UI showed no error.
    supabase = get_supabase(service_role=True)
    profile  = _load_profile(supabase, user_id)
    progress = _load_progress(supabase, user_id)

    user_name     = profile.get("display_name") or "Friend"
    recovery_type = profile.get("recovery_type") or "both"
    challenges    = profile.get("challenges") or []

    entry_id = str(uuid.uuid4())
    logger.info(f"📝 Generated entry_id: {entry_id}")

    try:
        _save_entry(supabase, entry_id, user_id, text, mood_score)
        logger.info(f"✅ Journal entry saved: {entry_id}")
    except Exception as exc:
        logger.error(f"❌ Failed to save journal entry: {exc}")
        raise

    _upsert_chroma(entry_id, user_id, text, mood_score)

    logger.info("🤖 Running AI pipeline...")
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

    logger.info(f"✅ AI Pipeline complete. Result keys: {list(result.keys())}")

    _save_insight(supabase, user_id, entry_id, result)
    new_streak = _update_streak(supabase, user_id, progress)

    response = {
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

    logger.info("=" * 80)
    logger.info("✅ create_journal_entry COMPLETE")
    logger.info(f"📊 Response: {json.dumps(response, default=str)}")
    logger.info("=" * 80)

    return response


# ── Streaming version ─────────────────────────────────────────────────────────

async def create_journal_entry_stream(
    user_id:    str,
    text:       str,
    mood_score: Optional[int],
) -> AsyncGenerator[str, None]:

    logger.info("=" * 80)
    logger.info("🚀 create_journal_entry_stream STARTED")
    logger.info(f"👤 User ID: {user_id}")
    logger.info(f"📝 Text length: {len(text)}")
    logger.info("=" * 80)

    # FIX: use service_role client — same RLS-blocked read issue as the
    # blocking path above
    supabase = get_supabase(service_role=True)
    profile  = _load_profile(supabase, user_id)
    progress = _load_progress(supabase, user_id)

    user_name     = profile.get("display_name") or "Friend"
    recovery_type = profile.get("recovery_type") or "both"
    challenges    = profile.get("challenges") or []

    entry_id = str(uuid.uuid4())
    logger.info(f"📝 Generated entry_id: {entry_id}")

    try:
        _save_entry(supabase, entry_id, user_id, text, mood_score)
        logger.info(f"✅ Journal entry saved: {entry_id}")
    except Exception as exc:
        logger.error(f"❌ Failed to save journal entry: {exc}")
        yield "event: error\ndata: Could not save your entry. Please try again.\n\n"
        return

    _upsert_chroma(entry_id, user_id, text, mood_score)

    logger.info("🤖 Running AI pipeline (streaming)...")

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
                logger.info("📡 Received result event from pipeline")
                data_line = [l for l in sse_line.split("\n") if l.startswith("data:")][0]
                pipeline_result = json.loads(data_line[len("data:"):].strip())

                logger.info(f"📊 Pipeline result: {json.dumps(pipeline_result, default=str)}")
                logger.info(f"💡 Emotion: {pipeline_result.get('detected_emotion')}")
                logger.info(f"📈 Risk: {pipeline_result.get('relapse_risk_level')}")
                logger.info(f"📝 Recommendations: {len(pipeline_result.get('recommendations', []))}")

                logger.info("💾 Saving insight to database...")
                _save_insight(supabase, user_id, entry_id, {
                    "detected_emotion":        pipeline_result.get("detected_emotion", ""),
                    "pattern_insight":         pipeline_result.get("pattern_insight", ""),
                    "relapse_risk_level":      pipeline_result.get("relapse_risk_level", "low"),
                    "recommendations":         pipeline_result.get("recommendations", []),
                    "alternative_suggestions": pipeline_result.get("alternative_suggestions", []),
                    "encouragement_message":   pipeline_result.get("encouragement_message", ""),
                })
                logger.info("✅ Insight saved")

                new_streak = _update_streak(supabase, user_id, progress)
                logger.info(f"✅ Streak updated to {new_streak}")

                enriched = {**pipeline_result, "entry_id": entry_id, "streak": new_streak}

                logger.info("=" * 80)
                logger.info("✅ Streaming pipeline COMPLETE")
                logger.info(f"📊 Enriched result: {json.dumps(enriched, default=str)}")
                logger.info("=" * 80)

                yield f"event: result\ndata: {json.dumps(enriched)}\n\n"

            except Exception as exc:
                logger.error(f"❌ Failed to enrich result SSE: {exc}", exc_info=True)
                yield sse_line
        else:
            yield sse_line