"""
app/routes/admin.py — Internal / system endpoints.

POST /admin/inactivity-scan — triggers the inactivity detection scan.

In production, this endpoint should be:
  a) Protected by a secret header key, OR
  b) Not exposed publicly (called internally by a scheduler).

A simple secret-key guard is implemented here via a header check.
"""

from fastapi import APIRouter, Header, HTTPException, status
from app.config import get_settings
from app.services.inactivity_service import run_inactivity_scan
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/admin", tags=["Admin"])
logger = get_logger(__name__)
settings = get_settings()


@router.post(
    "/inactivity-scan",
    summary="[Internal] Run inactivity detection and send notifications",
)
async def trigger_inactivity_scan(
    x_admin_key: str = Header(..., alias="X-Admin-Key"),
):
    """
    Scans all users for inactivity and dispatches reminder / escalation emails.

    Requires header: X-Admin-Key matching SECRET_KEY in environment.
    Intended to be called by a cron job or scheduler — not by end users.
    """
    if x_admin_key != settings.secret_key:
        logger.warning("Unauthorized inactivity scan attempt")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin key.",
        )

    logger.info("Inactivity scan triggered via admin endpoint")
    summary = await run_inactivity_scan()
    return {"status": "completed", "summary": summary}
