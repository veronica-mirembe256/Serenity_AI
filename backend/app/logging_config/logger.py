"""
app/logging_config/logger.py — structured logging with contextual metadata.

Uses Python's built-in logging module with a JSON-friendly formatter so logs
can be ingested by any observability stack (Datadog, Loki, CloudWatch, etc.).
"""

import logging
import json
import traceback
from datetime import datetime, timezone
from typing import Any


class StructuredFormatter(logging.Formatter):
    """Emit log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        log_obj: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }

        # Attach any extra fields passed via `extra=` keyword
        for key, value in record.__dict__.items():
            if key not in {
                "args", "asctime", "created", "exc_info", "exc_text",
                "filename", "funcName", "id", "levelname", "levelno",
                "lineno", "message", "module", "msecs", "msg", "user_name",
                "pathname", "process", "processName", "relativeCreated",
                "stack_info", "thread", "threadName",
            }:
                log_obj[key] = value

        if record.exc_info:
            log_obj["exception"] = traceback.format_exception(*record.exc_info)

        return json.dumps(log_obj, default=str)


def get_logger(name: str) -> logging.Logger:
    """
    Return a named logger pre-configured with structured output.

    Usage:
        logger = get_logger(__name__)
        logger.info("Journal entry saved", extra={"user_id": uid, "entry_id": eid})
    """
    logger = logging.getLogger(name)

    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(StructuredFormatter())
        logger.addHandler(handler)

    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    return logger
