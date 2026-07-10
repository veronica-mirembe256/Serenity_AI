"""
app/config.py — centralised settings loaded from environment variables.
All secrets and tuneable parameters live here; nothing is hardcoded.
"""

from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── Application ───────────────────────────────────────────────────────────
    app_name: str = "Serenity"
    app_env: str = "production"
    secret_key: str
    debug: bool = False

    # ── Supabase ──────────────────────────────────────────────────────────────
    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str

    # ── LLM ───────────────────────────────────────────────────────────────────
    openai_api_key: str
    openai_model: str = "gpt-4o"
    openai_embedding_model: str = "text-embedding-3-small"

    # ── ChromaDB ──────────────────────────────────────────────────────────────
    chroma_host: str = "localhost"
    chroma_port: int = 8000
    chroma_collection_journal: str = "journal_entries"

    # ── Email ─────────────────────────────────────────────────────────────────
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_user: str
    smtp_password: str
    email_from_name: str = "Serenity"
    email_from_address: str

    # ── Inactivity ────────────────────────────────────────────────────────────
    inactivity_reminder_days: int = 1
    inactivity_escalation_days: int = 7


@lru_cache
def get_settings() -> Settings:
    return Settings()
