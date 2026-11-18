"""Repository for settlements and payout profiles."""

from typing import Any

import asyncpg


async def bulk_create_settlements(
    conn: asyncpg.Connection,
    session_id: str,
    final_amounts: dict[str, int],
) -> None:
    """Insert or replace finalized settlement records for all participants."""
    for participant_id, amount_paise in final_amounts.items():
        await conn.execute(
            """
            INSERT INTO public.participant_settlements (
              participant_id, session_id, final_amount_paise, pay_preference, pay_status
            ) VALUES ($1, $2, $3, 'undecided', 'unpaid')
            ON CONFLICT (participant_id) DO UPDATE SET
              final_amount_paise = EXCLUDED.final_amount_paise,
              updated_at = now();
            """,
            participant_id,
            session_id,
            amount_paise,
        )


async def get_settlement(
    conn: asyncpg.Connection,
    participant_id: str,
) -> dict[str, Any] | None:
    """Fetch settlement row by participant_id."""
    row = await conn.fetchrow(
        "SELECT * FROM public.participant_settlements WHERE participant_id = $1;",
        participant_id,
    )
    return dict(row) if row else None


async def update_pay_preference(
    conn: asyncpg.Connection,
    participant_id: str,
    preference: str,
) -> dict[str, Any]:
    """Update participant's payment preference."""
    row = await conn.fetchrow(
        """
        UPDATE public.participant_settlements
        SET pay_preference = $2, updated_at = now()
        WHERE participant_id = $1
        RETURNING *;
        """,
        participant_id,
        preference,
    )
    if not row:
        raise RuntimeError("Settlement record not found.")
    return dict(row)


async def update_pay_status(
    conn: asyncpg.Connection,
    participant_id: str,
    status: str,
) -> dict[str, Any]:
    """Update participant's payment status."""
    row = await conn.fetchrow(
        """
        UPDATE public.participant_settlements
        SET pay_status = $2, updated_at = now()
        WHERE participant_id = $1
        RETURNING *;
        """,
        participant_id,
        status,
    )
    if not row:
        raise RuntimeError("Settlement record not found.")
    return dict(row)


async def get_active_payout_profile(
    conn: asyncpg.Connection,
    user_id: str,
) -> dict[str, Any] | None:
    """Fetch active payout profile for host (Backend-only query)."""
    row = await conn.fetchrow(
        """
        SELECT * FROM public.user_payout_profiles
        WHERE user_id = $1 AND is_active = true;
        """,
        user_id,
    )
    return dict(row) if row else None


async def upsert_payout_profile(
    conn: asyncpg.Connection,
    user_id: str,
    upi_encrypted: bytes,
    upi_bidx: str,
) -> dict[str, Any]:
    """Save or update encrypted host payout UPI profile."""
    # Deactivate existing profiles
    await conn.execute(
        "UPDATE public.user_payout_profiles SET is_active = false WHERE user_id = $1;",
        user_id,
    )
    row = await conn.fetchrow(
        """
        INSERT INTO public.user_payout_profiles (
          user_id, upi_id_encrypted, upi_id_bidx, is_active
        ) VALUES ($1, $2, $3, true)
        RETURNING *;
        """,
        user_id,
        upi_encrypted,
        upi_bidx,
    )
    if not row:
        raise RuntimeError("Failed to create payout profile.")
    return dict(row)
