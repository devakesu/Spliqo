"""FastAPI application factory, middleware configuration, and router initialization for Spliqo."""

import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.responses import Response
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app.api.v1 import api_v1_router
from app.core.config import settings
from app.core.infra.correlation import CorrelationIdFilter, CorrelationIdMiddleware
from app.core.infra.limiter import limiter
from app.core.security.security import (
    RequestSizeLimitMiddleware,
    SecurityHeadersMiddleware,
)

logger = logging.getLogger(__name__)

# Configure root logger with correlation ID filter
_root_logger = logging.getLogger()
_correlation_id_filter = CorrelationIdFilter()
_root_logger.addFilter(_correlation_id_filter)
for _handler in _root_logger.handlers:
    _handler.addFilter(_correlation_id_filter)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None]:
    """Manage application startup and shutdown lifecycle events."""
    logger.info("Spliqo application starting up (Environment: %s)", settings.environment)
    yield
    logger.info("Spliqo application shutting down gracefully")


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/api/v1/docs" if settings.debug else None,
    redoc_url=None,
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
allow_credentials = True
if "*" in origins:
    if settings.debug:
        allow_credentials = False
    else:
        raise RuntimeError(
            "CRITICAL: Wildcard origin '*' is not allowed when allow_credentials is True.",
        )

if settings.proxy_headers:
    app.add_middleware(
        ProxyHeadersMiddleware,
        trusted_hosts=settings.forwarded_allow_ips,
    )

app.add_middleware(CorrelationIdMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestSizeLimitMiddleware)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Request-ID",
        "X-Correlation-ID",
    ],
    expose_headers=["X-Request-ID"],
)

app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)


def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    """Handle RateLimitExceeded exceptions by returning a 429 JSON response.

    Args:
        request: Incoming FastAPI HTTP request.
        exc: The RateLimitExceeded exception instance.

    Returns:
        Response: 429 Too Many Requests JSON response.
    """
    _ = request
    detail_msg = "Rate limit exceeded. Please try again later."
    if isinstance(exc, RateLimitExceeded) and exc.detail:
        detail_msg = str(exc.detail)

    return JSONResponse(
        status_code=429,
        content={"detail": detail_msg},
        headers={"Retry-After": "60"},
    )


app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)  # type: ignore[arg-type]

# Mount API Routers
app.include_router(api_v1_router, prefix="/api/v1")


@app.get(
    "/",
    summary="Root Service Index",
    include_in_schema=False,
)
async def root_index() -> dict[str, Any]:
    """Returns application name and operational status."""
    return {
        "app": settings.app_name,
        "version": settings.app_version,
        "status": "operational",
    }
