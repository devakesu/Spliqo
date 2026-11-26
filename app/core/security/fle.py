"""Field-Level Encryption (FLE) and KMS Envelope Encryption utilities for Spliqo.

Provides AES-256-GCM authenticated encryption for sensitive fields
(e.g., phone numbers and UPI IDs) stored as bytea in PostgreSQL, with optional
authenticated associated data (AAD) binding to prevent ciphertext transplantation.

Envelope Encryption:
  - Raw payloads are encrypted locally using an ephemeral 256-bit Data Encryption
    Key (DEK) and AES-256-GCM; payloads are NEVER sent to Infisical KMS.
  - The DEK is wrapped once via Infisical KMS (`INFISICAL_KMS_KEY_ID`) and cached
    in RAM so neither encrypt nor decrypt hits KMS on every payload.
  - Wire format (`SQE1`):
      [4B magic b"SQE1"][2B uint16 wrapped_dek_len][wrapped_dek][12B nonce][ciphertext + 16B tag]
"""

import asyncio
import hashlib
import hmac
import os
import struct
import time
from collections import OrderedDict
from typing import Final

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import settings
from app.core.security.kms import InfisicalKMSClient, KMSError, KMSProvider

NONCE_LENGTH_BYTES: Final[int] = 12
KEY_LENGTH_BYTES: Final[int] = 32  # 256-bit key
ENVELOPE_MAGIC: Final[bytes] = b"SQE1"
ENVELOPE_HEADER_STRUCT: Final[struct.Struct] = struct.Struct(">4sH")


class FLEError(Exception):
    """Base exception for Field-Level Encryption errors."""


class FLEKeyError(FLEError):
    """Raised when an encryption key is invalid or of incorrect length."""


class FLEDecryptionError(FLEError):
    """Raised when decryption or tag verification fails."""


def validate_key(key: bytes) -> None:
    """Validate that the provided cryptographic key is exactly 256 bits (32 bytes)."""
    if len(key) != KEY_LENGTH_BYTES:
        raise FLEKeyError(
            f"Invalid key length: expected {KEY_LENGTH_BYTES} bytes, got {len(key)} bytes.",
        )


def encrypt_field(
    plaintext: str,
    key: bytes,
    associated_data: bytes | None = None,
) -> bytes:
    """Encrypt a plaintext string locally using AES-256-GCM."""
    validate_key(key)
    nonce = os.urandom(NONCE_LENGTH_BYTES)
    aesgcm = AESGCM(key)
    data_bytes = plaintext.encode("utf-8")
    ciphertext = aesgcm.encrypt(nonce, data_bytes, associated_data)
    return nonce + ciphertext


def decrypt_field(
    payload: bytes,
    key: bytes,
    associated_data: bytes | None = None,
) -> str:
    """Decrypt a local AES-256-GCM encrypted bytea payload."""
    validate_key(key)
    if len(payload) < NONCE_LENGTH_BYTES + 16:
        raise FLEDecryptionError("Payload too short to contain a valid nonce and auth tag.")

    nonce = payload[:NONCE_LENGTH_BYTES]
    ciphertext_and_tag = payload[NONCE_LENGTH_BYTES:]
    aesgcm = AESGCM(key)

    try:
        decrypted_bytes = aesgcm.decrypt(nonce, ciphertext_and_tag, associated_data)
        return decrypted_bytes.decode("utf-8")
    except InvalidTag as err:
        raise FLEDecryptionError("Authentication tag verification failed or ciphertext tampered.") from err
    except UnicodeDecodeError as err:
        raise FLEDecryptionError("Decrypted data is not valid UTF-8.") from err


def compute_blind_index(
    plaintext: str,
    key: bytes,
) -> str:
    """Compute an HMAC-SHA256 blind index for exact-match database lookups."""
    validate_key(key)
    return hmac.new(key, plaintext.strip().lower().encode("utf-8"), hashlib.sha256).hexdigest()


