from fastapi import APIRouter, Depends
from app.utils.auth import get_current_user          # FIX: auth dependency
from app.utils.models import ConsentRequest          # FIX: use existing Pydantic model
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger

router = APIRouter(prefix="/consent", tags=["Consent"])
logger = get_logger(__name__)


@router.post("")
async def save_consent(
    body: ConsentRequest,
    user_id: str = Depends(get_current_user),        # FIX: authenticated user only
):
    # FIX: use service_role client — anon client's write was silently/loudly
    # blocked by RLS WITH CHECK (auth.uid() is null for the anon client, so
    # it never matches user_id). Same root-cause pattern as journal/progress.
    supabase = get_supabase(service_role=True)
    supabase.table("user_consents").upsert({
        "user_id": user_id,
        **body.model_dump(),
    }).execute()

    logger.info("Consent updated", extra={"user_id": user_id})
    return {"status": "saved"}