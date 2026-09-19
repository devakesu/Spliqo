"""API rate limiting configuration and key generation utilities for Spliqo."""

from typing import Any, cast

from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings


def get_user_or_ip(request: Request) -> str:
    """Derives the rate-limiting identifier key for an incoming HTTP request.

    Checks request.state for cached user_id or decoded JWT payload from verified
    authentication, falling back to client IP address for unauthenticated requests.

    Args:
        request: FastAPI/Starlette request instance.

    Returns:
        str: Rate-limiting bucket identifier string.
    """
    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return f"user:{user_id}"

    user_payload = cast(
        dict[str, Any] | None,
        getattr(request.state, "authenticated_user_payload", None),
    )
    if isinstance(user_payload, dict):
        user_id_val = user_payload.get("sub") or user_payload.get("id")
        if user_id_val:
            return f"user:{user_id_val}"

    return get_remote_address(request)


limiter = Limiter(
    key_func=get_user_or_ip,
    enabled=settings.enable_rate_limiting,
    storage_uri=settings.redis_url,  # type: ignore[call-arg]
)

