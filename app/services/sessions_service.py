"""Service for session lifecycle, draft activation, host resolution, and finalization."""

from typing import Any

from app.core.database import get_db_connection
from app.core.errors import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ReconciliationError,
    UnresolvedItemsError,
)
from app.domain.allocation import calculate_split
from app.integrations.gemini import parse_receipt_image
from app.repositories import audit_repo, claims_repo, sessions_repo, settlements_repo
from app.schemas.sessions import (
    BillItemResponse,
    CreateDraftItemSchema,
    CreateDraftSessionRequest,
    FinalizeSessionResponse,
    ParseReceiptResponse,
    ResolveUnclaimedRequest,
    SessionResponse,
    UpdateDraftSessionRequest,
)


async def parse_and_create_draft(
    user_id: str,
    image_bytes: bytes,
    content_type: str,
    host_display_name: str = "Host",
) -> ParseReceiptResponse:
    """Parse receipt image using Gemini Vision and create a draft session with review flag."""
    parsed_data, expanded_items, flags = await parse_receipt_image(image_bytes, content_type)

    draft_request = CreateDraftSessionRequest(
        title=parsed_data.merchant_name,
        subtotal_paise=parsed_data.subtotal_paise,
        tax_paise=parsed_data.tax_paise,
        service_charge_paise=parsed_data.service_charge_paise,
        discount_paise=parsed_data.discount_paise,
        round_off_paise=parsed_data.round_off_paise,
        total_paise=parsed_data.total_paise,
        host_display_name=host_display_name,
        items=[
            CreateDraftItemSchema(
                name=item.name,
                price_paise=item.price_paise,
                position=idx,
            )
            for idx, item in enumerate(expanded_items)
        ],
    )

    session_resp = await create_draft(user_id=user_id, data=draft_request)
    return ParseReceiptResponse(
        session=session_resp,
        needs_review=True,
        flags=flags,
    )


