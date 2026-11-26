"""Unit tests for Field-Level Encryption (FLE), KMS Envelope Encryption, and strict config."""

import base64
import os
from pathlib import Path

import httpx
import jwt
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.security.auth import get_current_user_id
from app.core.security.fle import (
    ENVELOPE_MAGIC,
    EnvelopeEncryptor,
    FLEDecryptionError,
    FLEKeyError,
    compute_blind_index,
    decrypt_field,
    encrypt_field,
)
from app.core.security.kms import InfisicalKMSClient, KMSAuthError


@pytest.fixture
def valid_key() -> bytes:
    """Generate a valid 256-bit (32-byte) key."""
    return os.urandom(32)


@pytest.fixture
def bidx_key() -> bytes:
    """Generate a valid 256-bit (32-byte) blind index key."""
    return os.urandom(32)


class _CountingKMSProvider:
    """In-memory KMS provider that tracks wrap/unwrap call counts."""

    def __init__(self) -> None:
        self.wrap_calls = 0
        self.unwrap_calls = 0
        self._kek = os.urandom(32)

    async def wrap_key(self, plaintext_dek: bytes) -> bytes:
        self.wrap_calls += 1
        return bytes(a ^ b for a, b in zip(plaintext_dek, self._kek, strict=True))

    async def unwrap_key(self, wrapped_dek: bytes) -> bytes:
        self.unwrap_calls += 1
        return bytes(a ^ b for a, b in zip(wrapped_dek, self._kek, strict=True))


def test_encryption_decryption_round_trip(valid_key: bytes) -> None:
    """Assert encrypting and then decrypting yields the original string."""
    phone = "+919876543210"
    encrypted_bytes = encrypt_field(phone, valid_key)
    assert isinstance(encrypted_bytes, bytes)
    assert len(encrypted_bytes) > 28  # Nonce (12) + ciphertext + tag (16)

    decrypted = decrypt_field(encrypted_bytes, valid_key)
    assert decrypted == phone


def test_encryption_with_associated_data(valid_key: bytes) -> None:
    """Assert authenticated associated data (e.g. user_id) is enforced during decryption."""
    upi_id = "host@okhdfcbank"
    user_id_1 = b"00000000-0000-0000-0000-000000000001"
    user_id_2 = b"00000000-0000-0000-0000-000000000002"

    encrypted_bytes = encrypt_field(upi_id, valid_key, associated_data=user_id_1)

    assert decrypt_field(encrypted_bytes, valid_key, associated_data=user_id_1) == upi_id

    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        decrypt_field(encrypted_bytes, valid_key, associated_data=user_id_2)

    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        decrypt_field(encrypted_bytes, valid_key, associated_data=None)


def test_tampered_ciphertext_fails(valid_key: bytes) -> None:
    """Assert modifying any byte in the ciphertext causes decryption to fail."""
    plaintext = "sensitive_data"
    encrypted = bytearray(encrypt_field(plaintext, valid_key))
    encrypted[-1] ^= 0x01

    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        decrypt_field(bytes(encrypted), valid_key)


def test_short_payload_fails(valid_key: bytes) -> None:
    """Assert payloads shorter than nonce + tag length are rejected."""
    with pytest.raises(FLEDecryptionError, match="Payload too short"):
        decrypt_field(b"too_short", valid_key)


def test_invalid_key_length() -> None:
    """Assert keys that are not 32 bytes are rejected."""
    short_key = b"short_key_16byte"
    with pytest.raises(FLEKeyError, match="Invalid key length"):
        encrypt_field("test", short_key)

    with pytest.raises(FLEKeyError, match="Invalid key length"):
        decrypt_field(b"0" * 30, short_key)

    with pytest.raises(FLEKeyError, match="Invalid key length"):
        compute_blind_index("test", short_key)


def test_blind_index_deterministic(bidx_key: bytes) -> None:
    """Assert blind indexing is deterministic and normalizes whitespace/case."""
    phone_1 = " +919876543210 "
    phone_2 = "+919876543210"
    bidx_1 = compute_blind_index(phone_1, bidx_key)
    bidx_2 = compute_blind_index(phone_2, bidx_key)
    assert bidx_1 == bidx_2
    assert len(bidx_1) == 64

    other_key = os.urandom(32)
    assert compute_blind_index(phone_1, other_key) != bidx_1


