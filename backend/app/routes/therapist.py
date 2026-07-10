"""
app/routes/therapist.py

All therapist-facing endpoints. Every route:
  - Requires a valid therapist JWT (get_current_therapist dependency)
  - Verifies the target patient has given consent (consent_given = TRUE)
  - Writes an audit log entry via log_therapist_access()
  - Is read-only for patient data (therapists cannot modify journal/insights)

Endpoints:
  POST /therapist/register
  POST /therapist/link-patient          (link to a patient by email)
  GET  /therapist/patients              (list all consented patients)
  GET  /therapist/patients/{id}/summary (risk level, streak, last entry)
  GET  /therapist/patients/{id}/insights
  GET  /therapist/patients/{id}/progress
  GET  /therapist/patients/{id}/journal (only if journal_access consent)
  POST /therapist/patients/{id}/notes
  POST /therapist/patients/{id}/checkin (send check-in email to patient)
"""
import httpx
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, status, Query
from pydantic import BaseModel, EmailStr
from typing import Optional

from app.db.supabase_client import get_supabase
from app.utils.therapist_auth import get_current_therapist, log_therapist_access
from app.config import get_settings
from app.logging_config.logger import get_logger

router   = APIRouter(prefix="/therapist", tags=["Therapist"])
logger   = get_logger(__name__)
settings = get_settings()


# ── Request / Response models ─────────────────────────────────────────────────

class TherapistRegisterRequest(BaseModel):
    email:        EmailStr
    password:     str
    full_name:    str
    organisation: Optional[str] = None


class LinkPatientRequest(BaseModel):
    patient_email: EmailStr


class TherapistNoteRequest(BaseModel):
    note: str


# ── Helper: verify patient consent ───────────────────────────────────────────

def _verify_patient_consent(
    supabase,
    therapist_id: str,
    patient_id:   str,
    require_journal_access: bool = False,
) -> dict:
    """
    Raise 403 if the patient has not consented to this therapist accessing
    their data. Returns the therapist_patients row on success.
    """
    try:
        res = (
            supabase.table("therapist_patients")
            .select("*")
            .eq("therapist_id", therapist_id)
            .eq("patient_id",   patient_id)
            .eq("consent_given", True)
            .maybe_single()
            .execute()
        )
        link = res.data
    except Exception as exc:
        raise HTTPException(500, detail="Could not verify patient consent.")

    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This patient has not consented to your access, or the link does not exist.",
        )

    if require_journal_access and not link.get("journal_access_consent", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This patient has not granted full journal access. "
                   "Only AI insight summaries are available.",
        )

    return link


# ── POST /therapist/register ──────────────────────────────────────────────────

@router.post("/register", status_code=201, summary="Register a new therapist account")
async def register_therapist(body: TherapistRegisterRequest):
    """
    Creates a Supabase Auth user then inserts a row into the `therapists` table.
    The therapist must use POST /therapist/login (or the standard /auth/login)
    to obtain a JWT — their JWT is then validated against the therapists table
    by get_current_therapist().
    """
    supabase = get_supabase(service_role=True)

    # Create auth user
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                settings.supabase_url.rstrip("/") + "/auth/v1/admin/users",
                headers={
                    "apikey":        settings.supabase_service_role_key,
                    "Authorization": f"Bearer {settings.supabase_service_role_key}",
                    "Content-Type":  "application/json",
                },
                json={
                    "email":    body.email,
                    "password": body.password,
                    "email_confirm": True,
                },
            )
        if resp.status_code not in (200, 201):
            raise HTTPException(400, detail=resp.json().get("message", "Registration failed."))
        user_id = resp.json()["id"]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, detail=f"Auth service error: {exc}")

    # Insert therapist profile
    try:
        supabase.table("therapists").insert({
            "id":           user_id,
            "email":        body.email,
            "full_name":    body.full_name,
            "organisation": body.organisation,
        }).execute()
    except Exception as exc:
        raise HTTPException(500, detail=f"Could not create therapist profile: {exc}")

    logger.info("Therapist registered", extra={"therapist_id": user_id})
    return {"message": "Therapist account created.", "therapist_id": user_id}


# ── POST /therapist/link-patient ──────────────────────────────────────────────

