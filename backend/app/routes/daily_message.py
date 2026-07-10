"""
app/routes/daily_message.py

GET /daily-message — returns a personalised daily message for the user.
This endpoint was missing — the service existed but had no route.
"""
from fastapi import APIRouter, Depends
from app.utils.auth import get_current_user
from app.services.daily_message_service import generate_daily_message
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/daily-message", tags=["Daily Message"])
logger = get_logger(__name__)


@router.get("", summary="Get personalised daily message for the logged-in user")
async def get_daily_message(
    user_id: str = Depends(get_current_user),
):
    logger.info("GET /daily-message", extra={"user_id": user_id})
    result = await generate_daily_message(user_id)
    return result