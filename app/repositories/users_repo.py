"""Repository for authenticated user profile persistence."""

from typing import Any

import asyncpg


async def get_user_profile(
    conn: asyncpg.Connection,
    user_id: str,
) -> dict[str, Any] | None:
    """Fetch a user profile row by user_id."""
    row = await conn.fetchrow(
        """
        SELECT id, display_name, phone_number_encrypted
        FROM public.user_profiles
        WHERE id = $1;
        """,
        user_id,
    )
    return dict(row) if row else None


async def upsert_user_profile(
    conn: asyncpg.Connection,
    user_id: str,
    display_name: str,
    phone_encrypted: bytes | None,
    phone_bidx: str | None,
) -> dict[str, Any]:
    """Create or update a user's profile and optional FLE-encrypted phone fields."""
    row = await conn.fetchrow(
        """
        INSERT INTO public.user_profiles (
          id, display_name, phone_number_encrypted, phone_number_bidx
        ) VALUES ($1, $2, $3, $4)
        ON CONFLICT (id) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          phone_number_encrypted = COALESCE(
            EXCLUDED.phone_number_encrypted,
            public.user_profiles.phone_number_encrypted
          ),
          phone_number_bidx = COALESCE(
            EXCLUDED.phone_number_bidx,
            public.user_profiles.phone_number_bidx
          ),
          updated_at = now()
        RETURNING id, display_name, phone_number_encrypted;
        """,
        user_id,
        display_name,
        phone_encrypted,
        phone_bidx,
    )
    if not row:
        raise RuntimeError("Failed to persist user profile.")
    return dict(row)
