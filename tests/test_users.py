"""Tests for authenticated user profile endpoints, validation, and FLE encryption."""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from httpx import AsyncClient

from app.core.config import settings
from app.core.security.fle import get_envelope_encryptor
from app.schemas.users import UpdateProfileRequest
from app.services.users_service import mask_phone_number
from tests.conftest import TEST_EC_PRIVATE_KEY


def _make_auth_header(user_id: str) -> dict[str, str]:
    token = jwt.encode(
        {
            "sub": user_id,
            "role": "authenticated",
            "aud": settings.supabase_jwt_audience,
            "iss": settings.resolved_jwt_issuer,
        },
        TEST_EC_PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": "test-p256-key"},
    )
    return {"Authorization": f"Bearer {token}"}


def test_update_profile_request_normalizes_and_validates() -> None:
    """Validates NFC normalization, control-char stripping, and E.164 phone parsing."""
    req = UpdateProfileRequest(
        display_name="  Priya\x00 Sharma  ",
        phone_number="+91 98765-43210",
    )
    assert req.display_name == "Priya Sharma"
    assert req.phone_number == "+919876543210"

    with pytest.raises(ValueError, match="E.164"):
        UpdateProfileRequest(display_name="Priya", phone_number="9876543210")

    with pytest.raises(ValueError):
        UpdateProfileRequest(display_name="   ")


def test_mask_phone_number() -> None:
    """Ensures phone numbers are masked safely without exposing raw digits."""
    assert mask_phone_number("+919876543210") == "+91••••••3210"
    assert mask_phone_number("1234") == "••••"


@pytest.mark.asyncio
async def test_profile_requires_authentication(async_client: AsyncClient) -> None:
    """Unauthenticated requests to profile endpoints return 401."""
    res_get = await async_client.get("/v1/users/me/profile")
    res_put = await async_client.put(
        "/v1/users/me/profile",
        json={"display_name": "Priya"},
    )
    assert res_get.status_code == 401
    assert res_put.status_code == 401


@pytest.mark.asyncio
async def test_update_profile_encrypts_phone(async_client: AsyncClient) -> None:
    """Verifies PUT /v1/users/me/profile encrypts phone via FLE and masks it in response."""
    encryptor = get_envelope_encryptor()
    user_id = "00000000-0000-0000-0000-000000000010"

    mock_conn = MagicMock()

    @asynccontextmanager
    async def fake_tx() -> AsyncGenerator[None]:
        yield

    mock_conn.transaction = fake_tx

    @asynccontextmanager
    async def fake_get_db() -> AsyncGenerator[MagicMock]:
        yield mock_conn

    async def fake_upsert(**kwargs: object) -> dict[str, object]:
        encrypted = kwargs["phone_encrypted"]
        assert isinstance(encrypted, bytes)
        decrypted = await encryptor.decrypt(
            payload=encrypted,
            associated_data=user_id.encode("utf-8"),
        )
        assert decrypted == "+919876543210"
        return {
            "id": user_id,
            "display_name": kwargs["display_name"],
            "phone_number_encrypted": encrypted,
        }

    with (
        patch("app.core.config.settings.enable_rate_limiting", False),
        patch("app.services.users_service.get_db_connection", fake_get_db),
        patch("app.repositories.users_repo.upsert_user_profile", AsyncMock(side_effect=fake_upsert)),
    ):
        response = await async_client.put(
            "/v1/users/me/profile",
            headers=_make_auth_header(user_id),
            json={
                "display_name": "Priya",
                "phone_number": "+91 9876543210",
            },
        )

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == user_id
    assert payload["display_name"] == "Priya"
    assert payload["has_phone_number"] is True
    assert payload["masked_phone_number"] == "+91••••••3210"
    assert "9876543210" not in response.text
