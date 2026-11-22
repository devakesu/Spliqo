"""Repository for sessions and bill items using parameterized asyncpg queries."""

from typing import Any

import asyncpg


async def create_session_with_items(
    conn: asyncpg.Connection,
    host_id: str,
    title: str,
    subtotal_paise: int,
    tax_paise: int,
    service_charge_paise: int,
    discount_paise: int,
    round_off_paise: int,
    total_paise: int,
    host_display_name: str,
    items: list[dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Create a draft session, its bill items, and the host participant row atomically."""
    # 1. Insert session
    session_row = await conn.fetchrow(
        """
        INSERT INTO public.sessions (
          host_id, title, subtotal_paise, tax_paise, service_charge_paise,
          discount_paise, round_off_paise, total_paise, status, expires_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, 'draft', now() + interval '30 days'
        ) RETURNING *;
        """,
        host_id,
        title,
        subtotal_paise,
        tax_paise,
        service_charge_paise,
        discount_paise,
        round_off_paise,
        total_paise,
    )
    if not session_row:
        raise RuntimeError("Failed to insert session row.")

    # 2. Insert host as participant
    await conn.execute(
        """
        INSERT INTO public.session_participants (
          session_id, user_id, role, display_name
        ) VALUES ($1, $2, 'host', $3);
        """,
        session_row["id"],
        host_id,
        host_display_name,
    )

    # 3. Insert bill items
    inserted_items: list[dict[str, Any]] = []
    for idx, item in enumerate(items):
        item_row = await conn.fetchrow(
            """
            INSERT INTO public.bill_items (
              session_id, position, name, price_paise
            ) VALUES ($1, $2, $3, $4)
            RETURNING *;
            """,
            session_row["id"],
            item.get("position", idx),
            item["name"],
            item["price_paise"],
        )
        if item_row:
            inserted_items.append(dict(item_row))

    return dict(session_row), inserted_items


async def update_draft_session_with_items(
    conn: asyncpg.Connection,
    session_id: str,
    title: str | None,
    subtotal_paise: int,
    tax_paise: int,
    service_charge_paise: int,
    discount_paise: int,
    round_off_paise: int,
    total_paise: int,
    items: list[dict[str, Any]],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Update draft session adjustments and replace line items atomically."""
    update_query = """
        UPDATE public.sessions
        SET title = COALESCE($2, title),
            subtotal_paise = $3,
            tax_paise = $4,
            service_charge_paise = $5,
            discount_paise = $6,
            round_off_paise = $7,
            total_paise = $8,
            revision = revision + 1,
            updated_at = now()
        WHERE id = $1
        RETURNING *;
    """
    row = await conn.fetchrow(
        update_query,
        session_id,
        title,
        subtotal_paise,
        tax_paise,
        service_charge_paise,
        discount_paise,
        round_off_paise,
        total_paise,
    )
    if not row:
        raise ValueError(f"Session {session_id} not found.")

    # Delete existing items for draft session
    await conn.execute("DELETE FROM public.bill_items WHERE session_id = $1;", session_id)

    # Insert updated line items
    inserted_items: list[dict[str, Any]] = []
    for idx, item in enumerate(items):
        item_row = await conn.fetchrow(
            """
            INSERT INTO public.bill_items (session_id, position, name, price_paise)
            VALUES ($1, $2, $3, $4)
            RETURNING *;
            """,
            session_id,
            item.get("position", idx),
            item["name"],
            item["price_paise"],
        )
        if item_row:
            inserted_items.append(dict(item_row))

    return dict(row), inserted_items


async def get_session_by_id(
    conn: asyncpg.Connection,
    session_id: str,
) -> dict[str, Any] | None:
    """Fetch session row by UUID."""
    row = await conn.fetchrow(
        "SELECT * FROM public.sessions WHERE id = $1;",
        session_id,
    )
    return dict(row) if row else None


async def lock_session_for_update(
    conn: asyncpg.Connection,
    session_id: str,
) -> dict[str, Any] | None:
    """Acquire exclusive FOR UPDATE lock on session row (Section 8.7)."""
    row = await conn.fetchrow(
        "SELECT * FROM public.sessions WHERE id = $1 FOR UPDATE;",
        session_id,
    )
    return dict(row) if row else None


async def get_session_items(
    conn: asyncpg.Connection,
    session_id: str,
) -> list[dict[str, Any]]:
    """Fetch all bill items for a session ordered by position."""
    rows = await conn.fetch(
        "SELECT * FROM public.bill_items WHERE session_id = $1 ORDER BY position ASC;",
        session_id,
    )
    return [dict(r) for r in rows]


async def update_session_status(
    conn: asyncpg.Connection,
    session_id: str,
    new_status: str,
) -> dict[str, Any]:
    """Update session status."""
    row = await conn.fetchrow(
        """
        UPDATE public.sessions
        SET status = $2, updated_at = now()
        WHERE id = $1
        RETURNING *;
        """,
        session_id,
        new_status,
    )
    if not row:
        raise RuntimeError("Failed to update session status.")
    return dict(row)


async def get_participant(
    conn: asyncpg.Connection,
    session_id: str,
    user_id: str,
) -> dict[str, Any] | None:
    """Fetch participant row for a specific user within a session."""
    row = await conn.fetchrow(
        """
        SELECT * FROM public.session_participants
        WHERE session_id = $1 AND user_id = $2;
        """,
        session_id,
        user_id,
    )
    return dict(row) if row else None


async def list_participants(
    conn: asyncpg.Connection,
    session_id: str,
) -> list[dict[str, Any]]:
    """List all participants in a session."""
    rows = await conn.fetch(
        """
        SELECT * FROM public.session_participants
        WHERE session_id = $1
        ORDER BY joined_at ASC;
        """,
        session_id,
    )
    return [dict(r) for r in rows]
