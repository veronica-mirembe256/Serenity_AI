"""
app/routes/auth.py - Authentication endpoints.
Calls Supabase Auth REST API directly via httpx (not the Python SDK).
"""
import httpx
from fastapi import APIRouter, HTTPException, Request, status  # FIX: added Request
from pydantic import BaseModel, EmailStr

from app.limiter import limiter  # FIX: import limiter instance
from app.config import get_settings
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/auth", tags=["Auth"])
logger = get_logger(__name__)
settings = get_settings()


def _headers() -> dict:
    return {
        "apikey": settings.supabase_anon_key,
        "Content-Type": "application/json",
    }

def _url(path: str) -> str:
    return settings.supabase_url.rstrip("/") + "/auth/v1" + path


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None
    therapist_email: str | None = None
    emergency_contact_email: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AuthResponse(BaseModel):
    access_token: str
    user_id: str
    display_name: str | None = None


@router.post("/register", response_model=AuthResponse, status_code=201,
             summary="Register a new user account")
async def register(request: Request, body: RegisterRequest):  # FIX: request param required by slowapi
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            # ─────────────────────────────
            # 1. SIGNUP
            # ─────────────────────────────
            resp = await client.post(
                _url("/signup"),
                headers=_headers(),
                json={
                    "email": body.email,
                    "password": body.password,
                    "options": {
                        "data": {
                            "display_name": body.display_name
                        }
                    }
                },
            )

            data = resp.json()

            logger.info("SUPABASE SIGNUP RESPONSE", extra={
                "status": resp.status_code,
                "response": data
            })

            if resp.status_code not in (200, 201):
                raise HTTPException(
                    status_code=400,
                    detail=data.get("error_description")
                    or data.get("msg")
                    or data.get("message")
                    or str(data),
                )

            user = data.get("user") or {}
            session = data.get("session") or {}

            user_id = user.get("id")
            access_token = session.get("access_token")

            # ─────────────────────────────
            # 2. AUTO LOGIN IF NO SESSION
            # ─────────────────────────────
            if not access_token:
                logger.warning("No session returned, attempting auto-login")

                login_resp = await client.post(
                    _url("/token?grant_type=password"),
                    headers=_headers(),
                    json={
                        "email": body.email,
                        "password": body.password,
                    },
                )

                login_data = login_resp.json()

                logger.info("AUTO LOGIN RESPONSE", extra={
                    "status": login_resp.status_code,
                    "response": login_data
                })

                access_token = login_data.get("access_token")
                user_id = (login_data.get("user") or {}).get("id")

                if not access_token:
                    raise HTTPException(
                        status_code=400,
                        detail="Account created but login failed.",
                    )

        except httpx.ConnectError as exc:
            logger.error("Network error", extra={"error": str(exc)})
            raise HTTPException(503, detail="Cannot reach Supabase.")
        except httpx.TimeoutException:
            raise HTTPException(504, detail="Supabase timed out.")

    # ─────────────────────────────
    # 3. CREATE PROFILE
    # ─────────────────────────────
    await _create_profile(
        user_id,
        body.display_name,
        access_token,
        therapist_email=body.therapist_email,
        emergency_contact_email=body.emergency_contact_email,
    )

    logger.info("User registered successfully", extra={"user_id": user_id})

    return AuthResponse(
        access_token=access_token,
        user_id=user_id,
        display_name=body.display_name,
    )


@router.post("/login", response_model=AuthResponse, summary="Sign in with email and password")
@limiter.limit("5/minute")  # FIX: rate limit applied — brute-force protection
async def login(request: Request, body: LoginRequest):  # FIX: request param required by slowapi
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            resp = await client.post(
                _url("/token?grant_type=password"),
                headers=_headers(),
                json={"email": body.email, "password": body.password},
            )
        except httpx.ConnectError as exc:
            logger.error("Network error reaching Supabase", extra={"error": str(exc)})
            raise HTTPException(503, detail="Cannot reach Supabase. Check internet.")
        except httpx.TimeoutException:
            raise HTTPException(504, detail="Supabase timed out.")

    data = resp.json()

    if resp.status_code != 200 or "error" in data:
        msg = data.get("error_description") or data.get("msg") or "Invalid email or password."
        logger.warning("Login failed", extra={"email": body.email, "error": msg})
        raise HTTPException(401, detail=msg)

    access_token = data.get("access_token", "")
    user_id      = (data.get("user") or {}).get("id", "")

    if not access_token:
        raise HTTPException(401, detail="Login failed - no token returned.")

    logger.info("User logged in", extra={"user_id": user_id})
    return AuthResponse(access_token=access_token, user_id=user_id)


async def _create_profile(
    user_id: str,
    display_name: str | None,
    access_token: str,
    therapist_email: str | None = None,
    emergency_contact_email: str | None = None,
) -> None:
    if not user_id:
        return

    base = settings.supabase_url.rstrip("/")
    service_key = settings.supabase_service_role_key

    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            # ─────────────────────────────
            # 1. CREATE PROFILE
            # ─────────────────────────────
            profile_resp = await client.post(
                f"{base}/rest/v1/user_profiles",
                headers=headers,
                json={
                    "id": user_id,
                    "display_name": display_name or "Friend",
                    "recovery_type": "both",
                    "challenges": [],
                    "goals": [],
                    "therapist_email": therapist_email,
                    "emergency_contact_email": emergency_contact_email,
                },
            )
            logger.info("PROFILE INSERT RESPONSE", extra={
                "status": profile_resp.status_code,
                "body": profile_resp.text,
                "user_id": user_id
            })

            if profile_resp.status_code not in (200, 201, 204):
                logger.error(
                    "Profile insert failed",
                    extra={
                        "status": profile_resp.status_code,
                        "response": profile_resp.text,
                        "user_id": user_id,
                    },
                )

            # ─────────────────────────────
            # 2. CREATE PROGRESS
            # ─────────────────────────────
            progress_resp = await client.post(
                f"{base}/rest/v1/user_progress",
                headers=headers,
                json={
                    "user_id": user_id,
                    "current_streak": 0,
                    "longest_streak": 0,
                    "total_entries": 0,
                },
            )

            if progress_resp.status_code not in (200, 201, 204):
                logger.warning(
                    "Progress insert failed",
                    extra={
                        "status": progress_resp.status_code,
                        "response": progress_resp.text,
                        "user_id": user_id,
                    },
                )

        except Exception as exc:
            logger.error(
                "Profile creation crashed",
                extra={"error": str(exc), "user_id": user_id},
            )