class EnvelopeEncryptor:
    """KMS-backed envelope encryptor with in-memory DEK caching.

    Avoids sending application payloads or calling Infisical KMS per request by
    caching the active wrapped DEK for encryption and an LRU cache of unwrapped
    DEKs for decryption.
    """

    def __init__(
        self,
        kms_provider: KMSProvider,
        dek_ttl_seconds: float = 86400.0,
        max_cached_deks: int = 1024,
    ) -> None:
        self._kms = kms_provider
        self._dek_ttl_seconds = dek_ttl_seconds
        self._max_cached_deks = max_cached_deks

        self._active_dek: bytes | None = None
        self._active_wrapped_dek: bytes | None = None
        self._active_dek_expires_at: float = 0.0
        self._active_lock = asyncio.Lock()

        self._dek_cache: OrderedDict[bytes, bytes] = OrderedDict()
        self._unwrap_lock = asyncio.Lock()

    def _cache_dek(self, wrapped_dek: bytes, plaintext_dek: bytes) -> None:
        """Insert or refresh a DEK in the bounded LRU cache."""
        if wrapped_dek in self._dek_cache:
            self._dek_cache.move_to_end(wrapped_dek)
        self._dek_cache[wrapped_dek] = plaintext_dek
        while len(self._dek_cache) > self._max_cached_deks:
            self._dek_cache.popitem(last=False)

    async def _get_active_dek(self) -> tuple[bytes, bytes]:
        """Return (plaintext_dek, wrapped_dek), rotating & wrapping via KMS only when expired."""
        now = time.monotonic()
        if (
            self._active_dek is not None
            and self._active_wrapped_dek is not None
            and now < self._active_dek_expires_at
        ):
            return self._active_dek, self._active_wrapped_dek

        async with self._active_lock:
            now = time.monotonic()
            if (
                self._active_dek is not None
                and self._active_wrapped_dek is not None
                and now < self._active_dek_expires_at
            ):
                return self._active_dek, self._active_wrapped_dek

            plaintext_dek = os.urandom(KEY_LENGTH_BYTES)
            try:
                wrapped_dek = await self._kms.wrap_key(plaintext_dek)
            except KMSError as err:
                raise FLEKeyError(f"Failed to wrap DEK via KMS: {err}") from err

            if len(wrapped_dek) == 0 or len(wrapped_dek) > 65535:
                raise FLEKeyError("Wrapped DEK length out of valid bounds (1..65535 bytes).")

            self._active_dek = plaintext_dek
            self._active_wrapped_dek = wrapped_dek
            self._active_dek_expires_at = time.monotonic() + self._dek_ttl_seconds
            self._cache_dek(wrapped_dek, plaintext_dek)
            return plaintext_dek, wrapped_dek

    async def _resolve_dek(self, wrapped_dek: bytes) -> bytes:
        """Resolve a wrapped DEK from RAM cache or unwrap once via KMS."""
        cached = self._dek_cache.get(wrapped_dek)
        if cached is not None:
            self._dek_cache.move_to_end(wrapped_dek)
            return cached

        async with self._unwrap_lock:
            cached = self._dek_cache.get(wrapped_dek)
            if cached is not None:
                self._dek_cache.move_to_end(wrapped_dek)
                return cached

            try:
                plaintext_dek = await self._kms.unwrap_key(wrapped_dek)
            except KMSError as err:
                raise FLEDecryptionError(f"Failed to unwrap DEK via KMS: {err}") from err

            validate_key(plaintext_dek)
            self._cache_dek(wrapped_dek, plaintext_dek)
            return plaintext_dek

    async def encrypt(
        self,
        plaintext: str,
        associated_data: bytes | None = None,
    ) -> bytes:
        """Encrypt plaintext locally using a KMS-wrapped DEK and return an SQE1 envelope."""
        plaintext_dek, wrapped_dek = await self._get_active_dek()
        encrypted_payload = encrypt_field(
            plaintext=plaintext,
            key=plaintext_dek,
            associated_data=associated_data,
        )
        header = ENVELOPE_HEADER_STRUCT.pack(ENVELOPE_MAGIC, len(wrapped_dek))
        return header + wrapped_dek + encrypted_payload

    async def decrypt(
        self,
        payload: bytes,
        associated_data: bytes | None = None,
    ) -> str:
        """Decrypt an SQE1 envelope using the cached or KMS-unwrapped DEK."""
        if len(payload) < ENVELOPE_HEADER_STRUCT.size:
            raise FLEDecryptionError("Envelope payload too short.")

        magic, wrapped_len = ENVELOPE_HEADER_STRUCT.unpack_from(payload, 0)
        if magic != ENVELOPE_MAGIC:
            raise FLEDecryptionError("Unsupported or invalid envelope format.")

        dek_end = ENVELOPE_HEADER_STRUCT.size + wrapped_len
        if wrapped_len == 0 or len(payload) <= dek_end:
            raise FLEDecryptionError("Malformed envelope header or missing ciphertext.")

        wrapped_dek = payload[ENVELOPE_HEADER_STRUCT.size : dek_end]
        encrypted_payload = payload[dek_end:]

        plaintext_dek = await self._resolve_dek(wrapped_dek)
        return decrypt_field(
            payload=encrypted_payload,
            key=plaintext_dek,
            associated_data=associated_data,
        )


_envelope_encryptor: EnvelopeEncryptor | None = None


def get_envelope_encryptor() -> EnvelopeEncryptor:
    """Return the process-wide EnvelopeEncryptor backed by Infisical KMS."""
    global _envelope_encryptor
    if _envelope_encryptor is None:
        kms_client = InfisicalKMSClient(
            api_url=settings.resolved_infisical_api_url,
            key_id=settings.infisical_kms_key_id,
            client_id=settings.infisical_kms_universal_auth_client_id,
            client_secret=settings.infisical_kms_universal_auth_client_secret,
        )
        _envelope_encryptor = EnvelopeEncryptor(kms_provider=kms_client)
    return _envelope_encryptor


def set_envelope_encryptor(encryptor: EnvelopeEncryptor | None) -> None:
    """Override or reset the process-wide EnvelopeEncryptor (primarily for testing)."""
    global _envelope_encryptor
    _envelope_encryptor = encryptor
