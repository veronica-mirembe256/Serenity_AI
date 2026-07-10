"""
app/utils/auth.py - JWT validation using service_role_key via httpx.
The anon_key returns 403 for server-side introspection.
Service role key is required for admin-level token validation.
"""

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.logging_config.logger import get_logger

logger   = get_logger(__name__)
_bearer  = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> str:
    settings = get_settings()
    token    = credentials.credentials

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
            logger.warning(
                "Token validation failed",
                extra={"status": resp.status_code, "detail": resp.text[:300]},
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token. Please log in again.",
            )

        user_id = resp.json().get("id", "")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not identify user from token.",
            )

        return user_id

    except HTTPException:
        raise
    except httpx.ConnectError as exc:
        logger.error("Cannot reach Supabase", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service unreachable.",
        )
    except Exception as exc:
        logger.error("Token validation error", extra={"error": str(exc)})
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials.",
        )
