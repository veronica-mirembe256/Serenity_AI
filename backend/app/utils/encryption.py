"""
app/utils/encryption.py

FIX (security risk 1.2-A): Journal entries were stored as plaintext.
A database breach or misconfigured RLS policy would expose raw clinical data.

This module provides transparent encrypt/decrypt using Fernet (AES-128-CBC
+ HMAC-SHA256). The key is loaded from the JOURNAL_ENCRYPTION_KEY env var.

HOW TO GENERATE A KEY (run once, store in .env / secret manager):
    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

IMPORTANT:
- If JOURNAL_ENCRYPTION_KEY is not set, encryption is SKIPPED and a warning
  is logged. This keeps the app functional in development without the key,
  but encryption MUST be enabled in production.
- Existing plaintext rows are not automatically migrated. Run the migration
  script (see database/migrate_encrypt_journals.py) once after setting the key.
- The Fernet token is base64-url encoded, so it is safe to store as TEXT in
  Supabase without any additional encoding.
"""
import base64
import logging
from functools import lru_cache

logger = logging.getLogger(__name__)

try:
    from cryptography.fernet import Fernet, InvalidToken
    _CRYPTO_AVAILABLE = True
except ImportError:
    _CRYPTO_AVAILABLE = False
    logger.warning("cryptography package not installed — journal encryption disabled")


@lru_cache(maxsize=1)
def _get_fernet():
    """Return Fernet instance or None if key is not configured."""
    if not _CRYPTO_AVAILABLE:
        return None

    from app.config import get_settings
    settings = get_settings()
    key = getattr(settings, "journal_encryption_key", "") or ""

    if not key:
        logger.warning(
            "JOURNAL_ENCRYPTION_KEY not set — journal text stored as plaintext. "
            "Set this variable in production."
        )
        return None

    try:
        return Fernet(key.encode() if isinstance(key, str) else key)
    except Exception as exc:
        logger.error("Invalid JOURNAL_ENCRYPTION_KEY — encryption disabled",
            extra={"error": str(exc)})
        return None


def encrypt_text(plaintext: str) -> str:
    """
    Encrypt a string. Returns the ciphertext as a UTF-8 string.
    If encryption is not configured, returns the plaintext unchanged
    (with a warning already emitted by _get_fernet()).
    """
    fernet = _get_fernet()
    if fernet is None:
        return plaintext
    return fernet.encrypt(plaintext.encode("utf-8")).decode("utf-8")


def decrypt_text(ciphertext: str) -> str:
    """
    Decrypt a string previously encrypted with encrypt_text().
    If the value looks like plaintext (not a Fernet token), returns it as-is
    so that existing unencrypted rows still work after the key is added.
    Falls back to ciphertext on any decryption error.
    """
    fernet = _get_fernet()
    if fernet is None:
        return ciphertext

    try:
        return fernet.decrypt(ciphertext.encode("utf-8")).decode("utf-8")
    except Exception:
        # Value is either plaintext (legacy row) or corrupt — return as-is
        logger.debug("decrypt_text: returning value as plaintext (not a Fernet token)")
        return ciphertext