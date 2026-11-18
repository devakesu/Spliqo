"""Pydantic schemas for participants and invites."""

from typing import Any

from pydantic import BaseModel, Field, field_validator


class CreateInviteResponse(BaseModel):
    """Response DTO containing a newly generated session invite token."""

    invite_token: str
    session_id: str
    expires_at: str

    @field_validator("session_id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        return str(v)


class JoinSessionRequest(BaseModel):
    """Request payload to join a session using an invite token."""

    invite_token: str = Field(..., min_length=16)
    display_name: str = Field(..., min_length=1, max_length=40)


class ParticipantResponse(BaseModel):
    """Response DTO for session participant."""

    id: str
    session_id: str
    user_id: str
    role: str
    display_name: str
    selection_completed_at: str | None

    @field_validator("id", "session_id", "user_id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        return str(v)
