"""
app/main.py — FastAPI application entry point.
"""

import dns_patch
dns_patch.apply()

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from slowapi import _rate_limit_exceeded_handler

from slowapi.errors import RateLimitExceeded

from app.config import get_settings
from app.logging_config.logger import get_logger
from app.routes import auth, journal, user, progress, admin, onboarding, consent
from app.routes import therapist
from app.routes import daily_message   # FIX: register missing daily message route

logger   = get_logger(__name__)
settings = get_settings()

from app.limiter import limiter  # FIX: import from dedicated module


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"]    = "nosniff"
        response.headers["X-Frame-Options"]           = "DENY"
        response.headers["X-XSS-Protection"]          = "1; mode=block"
        response.headers["Referrer-Policy"]           = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"]        = "geolocation=(), microphone=()"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        "Recovery Companion API starting up",
        extra={"env": settings.app_env, "model": settings.openai_model},
    )
    yield
    logger.info("Recovery Companion API shutting down")


app = FastAPI(
    title="Recovery Companion API",
    description=(
        "AI-powered recovery companion backend. "
        "Supports addiction and mental health recovery through "
        "journaling, pattern detection, personalised support, "
        "progress tracking, and proactive escalation."
    ),
    version="2.0.0",
    # Show docs in all environments during development
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# Rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Security headers
app.add_middleware(SecurityHeadersMiddleware)

# CORS — read from env, default to * for development
_raw_origins = getattr(settings, "allowed_origins", "") or ""
if _raw_origins and _raw_origins != "*":
    _origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]
else:
    _origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(
        "Unhandled exception",
        extra={
            "path":   request.url.path,
            "method": request.method,
            "error":  str(exc),
        },
        exc_info=True,
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "An unexpected error occurred.", "detail": None},
    )


# Routers
app.include_router(auth.router)
app.include_router(journal.router)
app.include_router(user.router)
app.include_router(progress.router)
app.include_router(admin.router)
app.include_router(onboarding.router)
app.include_router(consent.router)
app.include_router(therapist.router)
app.include_router(daily_message.router)   # FIX: was missing


@app.get("/health", tags=["System"], summary="API health check")
async def health():
    return {
        "status":  "healthy",
        "app":     settings.app_name,
        "env":     settings.app_env,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8080,
        reload=settings.debug,
        log_level="debug" if settings.debug else "info",
    )