async def create_draft(
    user_id: str,
    data: CreateDraftSessionRequest,
) -> SessionResponse:
    """Create a new draft session and line items."""
    # Validate items sum to subtotal_paise
    items_sum = sum(item.price_paise for item in data.items)
    if items_sum != data.subtotal_paise:
        raise ReconciliationError("Sum of line items must equal subtotal_paise.")

    # Validate equation: total = subtotal + tax + service - discount + round_off
    expected_total = (
        data.subtotal_paise
        + data.tax_paise
        + data.service_charge_paise
        - data.discount_paise
        + data.round_off_paise
    )
    if expected_total != data.total_paise:
        raise ReconciliationError("Session adjustments do not reconcile with total_paise.")

    async with get_db_connection() as conn, conn.transaction():
        session_row, items = await sessions_repo.create_session_with_items(
            conn=conn,
            host_id=user_id,
            title=data.title,
            subtotal_paise=data.subtotal_paise,
            tax_paise=data.tax_paise,
            service_charge_paise=data.service_charge_paise,
            discount_paise=data.discount_paise,
            round_off_paise=data.round_off_paise,
            total_paise=data.total_paise,
            host_display_name=data.host_display_name,
            items=[item.model_dump() for item in data.items],
        )

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_draft_created",
            resource_type="session",
            resource_id=str(session_row["id"]),
            after_state=session_row,
        )

        return SessionResponse(
            id=str(session_row["id"]),
            host_id=str(session_row["host_id"]),
            title=session_row["title"],
            currency=session_row["currency"],
            subtotal_paise=session_row["subtotal_paise"],
            tax_paise=session_row["tax_paise"],
            service_charge_paise=session_row["service_charge_paise"],
            discount_paise=session_row["discount_paise"],
            round_off_paise=session_row["round_off_paise"],
            total_paise=session_row["total_paise"],
            status=session_row["status"],
            revision=session_row["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


async def update_draft(
    user_id: str,
    session_id: str,
    data: UpdateDraftSessionRequest,
) -> SessionResponse:
    """Update line items and adjustments in an existing draft session before activation."""
    # 1. Validate line items sum to subtotal_paise (Section 4.2)
    items_sum = sum(item.price_paise for item in data.items)
    if items_sum != data.subtotal_paise:
        raise ReconciliationError("Sum of line items must equal subtotal_paise.")

    # 2. Validate equation: total = subtotal + tax + service - discount + round_off
    expected_total = (
        data.subtotal_paise
        + data.tax_paise
        + data.service_charge_paise
        - data.discount_paise
        + data.round_off_paise
    )
    if expected_total != data.total_paise:
        raise ReconciliationError("Session adjustments do not reconcile with total_paise.")

    async with get_db_connection() as conn, conn.transaction():
        # Lock session for update to verify state
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can update draft session items.")

        if session_row["status"] != "draft":
            raise ConflictError(f"Cannot edit session in '{session_row['status']}' state.")

        updated_row, items = await sessions_repo.update_draft_session_with_items(
            conn=conn,
            session_id=session_id,
            title=data.title,
            subtotal_paise=data.subtotal_paise,
            tax_paise=data.tax_paise,
            service_charge_paise=data.service_charge_paise,
            discount_paise=data.discount_paise,
            round_off_paise=data.round_off_paise,
            total_paise=data.total_paise,
            items=[item.model_dump() for item in data.items],
        )

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_draft_updated",
            resource_type="session",
            resource_id=session_id,
            after_state=updated_row,
        )

        return SessionResponse(
            id=str(updated_row["id"]),
            host_id=str(updated_row["host_id"]),
            title=updated_row["title"],
            currency=updated_row["currency"],
            subtotal_paise=updated_row["subtotal_paise"],
            tax_paise=updated_row["tax_paise"],
            service_charge_paise=updated_row["service_charge_paise"],
            discount_paise=updated_row["discount_paise"],
            round_off_paise=updated_row["round_off_paise"],
            total_paise=updated_row["total_paise"],
            status=updated_row["status"],
            revision=updated_row["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


async def get_session(user_id: str, session_id: str) -> SessionResponse:
    """Fetch session details with authorization membership check."""
    async with get_db_connection() as conn:
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        # Check membership
        participant = await sessions_repo.get_participant(conn, session_id, user_id)
        if not participant:
            raise NotFoundError("Session not found.")  # Hide existence from non-members

        items = await sessions_repo.get_session_items(conn, session_id)
        return SessionResponse(
            id=str(session_row["id"]),
            host_id=str(session_row["host_id"]),
            title=session_row["title"],
            currency=session_row["currency"],
            subtotal_paise=session_row["subtotal_paise"],
            tax_paise=session_row["tax_paise"],
            service_charge_paise=session_row["service_charge_paise"],
            discount_paise=session_row["discount_paise"],
            round_off_paise=session_row["round_off_paise"],
            total_paise=session_row["total_paise"],
            status=session_row["status"],
            revision=session_row["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


async def activate_session(user_id: str, session_id: str) -> SessionResponse:
    """Host action to activate a draft session after verifying items."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can activate the session.")

        if session_row["status"] != "draft":
            raise ConflictError(f"Cannot activate session in '{session_row['status']}' state.")

        # Check reconciliation before activation (Section 4.2)
        items = await sessions_repo.get_session_items(conn, session_id)
        if sum(item["price_paise"] for item in items) != session_row["subtotal_paise"]:
            raise ReconciliationError("Line items do not reconcile with session subtotal.")

        updated_session = await sessions_repo.update_session_status(conn, session_id, "active")

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_activated",
            resource_type="session",
            resource_id=session_id,
            before_state=session_row,
            after_state=updated_session,
        )

        return SessionResponse(
            id=str(updated_session["id"]),
            host_id=str(updated_session["host_id"]),
            title=updated_session["title"],
            currency=updated_session["currency"],
            subtotal_paise=updated_session["subtotal_paise"],
            tax_paise=updated_session["tax_paise"],
            service_charge_paise=updated_session["service_charge_paise"],
            discount_paise=updated_session["discount_paise"],
            round_off_paise=updated_session["round_off_paise"],
            total_paise=updated_session["total_paise"],
            status=updated_session["status"],
            revision=updated_session["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


async def lock_session(user_id: str, session_id: str) -> SessionResponse:
    """Host action to force lock the room and transition to reviewing phase (STANDARDS.md Section 3.3)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can lock the room.")

        if session_row["status"] != "active":
            raise ConflictError(f"Cannot lock session in '{session_row['status']}' state.")

        # Forced completion on host lock: mark incomplete participants complete (Section 3.3)
        incomplete_rows = await conn.fetch(
            """
            UPDATE public.session_participants
            SET selection_completed_at = now()
            WHERE session_id = $1 AND selection_completed_at IS NULL
            RETURNING id, user_id;
            """,
            session_id,
        )

        updated_session = await sessions_repo.update_session_status(conn, session_id, "reviewing")
        items = await sessions_repo.get_session_items(conn, session_id)

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_locked",
            resource_type="session",
            resource_id=session_id,
            before_state=session_row,
            after_state={
                **dict(updated_session),
                "forced": True,
                "forced_participants": [str(r["id"]) for r in incomplete_rows],
            },
        )

        return SessionResponse(
            id=str(updated_session["id"]),
            host_id=str(updated_session["host_id"]),
            title=updated_session["title"],
            currency=updated_session["currency"],
            subtotal_paise=updated_session["subtotal_paise"],
            tax_paise=updated_session["tax_paise"],
            service_charge_paise=updated_session["service_charge_paise"],
            discount_paise=updated_session["discount_paise"],
            round_off_paise=updated_session["round_off_paise"],
            total_paise=updated_session["total_paise"],
            status=updated_session["status"],
            revision=updated_session["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


async def reopen_session(user_id: str, session_id: str) -> SessionResponse:
    """Host action to reopen the room before finalisation or when settlements have not started (STANDARDS.md Section 3.3)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can reopen the room.")

        if session_row["status"] == "reviewing":
            # Reopen from reviewing -> active: reset participants' completion so they can edit selections
            await conn.execute(
                """
                UPDATE public.session_participants
                SET selection_completed_at = NULL
                WHERE session_id = $1;
                """,
                session_id,
            )
            updated_session = await sessions_repo.update_session_status(conn, session_id, "active")
        elif session_row["status"] == "finalized":
            # Section 3.3: only if no settlement row has left 'unpaid'
            unpaid_count = await conn.fetchval(
                """
                SELECT count(*) FROM public.participant_settlements
                WHERE session_id = $1 AND pay_status <> 'unpaid';
                """,
                session_id,
            )
            if unpaid_count and unpaid_count > 0:
                raise ConflictError("Cannot reopen session with settlements in progress.")
            updated_session = await sessions_repo.update_session_status(conn, session_id, "reviewing")
        else:
            raise ConflictError(f"Cannot reopen session in '{session_row['status']}' state.")

        items = await sessions_repo.get_session_items(conn, session_id)

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_reopened",
            resource_type="session",
            resource_id=session_id,
            before_state=session_row,
            after_state=dict(updated_session),
        )

        return SessionResponse(
            id=str(updated_session["id"]),
            host_id=str(updated_session["host_id"]),
            title=updated_session["title"],
            currency=updated_session["currency"],
            subtotal_paise=updated_session["subtotal_paise"],
            tax_paise=updated_session["tax_paise"],
            service_charge_paise=updated_session["service_charge_paise"],
            discount_paise=updated_session["discount_paise"],
            round_off_paise=updated_session["round_off_paise"],
            total_paise=updated_session["total_paise"],
            status=updated_session["status"],
            revision=updated_session["revision"],
            items=[BillItemResponse(**item) for item in items],
        )


def _build_claims_for_action(
    action: str,
    target_item_ids: list[str],
    participants: list[dict[str, Any]],
    target_participant_id: str | None,
) -> list[tuple[str, str]]:
    """Build list of (item_id, participant_id) tuples based on resolution action."""
    if action == "assign_to_participant":
        if not target_participant_id:
            raise ConflictError("target_participant_id required for assign_to_participant action.")
        return [(item_id, target_participant_id) for item_id in target_item_ids]

    if action == "split_all":
        return [(item_id, str(p["id"])) for item_id in target_item_ids for p in participants]

    if action == "host_absorb":
        host_participant = next((p for p in participants if p["role"] == "host"), None)
        if not host_participant:
            raise RuntimeError("Host participant row not found.")
        host_id = str(host_participant["id"])
        return [(item_id, host_id) for item_id in target_item_ids]

    return []


async def _get_existing_final_amounts(
    conn: Any,
    session_id: str,
) -> dict[str, int]:
    """Fetch stored settlements for an already finalized session (idempotent replay)."""
    participants = await sessions_repo.list_participants(conn, session_id)
    existing: dict[str, int] = {}
    for p in participants:
        st = await settlements_repo.get_settlement(conn, str(p["id"]))
        if st and st["final_amount_paise"] is not None:
            existing[str(p["id"])] = st["final_amount_paise"]
    return existing


async def resolve_unclaimed_items(
    user_id: str,
    session_id: str,
    data: ResolveUnclaimedRequest,
) -> dict[str, Any]:
    """Host action in reviewing phase to allocate unclaimed items."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can resolve unclaimed items.")

        if session_row["status"] != "reviewing":
            raise ConflictError("Unclaimed items can only be resolved during the reviewing phase.")

        items = await sessions_repo.get_session_items(conn, session_id)
        claims = await claims_repo.get_claims_by_session(conn, session_id)
        participants = await sessions_repo.list_participants(conn, session_id)

        all_unclaimed = [str(i["id"]) for i in items if not claims.get(str(i["id"]))]
        target_item_ids = [i for i in (data.item_ids or all_unclaimed) if i in all_unclaimed]

        if not target_item_ids:
            return {"resolved_count": 0, "message": "No unclaimed items to resolve."}

        new_claims = _build_claims_for_action(
            action=data.action,
            target_item_ids=target_item_ids,
            participants=participants,
            target_participant_id=data.target_participant_id,
        )

        await claims_repo.bulk_insert_host_claims(conn, session_id, new_claims)

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action=f"unclaimed_resolved_{data.action}",
            resource_type="session",
            resource_id=session_id,
            after_state={"resolved_items": target_item_ids, "action": data.action},
        )

        return {
            "resolved_count": len(target_item_ids),
            "action": data.action,
            "resolved_item_ids": target_item_ids,
        }


async def finalize_session(
    user_id: str,
    session_id: str,
) -> FinalizeSessionResponse:
    """Authoritative server finalization transaction (Sections 3.1 & 8.7)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can finalize the session.")

        if session_row["status"] == "finalized":
            existing = await _get_existing_final_amounts(conn, session_id)
            return FinalizeSessionResponse(
                session_id=session_id,
                status="finalized",
                final_amounts=existing,
            )

        if session_row["status"] != "reviewing":
            raise ConflictError(f"Session must be in 'reviewing' state to finalize (current: '{session_row['status']}').")

        # 2. Verify all participants completed
        participants = await sessions_repo.list_participants(conn, session_id)
        incomplete = [p for p in participants if p["selection_completed_at"] is None]
        if incomplete:
            raise ConflictError(f"{len(incomplete)} participant(s) have not completed selection.")

        # 3. Read items and claims
        session_items = await sessions_repo.get_session_items(conn, session_id)
        items_dict = {str(item["id"]): int(item["price_paise"]) for item in session_items}
        claims_dict = await claims_repo.get_claims_by_session(conn, session_id)

        # 4. Assert zero unclaimed items
        unclaimed = [i for i in items_dict if not claims_dict.get(i)]
        if unclaimed:
            raise UnresolvedItemsError(unclaimed)

        # 5. Execute authoritative pure allocation engine
        participant_ids = [str(p["id"]) for p in participants]
        final_amounts = calculate_split(
            items=items_dict,
            claims=claims_dict,
            participants=participant_ids,
            subtotal_paise=int(session_row["subtotal_paise"]),
            total_paise=int(session_row["total_paise"]),
        )

        # 6. Store final settlements
        await settlements_repo.bulk_create_settlements(conn, session_id, final_amounts)

        # 7. Host already paid restaurant -> host settlement set to 'paid' (Section 3.6)
        host_p = next(p for p in participants if p["role"] == "host")
        await settlements_repo.update_pay_status(conn, str(host_p["id"]), "paid")

        # 8. Advance status to 'finalized'
        await sessions_repo.update_session_status(conn, session_id, "finalized")

        # 9. Record audit trail
        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="session_finalized",
            resource_type="session",
            resource_id=session_id,
            after_state={"final_amounts": final_amounts},
        )

        return FinalizeSessionResponse(
            session_id=session_id,
            status="finalized",
            final_amounts=final_amounts,
        )
