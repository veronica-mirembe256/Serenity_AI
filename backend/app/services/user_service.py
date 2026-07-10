"""
app/services/user_service.py

FIX (privacy risk 1.3-A & 1.3-B):
  DELETE /user/account — GDPR right-to-erasure endpoint.
  Deletes ALL user data across Supabase tables AND ChromaDB embeddings,
  then deletes the Supabase Auth user record.

FIX (production crash 2.8):
  send_crisis_email_background() — moves email sending to a FastAPI
  BackgroundTask so a slow/failing SMTP server never blocks the HTTP response.
"""
import httpx
from app.config import get_settings
from app.db.supabase_client import get_supabase
from app.db.chroma_client import delete_user_embeddings
from app.logging_config.logger import get_logger

logger   = get_logger(__name__)
settings = get_settings()

# Tables to purge on account deletion — order matters for FK constraints
_TABLES_TO_PURGE = [
    ("notification_log",  "user_id"),
    ("ai_insights",       "user_id"),
    ("journal_entries",   "user_id"),
    ("user_consents",     "user_id"),
    ("user_progress",     "user_id"),
    ("therapist_patients","patient_id"),   # unlink from any therapist
    ("user_profiles",     "id"),
]


async def delete_user_account(user_id: str) -> dict:
    """
    Full GDPR erasure:
    1. Delete all Supabase rows belonging to the user
    2. Delete all ChromaDB embeddings for the user
    3. Delete the Supabase Auth user (requires service role key)

    Returns a summary dict for the API response.
    """
    supabase = get_supabase(service_role=True)
    summary  = {}

    # ── Step 1: purge Supabase tables ────────────────────────────────────────
    for table, col in _TABLES_TO_PURGE:
        try:
            res = (
                supabase.table(table)
                .delete()
                .eq(col, user_id)
                .execute()
            )
            deleted = len(res.data) if res.data else 0
            summary[table] = deleted
            logger.info(f"Deleted {deleted} rows from {table}",
                extra={"user_id": user_id})
        except Exception as exc:
            logger.error(f"Failed to delete from {table}",
                extra={"user_id": user_id, "error": str(exc)})
            summary[table] = "error"

    # ── Step 2: purge ChromaDB embeddings ────────────────────────────────────
    try:
        chroma_deleted = delete_user_embeddings(user_id)
        summary["chroma_embeddings"] = chroma_deleted
    except Exception as exc:
        logger.error("Failed to delete ChromaDB embeddings",
            extra={"user_id": user_id, "error": str(exc)})
        summary["chroma_embeddings"] = "error"

    # ── Step 3: delete Supabase Auth user ────────────────────────────────────
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.delete(
                settings.supabase_url.rstrip("/") + f"/auth/v1/admin/users/{user_id}",
                headers={
                    "apikey":        settings.supabase_service_role_key,
                    "Authorization": f"Bearer {settings.supabase_service_role_key}",
                },
            )
        if resp.status_code in (200, 204):
            summary["auth_user"] = "deleted"
            logger.info("Auth user deleted", extra={"user_id": user_id})
        else:
            summary["auth_user"] = f"error:{resp.status_code}"
            logger.error("Auth user deletion failed",
                extra={"user_id": user_id, "status": resp.status_code})
    except Exception as exc:
        logger.error("Auth user deletion exception",
            extra={"user_id": user_id, "error": str(exc)})
        summary["auth_user"] = "error"

    return summary


async def send_crisis_email_task(
    to_email:       str,
    user_name:      str,
    contact_name:   str | None = None,
) -> None:
    """
    FIX (production crash 2.8): Crisis emails are now sent in a
    FastAPI BackgroundTask — a slow or failing SMTP server no longer
    blocks the HTTP response seen by the user in distress.

    This function is the actual email sender; it is passed to
    BackgroundTasks.add_task() by the route handler.
    """
    import aiosmtplib
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText

    subject = f"🚨 Crisis Alert — {user_name} needs support"
    greeting = f"Dear {contact_name}," if contact_name else "Dear Emergency Contact,"

    html = f"""
    <html><body style="font-family:sans-serif;max-width:600px;margin:auto;">
      <div style="background:#fee2e2;border-left:4px solid #dc2626;padding:16px;border-radius:8px;">
        <h2 style="color:#dc2626;margin:0 0 8px;">Crisis Alert</h2>
        <p style="margin:0;">{greeting}</p>
        <p>{user_name} has triggered an emergency alert from the Serenity app
        and may need immediate support. Please reach out as soon as possible.</p>
        <p>If you believe they are in immediate danger, please contact emergency
        services (999) right away.</p>
      </div>
      <p style="color:#6b7280;font-size:12px;margin-top:24px;">
        Sent automatically by Serenity Recovery Companion.
        This message was triggered by the user.
      </p>
    </body></html>
    """

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = f"{settings.email_from_name} <{settings.email_from_address}>"
    msg["To"]      = to_email
    msg.attach(MIMEText(html, "html"))

    try:
        await aiosmtplib.send(
            msg,
            hostname=settings.smtp_host,
            port=settings.smtp_port,
            username=settings.smtp_username,
            password=settings.smtp_password,
            use_tls=True,
        )
        logger.info("Crisis email sent", extra={"to": to_email, "user": user_name})
    except Exception as exc:
        logger.error("Crisis email failed",
            extra={"to": to_email, "error": str(exc)})