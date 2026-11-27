"""Pydantic schemas for authenticated user profile management."""

import re
import unicodedata
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

_CONTROL_CHARS_RE = re.compile(r"[\x00-\x1F\x7F]")
_E164_PHONE_RE = re.compile(r"^\+[1-9]\d{6,14}$")


def normalize_display_name(raw: str) -> str:
    """Canonicalize display name (NFC, strip control chars, trim) per Section 7.3."""
    cleaned = _CONTROL_CHARS_RE.sub("", unicodedata.normalize("NFC", raw)).strip()
    if not 1 <= len(cleaned) <= 40:
        raise ValueError("Display name must be between 1 and 40 characters.")
    return cleaned


def normalize_e164_phone(raw: str) -> str:
    """Canonicalize and strictly validate an E.164 phone number."""
    compact = re.sub(r"[\s\-()]+", "", unicodedata.normalize("NFC", raw).strip())
    if not _E164_PHONE_RE.match(compact):
        raise ValueError(
            "Phone number must be in valid E.164 format (e.g. +919876543210).",
        )
    return compact


class UpdateProfileRequest(BaseModel):
    """Strict DTO for creating or updating the authenticated user's profile."""

    model_config = ConfigDict(extra="forbid")

    display_name: str = Field(..., min_length=1, max_length=40)
    phone_number: str | None = Field(default=None, min_length=8, max_length=20)

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, v: str) -> str:
        """Normalize and bound display_name to 1..40 characters."""
        return normalize_display_name(v)

    @field_validator("phone_number")
    @classmethod
    def validate_phone_number(cls, v: str | None) -> str | None:
        """Normalize and validate phone_number as E.164 when provided."""
        if v is None:
            return None
        stripped = v.strip()
        if not stripped:
            return None
        return normalize_e164_phone(stripped)


class UserProfileResponse(BaseModel):
    """Response DTO for authenticated user profile (phone returned masked only)."""

    id: str
    display_name: str
    has_phone_number: bool
    masked_phone_number: str | None = None

    @field_validator("id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        """Coerce UUID database column to string."""
        return str(v)
