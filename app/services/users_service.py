"""Service layer for user profile retrieval and FLE-encrypted phone storage."""

from typing import Any

from app.core.config import settings
from app.core.database import get_db_connection
from app.core.errors import NotFoundError
from app.core.security.fle import compute_blind_index, get_envelope_encryptor
from app.repositories import users_repo
from app.schemas.users import UpdateProfileRequest, UserProfileResponse


def mask_phone_number(e164_phone: str) -> str:
    """Return a privacy-safe masked phone string (e.g. +91••••••3210)."""
    if len(e164_phone) <= 4:
        return "••••"
    prefix = e164_phone[:3] if e164_phone.startswith("+") and len(e164_phone) > 7 else ""
    last_four = e164_phone[-4:]
    hidden_count = max(4, len(e164_phone) - len(prefix) - 4)
    return f"{prefix}{'•' * hidden_count}{last_four}"


async def _to_profile_response(
    user_id: str,
    row: dict[str, Any],
) -> UserProfileResponse:
    """Map database row to UserProfileResponse, decrypting phone only to mask it."""
    encrypted_phone: bytes | None = row.get("phone_number_encrypted")
    masked_phone: str | None = None
    if encrypted_phone:
        encryptor = get_envelope_encryptor()
        plaintext_phone = await encryptor.decrypt(
            payload=bytes(encrypted_phone),
            associated_data=user_id.encode("utf-8"),
        )
        masked_phone = mask_phone_number(plaintext_phone)

    return UserProfileResponse(
        id=str(row["id"]),
        display_name=str(row["display_name"]),
        has_phone_number=encrypted_phone is not None,
        masked_phone_number=masked_phone,
    )


async def get_my_profile(user_id: str) -> UserProfileResponse:
    """Retrieve the authenticated caller's profile."""
    async with get_db_connection() as conn:
        row = await users_repo.get_user_profile(conn, user_id)
        if not row:
            raise NotFoundError("User profile not found.")
        return await _to_profile_response(user_id=user_id, row=row)


async def upsert_my_profile(
    user_id: str,
    data: UpdateProfileRequest,
) -> UserProfileResponse:
    """Update display_name and optionally encrypt & store phone_number via FLE."""
    phone_encrypted: bytes | None = None
    phone_bidx: str | None = None

    if data.phone_number is not None:
        # SECURITY: Encrypt confidential phone number using Infisical KMS FLE,
        # bound to user_id as AAD to prevent ciphertext transplantation.
        encryptor = get_envelope_encryptor()
        phone_encrypted = await encryptor.encrypt(
            plaintext=data.phone_number,
            associated_data=user_id.encode("utf-8"),
        )
        phone_bidx = compute_blind_index(
            plaintext=data.phone_number,
            key=settings.fle_blind_index_key,
        )

    async with get_db_connection() as conn, conn.transaction():
        row = await users_repo.upsert_user_profile(
            conn=conn,
            user_id=user_id,
            display_name=data.display_name,
            phone_encrypted=phone_encrypted,
            phone_bidx=phone_bidx,
        )

    return await _to_profile_response(user_id=user_id, row=row)
