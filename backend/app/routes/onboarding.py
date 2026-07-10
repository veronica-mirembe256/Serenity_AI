from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger
from app.utils.auth import get_current_user  # FIX: import auth dependency

router = APIRouter(prefix="/onboarding", tags=["Onboarding"])
logger = get_logger(__name__)


class OnboardingRequest(BaseModel):
    # FIX: user_id removed from request body — derived from token instead
    recovery_type: str
    challenges: list[str] = []
    goals: list[str] = []


@router.post("")
async def complete_onboarding(
    body: OnboardingRequest,
    user_id: str = Depends(get_current_user),  # FIX: authenticated user_id only
):
    supabase = get_supabase(service_role=True)

    try:
        res = (
            supabase.table("user_profiles")
            .update({
                "recovery_type": body.recovery_type,
                "challenges": body.challenges,
                "goals": body.goals,
            })
            .eq("id", user_id)
            .execute()
        )

        if not res:
            raise HTTPException(400, detail="Failed to update profile")

        return {"message": "Onboarding completed"}

    except Exception as e:
        logger.error("Onboarding failed", extra={"error": str(e)})
        raise HTTPException(500, detail="Onboarding error")