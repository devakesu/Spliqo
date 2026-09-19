"""Security headers and HTTP request size protection middleware for Spliqo.

Enforces HTTP Security Headers (CSP, HSTS, X-Frame-Options, Permissions-Policy)
and enforces a 10MB payload size limit on incoming request bodies to prevent Denial-of-Service.
"""

import logging
from typing import ClassVar

from fastapi import HTTPException, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import JSONResponse
from starlette.types import Message

logger = logging.getLogger(__name__)

# 10 MB maximum request payload size limit
MAX_REQUEST_BODY_SIZE = 10 * 1024 * 1024


def _check_content_length(content_length: str | None) -> Response | None:
    """Validates if the declared Content-Length exceeds allowable payload size."""
    if not content_length:
        return None
    try:
        if int(content_length) > MAX_REQUEST_BODY_SIZE:
            logger.warning(
                "Request payload exceeded max size: %s bytes",
                content_length,
            )
            return JSONResponse(
                status_code=413,
                content={
                    "detail": (
                        "Payload too large. "
                        "Maximum allowed request payload is 10MB."
                    ),
                },
            )
    except ValueError:
        pass
    return None


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware that attaches strict security headers and dynamic cache-control policies."""

    STATIC_ROUTES: ClassVar[set[str]] = {
        "/favicon.ico",
        "/robots.txt",
        "/sitemap.xml",
    }

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Processes request and attaches security and cache control headers to response.

        Args:
            request: Incoming HTTP Request instance.
            call_next: Next request endpoint handler.

        Returns:
            Response: HTTP response with added security headers.
        """
        response = await call_next(request)

        # Security Headers
        headers = response.headers
        headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; "
            "font-src 'self' data:; "
            "img-src 'self' data: https: blob:; "
            "connect-src 'self' https: wss:; "
            "frame-ancestors 'none'; "
            "form-action 'self'; "
            "base-uri 'self'; "
            "object-src 'none'; "
            "upgrade-insecure-requests;"
        )
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "DENY"
        headers["X-XSS-Protection"] = "1; mode=block"
        headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        headers["Permissions-Policy"] = (
            "camera=(), microphone=(), geolocation=(), payment=(), "
            "usb=(), display-capture=(), accelerometer=(), gyroscope=()"
        )
        headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains; preload"
        )
        headers["X-Permitted-Cross-Domain-Policies"] = "none"
        headers["Cross-Origin-Opener-Policy"] = "same-origin"

        path = request.url.path
        if path.startswith("/static/") or path in self.STATIC_ROUTES:
            headers["Cross-Origin-Resource-Policy"] = "cross-origin"
            headers["Cache-Control"] = (
                "public, max-age=86400, stale-while-revalidate=604800"
            )
        else:
            headers["Cross-Origin-Resource-Policy"] = "same-origin"
            if path.startswith("/api/"):
                headers["Cache-Control"] = "no-store, max-age=0"

        headers["Server"] = "Spliqo-Engine"
        return response


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Middleware preventing payload size abuse by rejecting bodies > 10MB."""

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Enforces Content-Length limits on incoming request payloads.

        Args:
            request: Incoming HTTP Request instance.
            call_next: Next request handler endpoint.

        Returns:
            Response: 413 JSONResponse if payload exceeds limit, or downstream Response.
        """
        early_rejection = _check_content_length(
            request.headers.get("content-length"),
        )
        if early_rejection is not None:
            return early_rejection

        bytes_received = 0
        original_receive = request._receive

        async def limited_receive() -> Message:
            nonlocal bytes_received
            message = await original_receive()
            if message["type"] == "http.request":
                body = message.get("body", b"")
                bytes_received += len(body)
                if bytes_received > MAX_REQUEST_BODY_SIZE:
                    logger.warning(
                        "Streaming request payload exceeded max size: %s bytes",
                        bytes_received,
                    )
                    raise HTTPException(
                        status_code=413,
                        detail=(
                            "Payload too large. "
                            "Maximum allowed request payload is 10MB."
                        ),
                    )
            return message

        request._receive = limited_receive
        try:
            return await call_next(request)
        except HTTPException as exc:
            if exc.status_code == 413:
                return JSONResponse(
                    status_code=413,
                    content={"detail": exc.detail},
                )
            raise
