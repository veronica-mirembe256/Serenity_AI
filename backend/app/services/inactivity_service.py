"""
app/services/inactivity_service.py

FIX (production crash 2.4): The previous scan fetched ALL users in a single
query. With 500+ users this times out and no reminder/escalation emails are
sent at all.

Now processes users in batches of 100 so the scan never times out regardless
of user count. Progress is logged per batch.

FIX (production crash 2.8): Email sending is already async via aiosmtplib
(inherited from the existing service). No change needed for email itself,
but we now catch and log errors per-user so one bad email address does not
abort the entire scan.
"""
from datetime import date, timedelta
from app.db.supabase_client import get_supabase
from app.logging_config.logger import get_logger

logger = get_logger(__name__)

_BATCH_SIZE = 100


async def run_inactivity_scan(
    reminder_days:   int = 1,
    escalation_days: int = 7,
) -> dict:
    """
    Paginated inactivity scan.
    Returns a summary: { scanned, reminders_sent, escalations_sent, errors }
    """
    from app.services.email_service import send_reminder_email, send_escalation_email

    supabase = get_supabase(service_role=True)
    today    = date.today()
    summary  = {"scanned": 0, "reminders_sent": 0, "escalations_sent": 0, "errors": 0}
    offset   = 0

    while True:
        # ── Fetch one batch ───────────────────────────────────────────────────
        try:
            res = (
                supabase.table("user_progress")
                .select("user_id, last_entry_date")
                .not_.is_("last_entry_date", "null")   # skip users who never journaled
                .range(offset, offset + _BATCH_SIZE - 1)
                .execute()
            )
            batch = res.data or []
        except Exception as exc:
            logger.error("Inactivity scan batch fetch failed",
                extra={"offset": offset, "error": str(exc)})
            break

        if not batch:
            break   # no more users

        logger.info(f"Inactivity scan: processing batch",
            extra={"offset": offset, "count": len(batch)})

        # ── Process each user in the batch ────────────────────────────────────
        for row in batch:
            user_id    = row["user_id"]
            last_entry = row.get("last_entry_date")
            summary["scanned"] += 1

            if not last_entry:
                continue

            try:
                last_date    = date.fromisoformat(last_entry)
                days_inactive = (today - last_date).days
            except Exception:
                continue

            # ── Load consent + profile (only when inactive enough to matter) ─
            if days_inactive < reminder_days:
                continue

            try:
                consent_res = (
                    supabase.table("user_consents")
                    .select("*")
                    .eq("user_id", user_id)
                    .maybe_single()
                    .execute()
                )
                consent = consent_res.data or {}

                profile_res = (
                    supabase.table("user_profiles")
                    .select("display_name, therapist_email, rehab_contact_email")
                    .eq("id", user_id)
                    .maybe_single()
                    .execute()
                )
                profile = profile_res.data or {}

                # Fetch email from auth — user_profiles stores display_name only
                auth_res = (
                    supabase.table("user_profiles")
                    .select("email")
                    .eq("id", user_id)
                    .maybe_single()
                    .execute()
                )
                user_email = (auth_res.data or {}).get("email", "")

            except Exception as exc:
                logger.warning("Consent/profile fetch failed for user",
                    extra={"user_id": user_id, "error": str(exc)})
                summary["errors"] += 1
                continue

            name = profile.get("display_name") or "Friend"

            # ── Reminder (1+ days inactive) ───────────────────────────────────
            if days_inactive >= reminder_days and consent.get("email_reminders") and user_email:
                try:
                    await send_reminder_email(
                        to_email=user_email,
                        user_name=name,
                        days_inactive=days_inactive,
                    )
                    summary["reminders_sent"] += 1
                except Exception as exc:
                    logger.warning("Reminder email failed",
                        extra={"user_id": user_id, "error": str(exc)})
                    summary["errors"] += 1

            # ── Escalation (7+ days inactive) ─────────────────────────────────
            if days_inactive >= escalation_days:
                therapist_email = profile.get("therapist_email")
                rehab_email     = profile.get("rehab_contact_email")

                if consent.get("therapist_escalation") and therapist_email:
                    try:
                        await send_escalation_email(
                            to_email=therapist_email,
                            user_name=name,
                            days_inactive=days_inactive,
                            recipient_type="therapist",
                        )
                        summary["escalations_sent"] += 1
                    except Exception as exc:
                        logger.warning("Therapist escalation email failed",
                            extra={"user_id": user_id, "error": str(exc)})
                        summary["errors"] += 1

                if consent.get("rehab_escalation") and rehab_email:
                    try:
                        await send_escalation_email(
                            to_email=rehab_email,
                            user_name=name,
                            days_inactive=days_inactive,
                            recipient_type="rehab",
                        )
                        summary["escalations_sent"] += 1
                    except Exception as exc:
                        logger.warning("Rehab escalation email failed",
                            extra={"user_id": user_id, "error": str(exc)})
                        summary["errors"] += 1

        offset += _BATCH_SIZE

        # Stop if we got a partial batch (last page)
        if len(batch) < _BATCH_SIZE:
            break

    logger.info("Inactivity scan complete", extra=summary)
    return summary