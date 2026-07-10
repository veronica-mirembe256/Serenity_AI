"""
app/services/email_service.py — async SMTP email sender.

Supports:
  - Daily reminder emails
  - Inactivity alerts
  - Therapist/rehab escalation emails (consent-gated)

All email bodies are rendered from Jinja2 templates.
Privacy: escalation emails are only sent when user consent is TRUE.
"""

import aiosmtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime

from app.config import get_settings
from app.utils.prompt_loader import render_prompt
from app.logging_config.logger import get_logger

logger = get_logger(__name__)
settings = get_settings()


# ─────────────────────────────────────────────────────────────────────────────
# Core mailer
# ─────────────────────────────────────────────────────────────────────────────

async def _send_email(to_address: str, subject: str, html_body: str) -> bool:
    """
    Send an HTML email via SMTP. Returns True on success, False on failure.
    """
    message = MIMEMultipart("alternative")
    message["From"] = f"{settings.email_from_name} <{settings.email_from_address}>"
    message["To"] = to_address
    message["Subject"] = subject
    message.attach(MIMEText(html_body, "html"))

    try:
        await aiosmtplib.send(
            message,
            hostname=settings.smtp_host,
            port=settings.smtp_port,
            username=settings.smtp_user,
            password=settings.smtp_password,
            start_tls=True,
        )
        logger.info(
            "Email sent successfully",
            extra={"to": to_address, "subject": subject},
        )
        return True
    except Exception as exc:
        logger.error(
            "Email send failed",
            extra={"to": to_address, "subject": subject, "error": str(exc)},
        )
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Public email functions
# ─────────────────────────────────────────────────────────────────────────────

async def send_inactivity_reminder(
    to_address: str,
    user_name: str,
    days_inactive: int,
    streak: int,
    app_url: str = "https://app.recoverycompanion.app",
) -> bool:
    """Send a gentle inactivity reminder email."""
    html_body = render_prompt(
        "email_reminder.j2",
        user_name=user_name,
        days_inactive=days_inactive,
        streak=streak,
        app_url=app_url,
    )
    subject = f"We miss you, {user_name} 💙 — Come back to your recovery journey"
    return await _send_email(to_address, subject, html_body)


async def send_escalation_alert(
    therapist_email: str,
    user_name: str,
    therapist_name: str | None,
    days_inactive: int,
    risk_level: str,
    app_url: str = "https://app.recoverycompanion.app",
) -> bool:
    """
    Send an escalation alert to a therapist or rehab contact.

    IMPORTANT: Only call this function after verifying user consent.
    """
    html_body = render_prompt(
        "email_escalation.j2",
        user_name=user_name,
        therapist_name=therapist_name,
        days_inactive=days_inactive,
        risk_level=risk_level,
        app_url=app_url,
    )
    subject = f"[Recovery Companion] Wellness Alert — {user_name}"
    return await _send_email(therapist_email, subject, html_body)
