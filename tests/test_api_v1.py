"""Integration tests for Spliqo API v1 lifecycle endpoints."""

import jwt
import pytest
from httpx import AsyncClient

from app.core.config import settings
from app.core.database import get_db_connection
from tests.conftest import TEST_EC_PRIVATE_KEY


def make_auth_header(user_id: str) -> dict[str, str]:
    """Generate a valid Supabase ECC (P-256 / ES256) JWT Bearer Authorization header."""
    token = jwt.encode(
        {
            "sub": user_id,
            "role": "authenticated",
            "aud": settings.supabase_jwt_audience,
            "iss": settings.resolved_jwt_issuer,
        },
        TEST_EC_PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": "test-p256-key"},
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def host_user_id() -> str:
    return "00000000-0000-0000-0000-000000000001"


@pytest.fixture
def guest_user_id() -> str:
    return "00000000-0000-0000-0000-000000000002"


@pytest.fixture
def outsider_user_id() -> str:
    return "00000000-0000-0000-0000-000000000003"


@pytest.mark.asyncio
async def test_full_session_lifecycle(
    async_client: AsyncClient,
    host_user_id: str,
    guest_user_id: str,
    outsider_user_id: str,
) -> None:
    """Test entire Model C session lifecycle: Draft -> Active -> Claim -> Review -> Finalize -> UPI Intent."""
    host_auth = make_auth_header(host_user_id)
    guest_auth = make_auth_header(guest_user_id)
    outsider_auth = make_auth_header(outsider_user_id)

    # 0. Ensure test users exist in auth.users
    async with get_db_connection() as conn:
        await conn.execute(
            """
            INSERT INTO auth.users (id, email)
            VALUES ($1, 'host@test.com'), ($2, 'guest@test.com'), ($3, 'outsider@test.com')
            ON CONFLICT (id) DO NOTHING;
            """,
            host_user_id,
            guest_user_id,
            outsider_user_id,
        )

    # 1. Host sets payout UPI profile
    payout_resp = await async_client.post(
        "/api/v1/payout-profile",
        json={"upi_id": "host@okhdfcbank"},
        headers=host_auth,
    )
    assert payout_resp.status_code == 200

    # 2. Host creates Draft session
    draft_payload = {
        "title": "Dinner at Paragon",
        "subtotal_paise": 10000,
        "tax_paise": 500,
        "service_charge_paise": 0,
        "discount_paise": 0,
        "round_off_paise": 0,
        "total_paise": 10500,
        "host_display_name": "Host Alice",
        "items": [
            {"name": "Biryani", "price_paise": 6000, "position": 0},
            {"name": "Juice", "price_paise": 4000, "position": 1},
        ],
    }
    draft_resp = await async_client.post(
        "/api/v1/sessions/draft",
        json=draft_payload,
        headers=host_auth,
    )
    assert draft_resp.status_code == 201
    draft_data = draft_resp.json()
    session_id = draft_data["id"]
    assert draft_data["status"] == "draft"
    assert len(draft_data["items"]) == 2

    # Outsider cannot view draft session
    outsider_get = await async_client.get(
        f"/api/v1/sessions/{session_id}",
        headers=outsider_auth,
    )
    assert outsider_get.status_code == 404

    # 2b. Host edits line items and adjustments in Draft session
    update_payload = {
        "title": "Dinner at Paragon (Updated)",
        "subtotal_paise": 11000,
        "tax_paise": 550,
        "service_charge_paise": 0,
        "discount_paise": 0,
        "round_off_paise": 0,
        "total_paise": 11550,
        "items": [
            {"name": "Biryani Special", "price_paise": 7000, "position": 0},
            {"name": "Juice", "price_paise": 4000, "position": 1},
        ],
    }
    # Outsider forbidden from updating draft
    outsider_put = await async_client.put(
        f"/api/v1/sessions/{session_id}/draft",
        json=update_payload,
        headers=outsider_auth,
    )
    assert outsider_put.status_code == 403

    # Host updates successfully
    host_put = await async_client.put(
        f"/api/v1/sessions/{session_id}/draft",
        json=update_payload,
        headers=host_auth,
    )
    assert host_put.status_code == 200
    updated_draft = host_put.json()
    assert updated_draft["title"] == "Dinner at Paragon (Updated)"
    assert updated_draft["subtotal_paise"] == 11000
    assert updated_draft["total_paise"] == 11550
    assert updated_draft["revision"] == draft_data["revision"] + 1
    assert len(updated_draft["items"]) == 2
    assert updated_draft["items"][0]["name"] == "Biryani Special"
    assert updated_draft["items"][0]["price_paise"] == 7000

    # 3. Host activates session
    activate_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/activate",
        headers=host_auth,
    )
    assert activate_resp.status_code == 200
    assert activate_resp.json()["status"] == "active"

    # 4. Host generates invite token
    invite_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/invites",
        headers=host_auth,
    )
    assert invite_resp.status_code == 201
    invite_token = invite_resp.json()["invite_token"]

    # 5. Guest joins session
    join_resp = await async_client.post(
        "/api/v1/sessions/join",
        json={"invite_token": invite_token, "display_name": "Guest Bob"},
        headers=guest_auth,
    )
    assert join_resp.status_code == 200
    guest_data = join_resp.json()
    guest_participant_id = guest_data["id"]

    # 6. Claim items directly via DB (simulating Flutter Direct-path claiming)
    async with get_db_connection() as conn:
        items = await conn.fetch("SELECT id FROM public.bill_items WHERE session_id = $1 ORDER BY position;", session_id)
        biryani_id = str(items[0]["id"])
        juice_id = str(items[1]["id"])

        host_part = await conn.fetchrow(
            "SELECT id FROM public.session_participants WHERE session_id = $1 AND role = 'host';",
            session_id,
        )
        assert host_part is not None
        host_participant_id = str(host_part["id"])

        # Host claims Biryani
        await conn.execute(
            """
            INSERT INTO public.item_claims (session_id, item_id, participant_id, source)
            VALUES ($1, $2, $3, 'self');
            """,
            session_id,
            biryani_id,
            host_participant_id,
        )
        # Guest claims Biryani (shared!) and Juice
        await conn.execute(
            """
            INSERT INTO public.item_claims (session_id, item_id, participant_id, source)
            VALUES ($1, $2, $3, 'self'), ($1, $4, $3, 'self');
            """,
            session_id,
            biryani_id,
            guest_participant_id,
            juice_id,
        )

        # 7. Complete selections (RPC calls)
        # Guest completes
        await conn.execute(
            "UPDATE public.session_participants SET selection_completed_at = now() WHERE id = $1;",
            guest_participant_id,
        )
        # Host completes and triggers reviewing transition
        await conn.execute(
            "UPDATE public.session_participants SET selection_completed_at = now() WHERE id = $1;",
            host_participant_id,
        )
        await conn.execute(
            "UPDATE public.sessions SET status = 'reviewing' WHERE id = $1;",
            session_id,
        )

    # 8. Host Finalizes session
    finalize_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/finalize",
        headers=host_auth,
    )
    assert finalize_resp.status_code == 200
    fin_data = finalize_resp.json()
    assert fin_data["status"] == "finalized"
    amounts = fin_data["final_amounts"]
    # Total must equal exactly updated_draft total paise
    assert sum(amounts.values()) == updated_draft["total_paise"]

    # 9. Guest selects payment preference 'self_pay'
    pref_resp = await async_client.patch(
        f"/api/v1/sessions/{session_id}/payment-preference",
        json={"preference": "self_pay"},
        headers=guest_auth,
    )
    assert pref_resp.status_code == 200
    assert pref_resp.json()["pay_preference"] == "self_pay"

    # 10. Guest fetches payment intent (server-assembled upi://pay URI)
    intent_resp = await async_client.get(
        f"/api/v1/sessions/{session_id}/payment-intent",
        headers=guest_auth,
    )
    assert intent_resp.status_code == 200
    intent_data = intent_resp.json()
    assert "upi://pay?" in intent_data["upi_uri"]
    assert "pa=host%40okhdfcbank" in intent_data["upi_uri"]
    assert intent_data["host_vpa"] == "host@okhdfcbank"
    assert intent_data["amount_paise"] == amounts[guest_participant_id]

    # 11. Guest marks payment as pending
    pending_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/payment-pending",
        headers=guest_auth,
    )
    assert pending_resp.status_code == 200
    assert pending_resp.json()["pay_status"] == "pending"

    # 12. Host confirms receipt of funds
    confirm_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/payment-confirm",
        json={"action": "confirm_paid", "target_participant_id": guest_participant_id},
        headers=host_auth,
    )
    assert confirm_resp.status_code == 200
    assert confirm_resp.json()["pay_status"] == "paid"


