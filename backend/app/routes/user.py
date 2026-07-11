"""
app/routes/user.py  (additions/replacements only)

FIX (privacy risk 1.3-A): Added DELETE /user/account — GDPR erasure endpoint.
FIX (production crash 2.8): Emergency alert email moved to BackgroundTask.
FIX (therapist portal): Added POST /user/therapist-consent — patient grants
    or revokes therapist access from their own Settings page.

Add these to your existing user.py router. The existing endpoints
(GET /user/profile, PATCH /user/profile, etc.) are unchanged.
"""
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status
from pydantic import BaseModel, EmailStr
from typing import Optional

from app.utils.auth import get_current_user
from app.db.supabase_client import get_supabase
from app.services.user_service import delete_user_account, send_crisis_email_task
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/user", tags=["User"])
logger = get_logger(__name__)


# ── DELETE /user/account  (GDPR right to erasure) ────────────────────────────

@router.delete(
    "/account",
    summary="Permanently delete account and all associated data",
    status_code=200,
)
async def delete_account(
    user_id: str = Depends(get_current_user),
):
    """
    Deletes every row associated with this user across all tables and
    removes their ChromaDB embeddings, then deletes the Supabase Auth record.

    This action is IRREVERSIBLE. The frontend should show a confirmation
    dialog before calling this endpoint.
    """
    logger.warning("Account deletion requested", extra={"user_id": user_id})
    summary = await delete_user_account(user_id)
    return {
        "message": "Your account and all associated data have been permanently deleted.",
        "summary": summary,
    }


# ── POST /user/emergency-alert  (non-blocking) ────────────────────────────────

@router.post(
    "/emergency-alert",
    summary="Send crisis alert email to emergency contact (non-blocking)",
)
async def emergency_alert(
    background_tasks: BackgroundTasks,              # FIX 2.8: BackgroundTask
    user_id: str = Depends(get_current_user),
):
    # FIX (critical): anon client's SELECT was silently blocked by RLS,
    # so profile always came back empty and users with a real emergency
    # contact configured were incorrectly told to set one up — meaning the
    # crisis alert never actually sent.
    supabase = get_supabase(service_role=True)
    try:
        res = (
            supabase.table("user_profiles")
            .select("display_name, emergency_contact_email")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile = res.data or {}
    except Exception as exc:
        raise HTTPException(500, detail="Could not fetch profile.")

    contact_email = profile.get("emergency_contact_email")
    if not contact_email:
        raise HTTPException(
            status_code=400,
            detail="No emergency contact email set. "
                   "Please add one in Settings before using this feature.",
        )

    user_name = profile.get("display_name") or "A Serenity user"

    # FIX 2.8: Email sent in background — response returns IMMEDIATELY
    # so the user in distress is not left waiting on SMTP.
    background_tasks.add_task(
        send_crisis_email_task,
        to_email=contact_email,
        user_name=user_name,
    )

    logger.warning("Crisis alert queued", extra={"user_id": user_id})
    return {"message": "Emergency alert sent to your contact."}


# ── POST /user/therapist-consent  (patient grants/revokes therapist access) ───

class TherapistConsentRequest(BaseModel):
    therapist_email:      EmailStr
    consent_given:        bool
    journal_access_consent: bool = False   # extra toggle for raw journal text


@router.post(
    "/therapist-consent",
    summary="Grant or revoke a therapist's access to your data",
)
async def set_therapist_consent(
    body:    TherapistConsentRequest,
    user_id: str = Depends(get_current_user),
):
    """
    Patient-facing endpoint. Called from the Settings page when a patient
    types their therapist's email and taps "Grant Access" or "Revoke Access".

    Flow:
    1. Look up the therapist by email in the `therapists` table
    2. Upsert the therapist_patients row with consent_given = body.consent_given
    3. Return confirmation

    If the therapist is not registered, return 404 so the patient knows
    to ask their therapist to register first.
    """
    supabase = get_supabase(service_role=True)

    # Find therapist by email
    try:
        res = (
            supabase.table("therapists")
            .select("id, full_name")
            .eq("email", str(body.therapist_email))
            .maybe_single()
            .execute()
        )
        therapist = res.data
    except Exception:
        raise HTTPException(500, detail="Could not look up therapist.")

    if not therapist:
        raise HTTPException(
            status_code=404,
            detail="No therapist found with that email. "
                   "Please ask your therapist to register on Serenity first.",
        )

    # Upsert consent link
    try:
        supabase.table("therapist_patients").upsert({
            "therapist_id":          therapist["id"],
            "patient_id":            user_id,
            "consent_given":         body.consent_given,
            "journal_access_consent": body.journal_access_consent,
        }, on_conflict="therapist_id,patient_id").execute()
    except Exception as exc:
        raise HTTPException(500, detail=f"Could not update consent: {exc}")

    action = "granted" if body.consent_given else "revoked"
    logger.info(f"Therapist access {action}",
        extra={"patient": user_id, "therapist": therapist["id"]})

    return {
        "message":        f"Access {action} for {therapist.get('full_name', 'your therapist')}.",
        "therapist_id":   therapist["id"],
        "consent_given":  body.consent_given,
        "journal_access": body.journal_access_consent,
    }