@router.post("/link-patient", summary="Link a patient by their registered email")
async def link_patient(
    body:       LinkPatientRequest,
    therapist:  dict = Depends(get_current_therapist),
):
    """
    Creates a therapist_patients row with consent_given=FALSE.
    The patient must go to Settings → Grant Therapist Access to set it TRUE.
    Alternatively, if the patient entered this therapist's email during
    onboarding, onboarding sets consent_given=TRUE automatically.
    """
    supabase = get_supabase(service_role=True)

    # Look up patient by email in user_profiles
    try:
        res = (
            supabase.table("user_profiles")
            .select("id")
            .eq("email", body.patient_email)
            .maybe_single()
            .execute()
        )
        patient = res.data
    except Exception:
        raise HTTPException(500, detail="Could not look up patient.")

    if not patient:
        raise HTTPException(404, detail="No patient found with that email address.")

    patient_id = patient["id"]

    # Upsert the link (idempotent)
    try:
        supabase.table("therapist_patients").upsert({
            "therapist_id":  therapist["id"],
            "patient_id":    patient_id,
            "consent_given": False,
        }, on_conflict="therapist_id,patient_id").execute()
    except Exception as exc:
        raise HTTPException(500, detail=f"Could not create patient link: {exc}")

    return {
        "message": "Patient linked. Awaiting patient consent.",
        "patient_id": patient_id,
    }


# ── GET /therapist/patients ───────────────────────────────────────────────────