@pytest.mark.asyncio
async def test_envelope_encryption_caches_dek_without_per_payload_kms_calls() -> None:
    """Assert EnvelopeEncryptor wraps/unwraps DEKs once and never sends payloads to KMS."""
    kms = _CountingKMSProvider()
    encryptor = EnvelopeEncryptor(kms_provider=kms)
    aad = b"user-123"

    envelopes = [
        await encryptor.encrypt(f"upi_{i}@okaxis", associated_data=aad)
        for i in range(10)
    ]

    assert all(env.startswith(ENVELOPE_MAGIC) for env in envelopes)
    # Only ONE KMS wrap_key call for all 10 payloads
    assert kms.wrap_calls == 1
    assert kms.unwrap_calls == 0

    # Decrypting on same instance uses cached DEK (0 unwrap calls)
    for i, env in enumerate(envelopes):
        assert await encryptor.decrypt(env, associated_data=aad) == f"upi_{i}@okaxis"
    assert kms.unwrap_calls == 0

    # Cold-start instance unwraps the DEK exactly ONCE across all 10 payloads
    cold_encryptor = EnvelopeEncryptor(kms_provider=kms)
    for i, env in enumerate(envelopes):
        assert await cold_encryptor.decrypt(env, associated_data=aad) == f"upi_{i}@okaxis"
    assert kms.unwrap_calls == 1


@pytest.mark.asyncio
async def test_envelope_rejects_invalid_magic_or_wrong_aad() -> None:
    """Assert malformed envelopes or wrong AAD are rejected."""
    kms = _CountingKMSProvider()
    encryptor = EnvelopeEncryptor(kms_provider=kms)

    env = await encryptor.encrypt("host@okicici", associated_data=b"user-1")
    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        await encryptor.decrypt(env, associated_data=b"user-2")

    with pytest.raises(FLEDecryptionError, match="Unsupported or invalid envelope"):
        await encryptor.decrypt(b"BAD1" + b"\x00\x20" + os.urandom(64))


@pytest.mark.asyncio
async def test_infisical_kms_client_auth_and_wrap_unwrap() -> None:
    """Verify InfisicalKMSClient Universal Auth login, token reuse, and KMS encrypt/decrypt."""
    login_calls = 0
    encrypt_calls = 0
    decrypt_calls = 0
    secret_dek = os.urandom(32)
    wrapped_token = "kms-wrapped-ciphertext-blob"

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal login_calls, encrypt_calls, decrypt_calls
        if request.url.path == "/api/v1/auth/universal-auth/login":
            login_calls += 1
            return httpx.Response(200, json={"accessToken": "tok-1", "expiresIn": 300})
        if request.url.path == "/api/v1/kms/keys/kms-key-1/encrypt":
            encrypt_calls += 1
            assert request.headers["Authorization"] == "Bearer tok-1"
            return httpx.Response(200, json={"ciphertext": wrapped_token})
        if request.url.path == "/api/v1/kms/keys/kms-key-1/decrypt":
            decrypt_calls += 1
            assert request.headers["Authorization"] == "Bearer tok-1"
            return httpx.Response(
                200,
                json={"plaintext": base64.b64encode(secret_dek).decode("ascii")},
            )
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http_client:
        kms = InfisicalKMSClient(
            api_url="https://app.infisical.com/api",
            key_id="kms-key-1",
            client_id="cid",
            client_secret="csec",
            http_client=http_client,
        )
        wrapped = await kms.wrap_key(secret_dek)
        assert wrapped == wrapped_token.encode("utf-8")

        unwrapped = await kms.unwrap_key(wrapped)
        assert unwrapped == secret_dek

    assert login_calls == 1
    assert encrypt_calls == 1
    assert decrypt_calls == 1


@pytest.mark.asyncio
async def test_infisical_kms_client_auth_failure_raises() -> None:
    """Verify InfisicalKMSClient raises KMSAuthError on failed Universal Auth."""

    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"message": "Invalid credentials"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http_client:
        kms = InfisicalKMSClient(
            api_url="https://app.infisical.com/api",
            key_id="kms-key-1",
            client_id="bad",
            client_secret="bad",
            http_client=http_client,
        )
        with pytest.raises(KMSAuthError):
            await kms.wrap_key(os.urandom(32))


def test_strict_settings_ignores_dotenv_and_requires_infisical_vars(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Ensure .env files are ignored and missing Infisical secrets fail validation."""
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text(
        "SUPABASE_SECRET_KEY=sb_secret_from_dotenv\n"
        "INFISICAL_KMS_KEY_ID=from-dotenv\n",
    )
    monkeypatch.delenv("SUPABASE_SECRET_KEY", raising=False)
    monkeypatch.delenv("INFISICAL_KMS_KEY_ID", raising=False)

    with pytest.raises(ValidationError):
        Settings()  # type: ignore[call-arg]


def test_auth_rejects_legacy_hs256_jwt() -> None:
    """Ensure legacy symmetric HS256 JWTs are rejected when ES256 is enforced."""
    legacy_token = jwt.encode(
        {"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"},
        "super-secret-jwt-token-with-at-least-32-characters-long",
        algorithm="HS256",
    )
    from app.core.errors import UnauthorizedError

    with pytest.raises(UnauthorizedError):
        get_current_user_id(authorization=f"Bearer {legacy_token}")
