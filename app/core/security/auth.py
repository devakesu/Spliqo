"""JWT Authentication dependency for FastAPI.

Extracts and validates Supabase-issued asymmetric JWT tokens (ECC P-256 / ES256)
against the project's JWKS endpoint. Derives caller user ID (`sub`) securely
without trusting client-supplied identifiers.
"""

from typing import Annotated

import jwt
from fastapi import Header
from jwt import PyJWKClient

from app.core.config import settings
from app.core.errors import UnauthorizedError

_jwk_client: PyJWKClient | None = None


def get_jwk_client() -> PyJWKClient:
    """Return the cached PyJWKClient configured for Supabase ECC (P-256) JWKS."""
    global _jwk_client
    if _jwk_client is None:
        _jwk_client = PyJWKClient(
            settings.resolved_jwks_url,
            cache_keys=True,
            lifespan=3600,
        )
    return _jwk_client


def set_jwk_client(client: PyJWKClient | None) -> None:
    """Override or reset the PyJWKClient (primarily for testing)."""
    global _jwk_client
    _jwk_client = client


def get_current_user_id(
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    """Extract and verify authenticated user UUID from Authorization header."""
    if not authorization or not authorization.startswith("Bearer "):
        raise UnauthorizedError("Missing or malformed Authorization header.")

    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise UnauthorizedError("Empty bearer token.")

    try:
        signing_key = get_jwk_client().get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["ES256"],
            issuer=settings.resolved_jwt_issuer,
            audience=settings.supabase_jwt_audience,
        )
        user_id = payload.get("sub")
        if not user_id:
            raise UnauthorizedError("Token missing subject (sub) claim.")
        return str(user_id)
    except jwt.ExpiredSignatureError as err:
        raise UnauthorizedError("Authentication token has expired.") from err
    except jwt.PyJWTError as err:
        raise UnauthorizedError("Invalid authentication token.") from err