@pytest.mark.asyncio
async def test_unclaimed_items_resolution_and_host_waive(
    async_client: AsyncClient,
    host_user_id: str,
    guest_user_id: str,
) -> None:
    """Test resolution of unclaimed items in reviewing phase and host_pays waive flow."""
    host_auth = make_auth_header(host_user_id)
    guest_auth = make_auth_header(guest_user_id)

    # 1. Host creates Draft session
    draft_payload = {
        "title": "Weekend Brunch",
        "subtotal_paise": 5000,
        "tax_paise": 0,
        "service_charge_paise": 0,
        "discount_paise": 0,
        "round_off_paise": 0,
        "total_paise": 5000,
        "host_display_name": "Host Alice",
        "items": [
            {"name": "Pancakes", "price_paise": 3000, "position": 0},
            {"name": "Coffee", "price_paise": 2000, "position": 1},
        ],
    }
    draft_resp = await async_client.post(
        "/api/v1/sessions/draft",
        json=draft_payload,
        headers=host_auth,
    )
    session_id = draft_resp.json()["id"]

    # 2. Host activates and invites guest
    await async_client.post(f"/api/v1/sessions/{session_id}/activate", headers=host_auth)
    invite_resp = await async_client.post(f"/api/v1/sessions/{session_id}/invites", headers=host_auth)
    invite_token = invite_resp.json()["invite_token"]

    join_resp = await async_client.post(
        "/api/v1/sessions/join",
        json={"invite_token": invite_token, "display_name": "Guest Bob"},
        headers=guest_auth,
    )
    guest_pid = join_resp.json()["id"]

    # 3. Only Coffee is claimed (Pancakes is unclaimed)
    async with get_db_connection() as conn:
        items = await conn.fetch("SELECT id FROM public.bill_items WHERE session_id = $1 ORDER BY position;", session_id)
        coffee_id = str(items[1]["id"])
        await conn.execute(
            """
            INSERT INTO public.item_claims (session_id, item_id, participant_id, source)
            VALUES ($1, $2, $3, 'self');
            """,
            session_id,
            coffee_id,
            guest_pid,
        )
        # Advance to reviewing
        await conn.execute("UPDATE public.session_participants SET selection_completed_at = now() WHERE session_id = $1;", session_id)
        await conn.execute("UPDATE public.sessions SET status = 'reviewing' WHERE id = $1;", session_id)

    # 4. Finalize fails with unresolved_items
    fin_fail = await async_client.post(
        f"/api/v1/sessions/{session_id}/finalize",
        headers=host_auth,
    )
    assert fin_fail.status_code == 409
    assert fin_fail.json()["error"]["code"] == "unresolved_items"

    # 5. Host resolves unclaimed items using split_all
    resolve_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/resolve-unclaimed",
        json={"action": "split_all"},
        headers=host_auth,
    )
    assert resolve_resp.status_code == 200
    assert resolve_resp.json()["resolved_count"] == 1

    # 6. Now finalization succeeds
    fin_success = await async_client.post(
        f"/api/v1/sessions/{session_id}/finalize",
        headers=host_auth,
    )
    assert fin_success.status_code == 200
    assert fin_success.json()["status"] == "finalized"

    # 7. Guest requests host to cover share ('host_pays')
    pref_resp = await async_client.patch(
        f"/api/v1/sessions/{session_id}/payment-preference",
        json={"preference": "host_pays"},
        headers=guest_auth,
    )
    assert pref_resp.status_code == 200
    assert pref_resp.json()["pay_preference"] == "host_pays"

    # 8. Host confirms waived
    waive_resp = await async_client.post(
        f"/api/v1/sessions/{session_id}/payment-confirm",
        json={"action": "confirm_waived", "target_participant_id": guest_pid},
        headers=host_auth,
    )
    assert waive_resp.status_code == 200
    assert waive_resp.json()["pay_status"] == "waived"


