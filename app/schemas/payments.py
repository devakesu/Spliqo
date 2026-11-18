"""Pydantic schemas for payments, settlement, and UPI intents."""

from typing import Any, Literal

from pydantic import BaseModel, field_validator


class PaymentIntentResponse(BaseModel):
    """Server-built UPI intent response payload."""

    upi_uri: str
    host_vpa: str
    amount_paise: int
    formatted_amount: str
    payee_name: str


class UpdatePayPreferenceRequest(BaseModel):
    """Payload to select payment preference."""

    preference: Literal["self_pay", "host_pays"]


class ConfirmPaymentRequest(BaseModel):
    """Host action to confirm or reject payment status."""

    action: Literal["confirm_paid", "reject_unpaid", "confirm_waived"]
    target_participant_id: str


class SettlementResponse(BaseModel):
    """Response DTO for participant settlement state."""

    participant_id: str
    session_id: str
    final_amount_paise: int | None
    pay_preference: str
    pay_status: str

    @field_validator("participant_id", "session_id", mode="before")
    @classmethod
    def stringify_uuid(cls, v: Any) -> str:
        return str(v)
