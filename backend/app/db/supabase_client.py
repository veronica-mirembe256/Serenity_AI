"""
app/db/supabase_client.py

FIX (production crash 2.3): Previously get_supabase() created a NEW client
on every single request. Under load this exhausts Supabase's connection limit
(60 on free, 200 on Pro) and the app starts returning 500s for all DB calls.

Now we keep ONE client per role (anon / service_role) for the entire process
lifetime. Thread-safe because the Supabase Python client is stateless for
reads; writes are serialised at the DB level via RLS.
"""
from __future__ import annotations
from threading import Lock
from supabase import create_client, Client
from app.config import get_settings

_lock          = Lock()
_anon_client:  Client | None = None
_admin_client: Client | None = None


def get_supabase(service_role: bool = False) -> Client:
    """
    Return the process-level Supabase client.

    service_role=True  →  service role key (bypasses RLS, server-side only)
    service_role=False →  anon key        (respects RLS, safe for user ops)
    """
    global _anon_client, _admin_client
    settings = get_settings()

    with _lock:
        if service_role:
            if _admin_client is None:
                _admin_client = create_client(
                    settings.supabase_url,
                    settings.supabase_service_role_key,
                )
            return _admin_client
        else:
            if _anon_client is None:
                _anon_client = create_client(
                    settings.supabase_url,
                    settings.supabase_anon_key,
                )
            return _anon_client