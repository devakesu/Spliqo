"""Shared pytest fixtures and test configuration for Spliqo."""

import os
from collections.abc import AsyncIterator, Iterator
from dataclasses import dataclass

import pytest
import pytest_asyncio
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DEBUG", "false")
if os.environ.get("DEBUG") == "release":
    os.environ["DEBUG"] = "false"

# Provide deterministic test-only runtime env vars (simulating Infisical injection)
os.environ.setdefault(
    "DATABASE_URL",
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
)
os.environ.setdefault("SUPABASE_URL", "http://127.0.0.1:54321")
os.environ.setdefault("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test_key")
os.environ.setdefault("SUPABASE_SECRET_KEY", "sb_secret_test_key")
os.environ.setdefault(
    "INFISICAL_KMS_KEY_ID",
    "12345678-1234-1234-1234-123456789abc",
)
os.environ.setdefault("INFISICAL_KMS_UNIVERSAL_AUTH_CLIENT_ID", "test-kms-client-id")
os.environ.setdefault(
    "INFISICAL_KMS_UNIVERSAL_AUTH_CLIENT_SECRET",
    "test-kms-client-secret",
)
os.environ.setdefault(
    "FLE_BLIND_INDEX_KEY_HEX",
    "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
)

from app.core.database import close_db_pool, init_db_pool
from app.core.security.auth import set_jwk_client
from app.core.security.fle import EnvelopeEncryptor, set_envelope_encryptor
from app.main import app

# Ephemeral ECC (P-256) keypair for ES256 JWT verification in tests
TEST_EC_PRIVATE_KEY = ec.generate_private_key(ec.SECP256R1())
TEST_EC_PUBLIC_KEY = TEST_EC_PRIVATE_KEY.public_key()


@dataclass
class _TestSigningKey:
    key: ec.EllipticCurvePublicKey


class _TestJWKClient:
    """In-memory JWK client returning the test ECC P-256 public key."""

    def get_signing_key_from_jwt(self, _token: str) -> _TestSigningKey:
        return _TestSigningKey(key=TEST_EC_PUBLIC_KEY)


class InMemoryKMSProvider:
    """Deterministic in-memory KMS provider for integration tests."""

    def __init__(self) -> None:
        self._kek = AESGCM(os.urandom(32))

    async def wrap_key(self, plaintext_dek: bytes) -> bytes:
        nonce = os.urandom(12)
        return nonce + self._kek.encrypt(nonce, plaintext_dek, None)

    async def unwrap_key(self, wrapped_dek: bytes) -> bytes:
        nonce, ct = wrapped_dek[:12], wrapped_dek[12:]
        return self._kek.decrypt(nonce, ct, None)


@pytest.fixture(autouse=True)
def _configure_test_security() -> Iterator[None]:
    """Install in-memory ECC P-256 JWK client and KMS envelope encryptor for tests."""
    set_jwk_client(_TestJWKClient())  # type: ignore[arg-type]
    set_envelope_encryptor(EnvelopeEncryptor(kms_provider=InMemoryKMSProvider()))
    yield
    set_jwk_client(None)
    set_envelope_encryptor(None)


@pytest_asyncio.fixture
async def async_client() -> AsyncIterator[AsyncClient]:
    """Provides an asynchronous HTTP test client for the FastAPI app."""
    await init_db_pool()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    await close_db_pool()
