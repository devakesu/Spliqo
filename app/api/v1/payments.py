"""FastAPI router for payments, settlement, and UPI intents."""

from typing import Annotated

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field

from app.core.security.auth import get_current_user_id
from app.schemas.payments import (
    ConfirmPaymentRequest,
    PaymentIntentResponse,
    SettlementResponse,
    UpdatePayPreferenceRequest,
)
from app.services import payments_service

router = APIRouter(tags=["Payments & Settlement"])


class SetPayoutProfileRequest(BaseModel):
    """Payload to configure host payout UPI VPA."""

    upi_id: str = Field(..., min_length=5, max_length=100)


@router.post("/payout-profile", status_code=status.HTTP_200_OK)
async def set_payout_profile(
    data: SetPayoutProfileRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict[str, str]:
    """Host sets their payout UPI ID (encrypted at rest via FLE in Backend-only table)."""
    await payments_service.save_host_payout_upi(user_id=user_id, upi_id=data.upi_id)
    return {"message": "Payout UPI profile saved securely."}


@router.get("/sessions/{session_id}/payment-intent", response_model=PaymentIntentResponse)
async def get_payment_intent(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> PaymentIntentResponse:
    """Fetch server-assembled upi://pay intent for a finalized session."""
    return await payments_service.get_payment_intent(user_id=user_id, session_id=session_id)


@router.patch("/sessions/{session_id}/payment-preference", response_model=SettlementResponse)
async def update_payment_preference(
    session_id: str,
    data: UpdatePayPreferenceRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SettlementResponse:
    """Participant sets their payment preference (self_pay or host_pays)."""
    return await payments_service.update_payment_preference(
        user_id=user_id,
        session_id=session_id,
        preference=data.preference,
    )


@router.post("/sessions/{session_id}/payment-pending", response_model=SettlementResponse)
async def mark_payment_pending(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SettlementResponse:
    """Participant marks 'I have paid' for host confirmation."""
    return await payments_service.mark_payment_pending(user_id=user_id, session_id=session_id)


@router.post("/sessions/{session_id}/payment-confirm", response_model=SettlementResponse)
async def confirm_payment(
    session_id: str,
    data: ConfirmPaymentRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SettlementResponse:
    """Host confirms receipt or waives share."""
    return await payments_service.confirm_payment(
        user_id=user_id,
        session_id=session_id,
        target_participant_id=data.target_participant_id,
        action=data.action,
    )