@pytest.mark.asyncio
async def test_auth_and_permission_enforcement(
    async_client: AsyncClient,
    guest_user_id: str,
) -> None:
    """Test standard authorization matrix enforcement (401 unauthenticated, 403 forbidden)."""
    # 1. Unauthenticated request rejected with standard envelope
    unauth_resp = await async_client.post("/api/v1/sessions/draft", json={})
    assert unauth_resp.status_code == 401
    assert unauth_resp.json()["error"]["code"] == "unauthorized"

    # 2. Non-host attempting to activate or finalize rejected with 403/404
    guest_auth = make_auth_header(guest_user_id)
    forbidden_act = await async_client.post(
        "/api/v1/sessions/00000000-0000-0000-0000-000000000099/activate",
        headers=guest_auth,
    )
    assert forbidden_act.status_code in (403, 404)


@pytest.mark.asyncio
async def test_parse_receipt_image(
    async_client: AsyncClient,
    host_user_id: str,
) -> None:
    """Test OCR receipt image parsing endpoint with magic byte validation and draft creation."""
    host_auth = make_auth_header(host_user_id)

    # 1. Invalid image bytes rejected with 400
    invalid_upload = {
        "file": ("test.jpg", b"NOT_A_REAL_IMAGE", "image/jpeg"),
    }
    bad_resp = await async_client.post(
        "/api/v1/sessions/parse",
        files=invalid_upload,
        data={"host_display_name": "Host"},
        headers=host_auth,
    )
    assert bad_resp.status_code == 400
    assert bad_resp.json()["error"]["code"] == "invalid_file_header"

    # 2. Valid JPEG with magic bytes accepted
    valid_jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF" + b"\x00" * 100
    valid_upload = {
        "file": ("receipt.jpg", valid_jpeg_bytes, "image/jpeg"),
    }
    good_resp = await async_client.post(
        "/api/v1/sessions/parse",
        files=valid_upload,
        data={"host_display_name": "Test Host"},
        headers=host_auth,
    )
    assert good_resp.status_code == 201
    body = good_resp.json()
    assert body["needs_review"] is True
    assert body["session"]["status"] == "draft"
    assert len(body["session"]["items"]) >= 1
    # Check quantity expansion: Garlic Naan quantity 2 should expand into #1 and #2
    item_names = [i["name"] for i in body["session"]["items"]]
    assert any("Garlic Naan #1" in n for n in item_names)
    assert any("Garlic Naan #2" in n for n in item_names)


