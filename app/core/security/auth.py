"""JWT Authentication dependency for FastAPI.

Extracts and validates Supabase-issued JWT tokens.
Derives caller user ID (`sub`) securely without trusting client-supplied identifiers.
"""

from typing import Annotated

import jwt
from fastapi import Header

from app.core.config import settings
from app.core.errors import UnauthorizedError


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
        # In test/dev environment, decode with configured secret or fallback
        secret = settings.supabase_jwt_secret or "super-secret-jwt-token-with-at-least-32-characters-long"
        payload = jwt.decode(
            token,
            secret,
            algorithms=["HS256"],
            options={"verify_aud": False},
        )
        user_id = payload.get("sub")
        if not user_id:
            raise UnauthorizedError("Token missing subject (sub) claim.")
        return str(user_id)
    except jwt.ExpiredSignatureError as err:
        raise UnauthorizedError("Authentication token has expired.") from err
    except jwt.PyJWTError as err:
        raise UnauthorizedError("Invalid authentication token.") from err
