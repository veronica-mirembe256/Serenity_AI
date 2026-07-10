"""
app/utils/therapist_auth.py

Provides get_current_therapist() — a FastAPI dependency that:
  1. Validates the Bearer JWT via Supabase (same as get_current_user)
  2. Checks the resolved user_id exists in the `therapists` table
  3. Returns the therapist's full row (id, email, full_name, organisation)

This ensures therapist endpoints are completely separate from patient
endpoints — a patient JWT cannot access therapist routes and vice versa.
"""
import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger

logger  = get_logger(__name__)
_bearer = HTTPBearer()


async def get_current_therapist(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
    """
    Validates JWT and confirms the caller is a registered therapist.
    Returns the therapist row dict on success.
    Raises 401 if token invalid, 403 if user is not a therapist.
    """
    settings = get_settings()
    token    = credentials.credentials

    # ── Step 1: validate JWT via Supabase ────────────────────────────────────
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(
                settings.supabase_url.rstrip("/") + "/auth/v1/user",
                headers={
                    "apikey":        settings.supabase_service_role_key,
                    "Authorization": f"Bearer {token}",
                },
            )

        if resp.status_code != 200:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token.",
            )

        user_id = resp.json().get("id", "")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not identify user from token.",
            )

    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Therapist token validation failed", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials.",
        )

    # ── Step 2: confirm caller is in therapists table ────────────────────────
    supabase = get_supabase(service_role=True)
    try:
        res = (
            supabase.table("therapists")
            .select("*")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        therapist = res.data
    except Exception as exc:
        logger.error("Therapist lookup failed", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not verify therapist status.",
        )

    if not therapist:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied. This endpoint is for registered therapists only.",
        )

    return therapist


async def log_therapist_access(
    therapist_id: str,
    patient_id:   str,
    resource:     str,
) -> None:
    """
    FIX (privacy risk 1.3-C): Write an audit log entry every time a therapist
    accesses a patient's data. Called from each therapist route handler.
    Non-fatal — a logging failure never blocks the actual data response.
    """
    try:
        supabase = get_supabase(service_role=True)
        supabase.table("therapist_access_log").insert({
            "therapist_id": therapist_id,
            "patient_id":   patient_id,
            "resource":     resource,
        }).execute()
    except Exception as exc:
        logger.warning("Therapist access log failed (non-fatal)",
            extra={"therapist_id": therapist_id, "error": str(exc)})