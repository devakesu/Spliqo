"""Service for payment intent generation, settlement tracking, and UPI VPA encryption."""

import urllib.parse
from typing import Any

from app.core.config import settings
from app.core.database import get_db_connection
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.core.security.fle import compute_blind_index, get_envelope_encryptor
from app.repositories import audit_repo, sessions_repo, settlements_repo
from app.schemas.payments import PaymentIntentResponse, SettlementResponse


def _validate_settlement_for_intent(settlement: dict[str, Any] | None) -> int:
    """Validate settlement row is eligible for payment intent generation."""
    if not settlement:
        raise NotFoundError("Settlement record not found.")
    if settlement["pay_status"] != "unpaid":
        raise ConflictError(f"Cannot generate intent for payment in '{settlement['pay_status']}' status.")
    if settlement["pay_preference"] != "self_pay":
        raise ConflictError("Payment intent is only available when 'self_pay' is selected.")
    amount = settlement["final_amount_paise"]
    if amount is None or amount <= 0:
        raise ConflictError("No payable balance due.")
    return int(amount)


def _build_upi_uri(host_vpa: str, host_name: str, amount_paise: int, title: str) -> tuple[str, str]:
    """Format exact currency string and assemble percent-encoded upi://pay URI."""
    formatted = f"{amount_paise // 100}.{amount_paise % 100:02d}"
    query = {
        "pa": host_vpa,
        "pn": host_name,
        "am": formatted,
        "cu": "INR",
        "tn": f"Spliqo - {title[:20]}",
    }
    return f"upi://pay?{urllib.parse.urlencode(query)}", formatted


def _determine_new_pay_status(action: str, current_status: str, preference: str) -> str:
    """Determine new payment status based on host confirmation action."""
    if action == "confirm_paid":
        if current_status not in ("pending", "unpaid"):
            raise ConflictError(f"Cannot mark paid from '{current_status}'.")
        return "paid"
    if action == "reject_unpaid":
        if current_status != "pending":
            raise ConflictError("Only pending payments can be rejected back to unpaid.")
        return "unpaid"
    if action == "confirm_waived":
        if preference != "host_pays":
            raise ConflictError("Participant must request 'host_pays' to be waived.")
        return "waived"
    raise ConflictError("Invalid confirmation action.")


async def save_host_payout_upi(
    user_id: str,
    upi_id: str,
) -> None:
    """Save or update the host's encrypted payout UPI VPA in the Backend-only table."""
    normalized_upi = upi_id.strip()
    if "@" not in normalized_upi or len(normalized_upi) < 5:
        raise ConflictError("Invalid UPI ID format.")

    # Encrypt using Infisical KMS envelope encryption with user_id bound as associated data
    encryptor = get_envelope_encryptor()
    encrypted_upi = await encryptor.encrypt(
        plaintext=normalized_upi,
        associated_data=user_id.encode("utf-8"),
    )
    bidx = compute_blind_index(
        plaintext=normalized_upi,
        key=settings.fle_blind_index_key,
    )

    async with get_db_connection() as conn, conn.transaction():
        await settlements_repo.upsert_payout_profile(
            conn=conn,
            user_id=user_id,
            upi_encrypted=encrypted_upi,
            upi_bidx=bidx,
        )


async def get_payment_intent(
    user_id: str,
    session_id: str,
) -> PaymentIntentResponse:
    """Server-built UPI intent (Section 11.2).

    Constructs the `upi://pay` URI on the backend; client never assembles it.
    """
    async with get_db_connection() as conn:
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if session_row["status"] != "finalized":
            raise ConflictError("Payment intents can only be generated for finalized sessions.")

        participant = await sessions_repo.get_participant(conn, session_id, user_id)
        if not participant:
            raise NotFoundError("Session not found.")

        if participant["role"] == "host":
            raise ConflictError("Host already paid the restaurant; no payment intent needed.")

        participant_id = str(participant["id"])
        settlement = await settlements_repo.get_settlement(conn, participant_id)
        final_amount_paise = _validate_settlement_for_intent(settlement)

        # Fetch and decrypt host payout profile
        host_id = str(session_row["host_id"])
        payout_profile = await settlements_repo.get_active_payout_profile(conn, host_id)
        if not payout_profile:
            raise ConflictError("Host has not configured a payout UPI ID.")

        encryptor = get_envelope_encryptor()
        host_vpa = await encryptor.decrypt(
            payload=bytes(payout_profile["upi_id_encrypted"]),
            associated_data=host_id.encode("utf-8"),
        )

        participants = await sessions_repo.list_participants(conn, session_id)
        host_participant = next((p for p in participants if p["role"] == "host"), None)
        host_name = host_participant["display_name"] if host_participant else "Host"

        upi_uri, formatted_amount = _build_upi_uri(
            host_vpa=host_vpa,
            host_name=host_name,
            amount_paise=final_amount_paise,
            title=session_row["title"],
        )

        return PaymentIntentResponse(
            upi_uri=upi_uri,
            host_vpa=host_vpa,
            amount_paise=final_amount_paise,
            formatted_amount=formatted_amount,
            payee_name=host_name,
        )