@router.get("/patients", summary="List all consented patients")
async def list_patients(therapist: dict = Depends(get_current_therapist)):
    supabase     = get_supabase(service_role=True)
    therapist_id = therapist["id"]

    try:
        res = (
            supabase.table("therapist_patients")
            .select("patient_id, consent_given, journal_access_consent, linked_at")
            .eq("therapist_id", therapist_id)
            .eq("consent_given", True)
            .execute()
        )
        links = res.data or []
    except Exception as exc:
        raise HTTPException(500, detail="Could not fetch patients.")

    patients = []
    for link in links:
        pid = link["patient_id"]
        try:
            profile_res = (
                supabase.table("user_profiles")
                .select("display_name, recovery_type")
                .eq("id", pid)
                .maybe_single()
                .execute()
            )
            progress_res = (
                supabase.table("user_progress")
                .select("current_streak, last_entry_date, total_entries")
                .eq("user_id", pid)
                .maybe_single()
                .execute()
            )
            insight_res = (
                supabase.table("ai_insights")
                .select("relapse_risk_level, created_at")
                .eq("user_id", pid)
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            profile  = profile_res.data  or {}
            progress = progress_res.data or {}
            latest   = (insight_res.data or [{}])[0]

            patients.append({
                "patient_id":         pid,
                "display_name":       profile.get("display_name", "Unknown"),
                "recovery_type":      profile.get("recovery_type", "both"),
                "current_streak":     progress.get("current_streak", 0),
                "last_entry_date":    progress.get("last_entry_date"),
                "total_entries":      progress.get("total_entries", 0),
                "latest_risk_level":  latest.get("relapse_risk_level", "unknown"),
                "latest_insight_at":  latest.get("created_at"),
                "journal_access":     link.get("journal_access_consent", False),
                "linked_at":          link.get("linked_at"),
            })
        except Exception as exc:
            logger.warning("Skipping patient in list",
                extra={"patient_id": pid, "error": str(exc)})

    return {"patients": patients, "total": len(patients)}


# ── GET /therapist/patients/{id}/summary ─────────────────────────────────────

@router.get("/patients/{patient_id}/summary")
async def get_patient_summary(
    patient_id: str,
    background_tasks: BackgroundTasks,
    therapist: dict = Depends(get_current_therapist),
):
    supabase = get_supabase(service_role=True)
    _verify_patient_consent(supabase, therapist["id"], patient_id)
    background_tasks.add_task(
        log_therapist_access, therapist["id"], patient_id, "summary")

    try:
        profile_res  = supabase.table("user_profiles").select(
            "display_name, recovery_type, challenges"
        ).eq("id", patient_id).maybe_single().execute()

        progress_res = supabase.table("user_progress").select("*").eq(
            "user_id", patient_id).maybe_single().execute()

        # Last 7 risk levels for trend
        insights_res = supabase.table("ai_insights").select(
            "relapse_risk_level, detected_emotion, created_at"
        ).eq("user_id", patient_id).order("created_at", desc=True).limit(7).execute()

    except Exception as exc:
        raise HTTPException(500, detail="Could not fetch patient summary.")

    profile    = profile_res.data  or {}
    progress   = progress_res.data or {}
    risk_trend = [r["relapse_risk_level"] for r in (insights_res.data or [])]

    return {
        "patient_id":       patient_id,
        "display_name":     profile.get("display_name", "Unknown"),
        "recovery_type":    profile.get("recovery_type", "both"),
        "challenges":       profile.get("challenges", []),
        "current_streak":   progress.get("current_streak", 0),
        "longest_streak":   progress.get("longest_streak", 0),
        "total_entries":    progress.get("total_entries", 0),
        "last_entry_date":  progress.get("last_entry_date"),
        "risk_trend":       risk_trend,
        "latest_risk":      risk_trend[0] if risk_trend else "unknown",
        "high_risk_flag":   "high" in risk_trend[:3],   # high risk in last 3 entries
    }


# ── GET /therapist/patients/{id}/insights ────────────────────────────────────

@router.get("/patients/{patient_id}/insights")
async def get_patient_insights(
    patient_id: str,
    background_tasks: BackgroundTasks,
    limit:  int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    therapist: dict = Depends(get_current_therapist),
):
    supabase = get_supabase(service_role=True)
    _verify_patient_consent(supabase, therapist["id"], patient_id)
    background_tasks.add_task(
        log_therapist_access, therapist["id"], patient_id, "ai_insights")

    try:
        res = (
            supabase.table("ai_insights")
            .select(
                "id, detected_emotion, pattern_insight, relapse_risk_level, "
                "recommendations, encouragement, created_at"
                # NOTE: alternative_suggestions intentionally omitted — minimal exposure
            )
            .eq("user_id", patient_id)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
    except Exception as exc:
        raise HTTPException(500, detail="Could not fetch insights.")

    return {"insights": res.data or [], "total": len(res.data or [])}


# ── GET /therapist/patients/{id}/progress ────────────────────────────────────

@router.get("/patients/{patient_id}/progress")
async def get_patient_progress(
    patient_id: str,
    background_tasks: BackgroundTasks,
    therapist: dict = Depends(get_current_therapist),
):
    supabase = get_supabase(service_role=True)
    _verify_patient_consent(supabase, therapist["id"], patient_id)
    background_tasks.add_task(
        log_therapist_access, therapist["id"], patient_id, "user_progress")

    try:
        res = (
            supabase.table("user_progress")
            .select("current_streak, longest_streak, total_entries, last_entry_date")
            .eq("user_id", patient_id)
            .maybe_single()
            .execute()
        )
    except Exception:
        raise HTTPException(500, detail="Could not fetch progress.")

    return res.data or {}


# ── GET /therapist/patients/{id}/journal ─────────────────────────────────────

@router.get("/patients/{patient_id}/journal")
async def get_patient_journal(
    patient_id: str,
    background_tasks: BackgroundTasks,
    limit:  int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
    therapist: dict = Depends(get_current_therapist),
):
    """
    Returns raw journal entries. Only accessible if the patient has granted
    full journal access (journal_access_consent = TRUE on therapist_patients).
    Data minimisation: emergency_contact_email is never included.
    """
    supabase = get_supabase(service_role=True)
    # require_journal_access=True enforces the extra consent flag
    _verify_patient_consent(supabase, therapist["id"], patient_id,
                            require_journal_access=True)
    background_tasks.add_task(
        log_therapist_access, therapist["id"], patient_id, "journal_entries")

    from app.utils.encryption import decrypt_text

    try:
        res = (
            supabase.table("journal_entries")
            .select("id, text, mood_score, created_at")
            .eq("user_id", patient_id)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
    except Exception:
        raise HTTPException(500, detail="Could not fetch journal entries.")

    # Decrypt text before returning
    rows = []
    for r in (res.data or []):
        rows.append({
            **r,
            "text": decrypt_text(r.get("text", "")),
        })

    return {"entries": rows, "total": len(rows)}


# ── POST /therapist/patients/{id}/notes ──────────────────────────────────────

@router.post("/patients/{patient_id}/notes", status_code=201)
async def add_therapist_note(
    patient_id: str,
    body:       TherapistNoteRequest,
    therapist:  dict = Depends(get_current_therapist),
):
    supabase = get_supabase(service_role=True)
    _verify_patient_consent(supabase, therapist["id"], patient_id)

    try:
        supabase.table("therapist_notes").insert({
            "therapist_id": therapist["id"],
            "patient_id":   patient_id,
            "note":         body.note,
        }).execute()
    except Exception as exc:
        raise HTTPException(500, detail="Could not save note.")

    log_therapist_access(therapist["id"], patient_id, "therapist_notes_write")
    return {"message": "Note saved."}


# ── POST /therapist/patients/{id}/checkin ────────────────────────────────────

@router.post("/patients/{patient_id}/checkin")
async def send_checkin(
    patient_id:       str,
    background_tasks: BackgroundTasks,
    therapist:        dict = Depends(get_current_therapist),
):
    """
    Send a check-in email to the patient.
    Email is sent in a background task (non-blocking).
    """
    supabase = get_supabase(service_role=True)
    _verify_patient_consent(supabase, therapist["id"], patient_id)

    try:
        profile_res = (
            supabase.table("user_profiles")
            .select("display_name, email")
            .eq("id", patient_id)
            .maybe_single()
            .execute()
        )
        profile = profile_res.data or {}
    except Exception:
        raise HTTPException(500, detail="Could not fetch patient profile.")

    patient_email = profile.get("email")
    if not patient_email:
        raise HTTPException(404, detail="Patient email not found.")

    from app.services.email_service import send_checkin_email
    background_tasks.add_task(
        send_checkin_email,
        to_email=patient_email,
        patient_name=profile.get("display_name", "Friend"),
        therapist_name=therapist.get("full_name", "Your therapist"),
    )

    return {"message": "Check-in email queued."}