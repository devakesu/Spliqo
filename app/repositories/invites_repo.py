"""Repository for session invites and participant joins."""

from datetime import datetime
from typing import Any

import asyncpg


async def create_invite(
    conn: asyncpg.Connection,
    session_id: str,
    token_hash: str,
    created_by: str,
    expires_at: datetime,
) -> dict[str, Any]:
    """Store hashed session invite token."""
    row = await conn.fetchrow(
        """
        INSERT INTO public.session_invites (
          session_id, token_hash, created_by, expires_at
        ) VALUES ($1, $2, $3, $4)
        RETURNING *;
        """,
        session_id,
        token_hash,
        created_by,
        expires_at,
    )
    if not row:
        raise RuntimeError("Failed to create invite.")
    return dict(row)


async def get_active_invite(
    conn: asyncpg.Connection,
    token_hash: str,
) -> dict[str, Any] | None:
    """Find valid, non-expired, non-revoked invite by token hash."""
    row = await conn.fetchrow(
        """
        SELECT * FROM public.session_invites
        WHERE token_hash = $1
          AND is_revoked = false
          AND expires_at > now();
        """,
        token_hash,
    )
    return dict(row) if row else None


async def add_participant(
    conn: asyncpg.Connection,
    session_id: str,
    user_id: str,
    display_name: str,
) -> dict[str, Any]:
    """Add a new participant to a session."""
    row = await conn.fetchrow(
        """
        INSERT INTO public.session_participants (
          session_id, user_id, role, display_name
        ) VALUES ($1, $2, 'participant', $3)
        RETURNING *;
        """,
        session_id,
        user_id,
        display_name,
    )
    if not row:
        raise RuntimeError("Failed to add participant.")
    return dict(row)


async def count_participants(
    conn: asyncpg.Connection,
    session_id: str,
) -> int:
    """Return count of participants in a session."""
    count = await conn.fetchval(
        "SELECT count(*) FROM public.session_participants WHERE session_id = $1;",
        session_id,
    )
    return int(count or 0)
