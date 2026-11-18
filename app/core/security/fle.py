"""Field-Level Encryption (FLE) utilities for Spliqo.

Provides AES-256-GCM authenticated encryption for sensitive fields
(e.g., phone numbers and UPI IDs) stored as bytea in PostgreSQL, with optional
authenticated associated data (AAD) binding to prevent ciphertext transplantation.
Also provides HMAC-SHA256 blind indexing for exact-match database queries.
"""

import hashlib
import hmac
import os
from typing import Final

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

NONCE_LENGTH_BYTES: Final[int] = 12
KEY_LENGTH_BYTES: Final[int] = 32  # 256-bit key


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
    """Encrypt a plaintext string using AES-256-GCM.

    Args:
        plaintext: The sensitive string to encrypt (e.g., phone number or UPI ID).
        key: 32-byte (256-bit) encryption key.
        associated_data: Optional authenticated associated data (e.g., user_id)
            bound cryptographically to prevent ciphertext transplantation.

    Returns:
        Binary payload structured as: [12-byte Nonce] + [Ciphertext + 16-byte Auth Tag].
        Stored directly as `bytea` in PostgreSQL.
    """
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
    """Decrypt an AES-256-GCM encrypted bytea payload.

    Args:
        payload: Binary payload containing [12-byte Nonce] + [Ciphertext + Auth Tag].
        key: 32-byte (256-bit) encryption key.
        associated_data: Optional authenticated associated data matching encryption.

    Returns:
        The decrypted plaintext string.

    Raises:
        FLEDecryptionError: If the payload is malformed or authentication tag verification fails.
    """
    validate_key(key)
    # Minimum valid length: 12-byte nonce + 16-byte auth tag = 28 bytes
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
    """Compute an HMAC-SHA256 blind index for exact-match database lookups.

    Args:
        plaintext: The normalized plaintext string to index.
        key: Secret HMAC key (distinct from the encryption key).

    Returns:
        Hex-encoded HMAC digest for fast database indexing without exposing raw data.
    """
    validate_key(key)
    return hmac.new(key, plaintext.strip().lower().encode("utf-8"), hashlib.sha256).hexdigest()