async def update_payment_preference(
    user_id: str,
    session_id: str,
    preference: str,
) -> SettlementResponse:
    """Participant updates their payment preference (self_pay or host_pays)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if session_row["status"] != "finalized":
            raise ConflictError("Payment preference can only be chosen after finalization.")

        participant = await sessions_repo.get_participant(conn, session_id, user_id)
        if not participant:
            raise NotFoundError("Session not found.")

        participant_id = str(participant["id"])
        settlement = await settlements_repo.get_settlement(conn, participant_id)
        if not settlement:
            raise NotFoundError("Settlement record not found.")

        if settlement["pay_status"] in ("paid", "waived"):
            raise ConflictError(f"Cannot change preference once payment is '{settlement['pay_status']}'.")

        updated = await settlements_repo.update_pay_preference(conn, participant_id, preference)

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="payment_preference_updated",
            resource_type="settlement",
            resource_id=participant_id,
            after_state={"pay_preference": preference},
        )

        return SettlementResponse(
            participant_id=str(updated["participant_id"]),
            session_id=str(updated["session_id"]),
            final_amount_paise=updated["final_amount_paise"],
            pay_preference=updated["pay_preference"],
            pay_status=updated["pay_status"],
        )


async def mark_payment_pending(
    user_id: str,
    session_id: str,
) -> SettlementResponse:
    """Participant marks: 'I have paid my share' (transitions unpaid -> pending)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        participant = await sessions_repo.get_participant(conn, session_id, user_id)
        if not participant:
            raise NotFoundError("Session not found.")

        participant_id = str(participant["id"])
        settlement = await settlements_repo.get_settlement(conn, participant_id)
        if not settlement:
            raise NotFoundError("Settlement record not found.")

        if settlement["pay_preference"] != "self_pay":
            raise ConflictError("Only self_pay participants can mark payment pending.")

        if settlement["pay_status"] != "unpaid":
            raise ConflictError(f"Payment is already '{settlement['pay_status']}'.")

        updated = await settlements_repo.update_pay_status(conn, participant_id, "pending")

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="payment_marked_pending",
            resource_type="settlement",
            resource_id=participant_id,
        )

        return SettlementResponse(
            participant_id=str(updated["participant_id"]),
            session_id=str(updated["session_id"]),
            final_amount_paise=updated["final_amount_paise"],
            pay_preference=updated["pay_preference"],
            pay_status=updated["pay_status"],
        )


async def confirm_payment(
    user_id: str,
    session_id: str,
    target_participant_id: str,
    action: str,
) -> SettlementResponse:
    """Host action to confirm receipt of funds (Section 3.6)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can confirm or waive payments.")

        settlement = await settlements_repo.get_settlement(conn, target_participant_id)
        if not settlement:
            raise NotFoundError("Settlement record not found.")

        new_status = _determine_new_pay_status(
            action=action,
            current_status=settlement["pay_status"],
            preference=settlement["pay_preference"],
        )

        updated = await settlements_repo.update_pay_status(conn, target_participant_id, new_status)

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action=f"payment_{action}",
            resource_type="settlement",
            resource_id=target_participant_id,
            before_state=settlement,
            after_state=updated,
        )

        return SettlementResponse(
            participant_id=str(updated["participant_id"]),
            session_id=str(updated["session_id"]),
            final_amount_paise=updated["final_amount_paise"],
            pay_preference=updated["pay_preference"],
            pay_status=updated["pay_status"],
        )
