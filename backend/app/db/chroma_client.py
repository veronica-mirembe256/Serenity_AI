"""
app/db/chroma_client.py

FIX (production crash 2.1): Previously ChromaDB was configured without a
persistent path. Every container restart wiped all journal embeddings,
silently breaking the RAG context for ALL users permanently.

Now uses PersistentClient so data survives restarts. The path is controlled
by the CHROMA_PERSIST_PATH env variable (default /data/chroma) which should
be mounted as a Docker volume.

FIX (security risk 1.2-B): Added token-based auth support via
CHROMA_AUTH_TOKEN env variable. When set, the server-mode client sends the
token on every request. For embedded (PersistentClient) mode, no network
auth is needed — the data is only accessible to the process itself.
"""
from __future__ import annotations
import chromadb
from chromadb.config import Settings as ChromaSettings
from app.config import get_settings
from app.logging_config.logger import get_logger

logger = get_logger(__name__)
_client: chromadb.ClientAPI | None = None


def _get_client() -> chromadb.ClientAPI:
    global _client
    if _client is not None:
        return _client

    settings = get_settings()
    persist_path = getattr(settings, "chroma_persist_path", "/data/chroma")
    chroma_mode  = getattr(settings, "chroma_mode", "persistent")   # "persistent" | "server"

    if chroma_mode == "server":
        # Remote server mode — used when ChromaDB runs as a separate container.
        # Requires CHROMA_SERVER_HOST, CHROMA_SERVER_PORT, CHROMA_AUTH_TOKEN in env.
        host  = getattr(settings, "chroma_server_host", "localhost")
        port  = int(getattr(settings, "chroma_server_port", 8000))
        token = getattr(settings, "chroma_auth_token", "")

        chroma_settings = ChromaSettings(
            chroma_client_auth_provider=(
                "chromadb.auth.token_authn.TokenAuthClientProvider"
                if token else None
            ),
            chroma_client_auth_credentials=token if token else None,
            anonymized_telemetry=False,
        )
        _client = chromadb.HttpClient(
            host=host,
            port=port,
            settings=chroma_settings,
        )
        logger.info("ChromaDB connected (server mode)",
            extra={"host": host, "port": port, "auth": bool(token)})
    else:
        # Embedded persistent mode — single-process, data stored on disk.
        # Simplest and most secure option: no network exposure at all.
        _client = chromadb.PersistentClient(
            path=persist_path,
            settings=ChromaSettings(anonymized_telemetry=False),
        )
        logger.info("ChromaDB connected (persistent mode)",
            extra={"path": persist_path})

    return _client


def _get_collection() -> chromadb.Collection:
    client = _get_client()
    from chromadb.utils import embedding_functions
    from app.config import get_settings
    s = get_settings()

    # Use OpenAI embeddings — no model download needed
    openai_ef = embedding_functions.OpenAIEmbeddingFunction(
        api_key=s.openai_api_key,
        model_name="text-embedding-3-small",
    )
    return client.get_or_create_collection(
        name="journal_entries",
        embedding_function=openai_ef,
        metadata={"hnsw:space": "cosine"},
    )


# ── Public API ────────────────────────────────────────────────────────────────

def upsert_journal_entry(
    entry_id: str,
    user_id:  str,
    text:     str,
    metadata: dict,
) -> None:
    collection = _get_collection()
    collection.upsert(
        ids=[entry_id],
        documents=[text],
        metadatas=[{"user_id": user_id, **metadata}],
    )


def retrieve_similar_entries(
    user_id:    str,
    query_text: str,
    n_results:  int = 5,
) -> list[dict]:
    collection = _get_collection()
    results = collection.query(
        query_texts=[query_text],
        n_results=n_results,
        where={"user_id": user_id},   # user isolation enforced here
    )
    docs      = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    return [{"text": d, **m} for d, m in zip(docs, metadatas)]


def delete_user_embeddings(user_id: str) -> int:
    """
    FIX (privacy risk 1.3-B): Delete ALL embeddings for a user.
    Called during account deletion so no data residue remains in ChromaDB
    after the Supabase rows are deleted.
    Returns the number of documents deleted.
    """
    collection = _get_collection()
    existing   = collection.get(where={"user_id": user_id})
    ids        = existing.get("ids", [])
    if ids:
        collection.delete(ids=ids)
        logger.info("ChromaDB embeddings deleted",
            extra={"user_id": user_id, "count": len(ids)})
    return len(ids)