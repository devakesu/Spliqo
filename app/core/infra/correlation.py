"""Request correlation and tracing infrastructure for Spliqo FastAPI backend."""

import contextvars
import logging
import re
import uuid
from typing import Any

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

_REQUEST_ID_CTX: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="")
_SAFE_REQUEST_ID_REGEX = re.compile(r"^[a-zA-Z0-9\-_]{1,64}$")


def get_request_id() -> str:
    """Returns the current request correlation ID from contextvars."""
    return _REQUEST_ID_CTX.get()


class CorrelationIdFilter(logging.Filter):
    """Logging filter that attaches the current request_id to LogRecord instances."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = get_request_id()
        return True


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """Middleware that reads or generates X-Request-ID and binds it to contextvars."""

    async def dispatch(self, request: Request, call_next: Any) -> Response:
        incoming_id = request.headers.get("X-Request-ID") or request.headers.get("X-Correlation-ID")
        if incoming_id and _SAFE_REQUEST_ID_REGEX.match(incoming_id.strip()):
            request_id = incoming_id.strip()
        else:
            request_id = str(uuid.uuid4())

        token = _REQUEST_ID_CTX.set(request_id)
        request.state.request_id = request_id

        try:
            response = await call_next(request)
            response.headers["X-Request-ID"] = request_id
            return response
        finally:
            _REQUEST_ID_CTX.reset(token)

