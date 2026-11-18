"""Unit tests for Field-Level Encryption (FLE) and Blind Indexing."""

import os

import pytest

from app.core.security.fle import (
    FLEDecryptionError,
    FLEKeyError,
    compute_blind_index,
    decrypt_field,
    encrypt_field,
)


@pytest.fixture
def valid_key() -> bytes:
    """Generate a valid 256-bit (32-byte) key."""
    return os.urandom(32)


@pytest.fixture
def bidx_key() -> bytes:
    """Generate a valid 256-bit (32-byte) blind index key."""
    return os.urandom(32)


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

    # Correct associated data succeeds
    assert decrypt_field(encrypted_bytes, valid_key, associated_data=user_id_1) == upi_id

    # Wrong associated data fails (prevents ciphertext transplantation across users)
    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        decrypt_field(encrypted_bytes, valid_key, associated_data=user_id_2)

    # Missing associated data fails
    with pytest.raises(FLEDecryptionError, match="tag verification failed"):
        decrypt_field(encrypted_bytes, valid_key, associated_data=None)


def test_tampered_ciphertext_fails(valid_key: bytes) -> None:
    """Assert modifying any byte in the ciphertext causes decryption to fail."""
    plaintext = "sensitive_data"
    encrypted = bytearray(encrypt_field(plaintext, valid_key))
    # Flip the last byte
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
    assert len(bidx_1) == 64  # SHA-256 hex digest length

    # Different key produces different hash
    other_key = os.urandom(32)
    assert compute_blind_index(phone_1, other_key) != bidx_1
