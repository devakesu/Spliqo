"""Pydantic schemas for Sessions and Bill Items."""

from typing import Any, Literal

from pydantic import BaseModel, Field, StrictInt, field_validator


class CreateDraftItemSchema(BaseModel):
    """Schema for creating a bill item within a draft."""

    name: str = Field(..., min_length=1, max_length=80)
    price_paise: StrictInt = Field(..., ge=1, le=10_000_000)
    position: int = Field(0, ge=0)


class CreateDraftSessionRequest(BaseModel):
    """Request payload to create a new draft session."""

    title: str = Field(..., min_length=1, max_length=80)
    subtotal_paise: StrictInt = Field(..., ge=1, le=10_000_000)
    tax_paise: StrictInt = Field(0, ge=0)
    service_charge_paise: StrictInt = Field(0, ge=0)
    discount_paise: StrictInt = Field(0, ge=0)
    round_off_paise: StrictInt = Field(0)
    total_paise: StrictInt = Field(..., ge=1, le=10_000_000)
    host_display_name: str = Field("Host", min_length=1, max_length=40)
    items: list[CreateDraftItemSchema] = Field(..., min_length=1, max_length=200)


class UpdateDraftSessionRequest(BaseModel):
    """Request payload to update a draft session and its line items before activation."""

    title: str | None = Field(None, min_length=1, max_length=80)
    subtotal_paise: StrictInt = Field(..., ge=1, le=10_000_000)
    tax_paise: StrictInt = Field(0, ge=0)
    service_charge_paise: StrictInt = Field(0, ge=0)
    discount_paise: StrictInt = Field(0, ge=0)
    round_off_paise: StrictInt = Field(0)
    total_paise: StrictInt = Field(..., ge=1, le=10_000_000)
    items: list[CreateDraftItemSchema] = Field(..., min_length=1, max_length=200)


class BillItemResponse(BaseModel):
    """Response DTO for an individual line item."""

    id: str
    session_id: str
    position: int
    name: str
    price_paise: int

    @field_validator("id", "session_id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        return str(v)


class SessionResponse(BaseModel):
    """Response DTO for session state and item list."""

    id: str
    host_id: str
    title: str
    currency: str
    subtotal_paise: int
    tax_paise: int
    service_charge_paise: int
    discount_paise: int
    round_off_paise: int
    total_paise: int
    status: str
    revision: int
    items: list[BillItemResponse] = Field(default_factory=list[BillItemResponse])

    @field_validator("id", "host_id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        return str(v)


class ResolveUnclaimedRequest(BaseModel):
    """Request payload for host bulk resolution of unclaimed items."""

    action: Literal["assign_to_participant", "split_all", "host_absorb"]
    target_participant_id: str | None = None
    item_ids: list[str] | None = None


class FinalizeSessionResponse(BaseModel):
    """Response payload returned when session finalization succeeds."""

    session_id: str
    status: str
    final_amounts: dict[str, int]


class ParseReceiptResponse(BaseModel):
    """Response payload returned when receipt image OCR completes."""

    session: SessionResponse
    needs_review: bool = True
    flags: list[str] = Field(default_factory=list[str])
