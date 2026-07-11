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
    # FIX: these names didn't match what email_service.py actually exports
    # (send_inactivity_reminder / send_escalation_alert), so this import was
    # raising ImportError and crashing the entire scan before it processed
    # a single user.
    from app.services.email_service import send_inactivity_reminder, send_escalation_alert

    supabase = get_supabase(service_role=True)
    today    = date.today()
    summary  = {"scanned": 0, "reminders_sent": 0, "escalations_sent": 0, "errors": 0}
    offset   = 0

    while True:
        # ── Fetch one batch ───────────────────────────────────────────────────
        try:
            res = (
                supabase.table("user_progress")
                .select("user_id, last_entry_date, current_streak")
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

                # FIX: user_profiles has no `email` column — the previous
                # query always returned empty, so reminder emails silently
                # never sent to anyone. Email lives in Supabase Auth, so we
                # fetch it via the Admin API (requires the service_role
                # client, which `supabase` already is here).
                user_email = ""
                try:
                    auth_user = supabase.auth.admin.get_user_by_id(user_id)
                    user_email = getattr(getattr(auth_user, "user", None), "email", "") or ""
                except Exception as exc:
                    logger.warning("Auth email lookup failed for user",
                        extra={"user_id": user_id, "error": str(exc)})

            except Exception as exc:
                logger.warning("Consent/profile fetch failed for user",
                    extra={"user_id": user_id, "error": str(exc)})
                summary["errors"] += 1
                continue

            name = profile.get("display_name") or "Friend"

            # ── Reminder (1+ days inactive) ───────────────────────────────────
            if days_inactive >= reminder_days and consent.get("email_reminders") and user_email:
                try:
                    await send_inactivity_reminder(
                        to_address=user_email,
                        user_name=name,
                        days_inactive=days_inactive,
                        streak=row.get("current_streak", 0),
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

                # Latest risk level gives the recipient real context, and is
                # what the email_escalation.j2 template expects.
                risk_level = "unknown"
                try:
                    risk_res = (
                        supabase.table("ai_insights")
                        .select("relapse_risk_level")
                        .eq("user_id", user_id)
                        .order("created_at", desc=True)
                        .limit(1)
                        .maybe_single()
                        .execute()
                    )
                    if risk_res and risk_res.data:
                        risk_level = risk_res.data.get("relapse_risk_level", "unknown")
                except Exception as exc:
                    logger.warning("Risk level lookup failed for escalation",
                        extra={"user_id": user_id, "error": str(exc)})

                if consent.get("therapist_escalation") and therapist_email:
                    try:
                        await send_escalation_alert(
                            therapist_email=therapist_email,
                            user_name=name,
                            therapist_name=None,
                            days_inactive=days_inactive,
                            risk_level=risk_level,
                        )
                        summary["escalations_sent"] += 1
                    except Exception as exc:
                        logger.warning("Therapist escalation email failed",
                            extra={"user_id": user_id, "error": str(exc)})
                        summary["errors"] += 1

                if consent.get("rehab_escalation") and rehab_email:
                    try:
                        await send_escalation_alert(
                            therapist_email=rehab_email,
                            user_name=name,
                            therapist_name=None,
                            days_inactive=days_inactive,
                            risk_level=risk_level,
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