@pytest.mark.asyncio
async def test_host_lock_and_reopen_room(
    async_client: AsyncClient,
    host_user_id: str,
    guest_user_id: str,
) -> None:
    """Test host force-lock (§3.3) and host room re-opening transitions."""
    host_auth = make_auth_header(host_user_id)
    guest_auth = make_auth_header(guest_user_id)

    # 1. Host creates Draft session
    draft_payload = {
        "title": "Team Lunch",
        "subtotal_paise": 4000,
        "tax_paise": 0,
        "service_charge_paise": 0,
        "discount_paise": 0,
        "round_off_paise": 0,
        "total_paise": 4000,
        "host_display_name": "Host Alice",
        "items": [
            {"name": "Burger", "price_paise": 2000, "position": 0},
            {"name": "Fries", "price_paise": 2000, "position": 1},
        ],
    }
    draft_resp = await async_client.post(
        "/api/v1/sessions/draft",
        json=draft_payload,
        headers=host_auth,
    )
    assert draft_resp.status_code == 201
    session_id = draft_resp.json()["id"]

    # 2. Host activates and invites guest
    await async_client.post(f"/api/v1/sessions/{session_id}/activate", headers=host_auth)
    invite_resp = await async_client.post(f"/api/v1/sessions/{session_id}/invites", headers=host_auth)
    invite_token = invite_resp.json()["invite_token"]

    join_resp = await async_client.post(
        "/api/v1/sessions/join",
        json={"invite_token": invite_token, "display_name": "Guest Bob"},
        headers=guest_auth,
    )
    assert join_resp.status_code == 200
    guest_pid = join_resp.json()["id"]

    # Guest has NOT completed selection yet
    async with get_db_connection() as conn:
        p_row = await conn.fetchrow("SELECT selection_completed_at FROM public.session_participants WHERE id = $1;", guest_pid)
        assert p_row["selection_completed_at"] is None

    # 3. Non-host attempts to lock room -> 403 Forbidden
    guest_lock = await async_client.post(f"/api/v1/sessions/{session_id}/lock", headers=guest_auth)
    assert guest_lock.status_code == 403

    # 4. Host locks room (STANDARDS.md §3.3 forced completion)
    host_lock = await async_client.post(f"/api/v1/sessions/{session_id}/lock", headers=host_auth)
    assert host_lock.status_code == 200
    assert host_lock.json()["status"] == "reviewing"

    # Verify participant is now marked complete
    async with get_db_connection() as conn:
        p_row_after = await conn.fetchrow("SELECT selection_completed_at FROM public.session_participants WHERE id = $1;", guest_pid)
        assert p_row_after["selection_completed_at"] is not None

        # Verify audit log recorded session_locked with forced=True
        audit_event = await conn.fetchrow(
            "SELECT * FROM public.audit_log WHERE resource_id = $1 AND action = 'session_locked';",
            session_id,
        )
        assert audit_event is not None
        assert "forced" in audit_event["after_state"]

    # 5. Non-host attempts to reopen room -> 403 Forbidden
    guest_reopen = await async_client.post(f"/api/v1/sessions/{session_id}/reopen", headers=guest_auth)
    assert guest_reopen.status_code == 403

    # 6. Host reopens room before finalization (reviewing -> active)
    host_reopen = await async_client.post(f"/api/v1/sessions/{session_id}/reopen", headers=host_auth)
    assert host_reopen.status_code == 200
    assert host_reopen.json()["status"] == "active"

    # Verify participant selection_completed_at is reset to NULL so they can select again
    async with get_db_connection() as conn:
        p_row_reopened = await conn.fetchrow("SELECT selection_completed_at FROM public.session_participants WHERE id = $1;", guest_pid)
        assert p_row_reopened["selection_completed_at"] is None

        # Verify audit log recorded session_reopened
        reopen_audit = await conn.fetchrow(
            "SELECT * FROM public.audit_log WHERE resource_id = $1 AND action = 'session_reopened';",
            session_id,
        )
        assert reopen_audit is not None


