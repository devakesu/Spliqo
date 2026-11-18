"""Repository for item claims."""

from collections import defaultdict

import asyncpg


async def get_claims_by_session(
    conn: asyncpg.Connection,
    session_id: str,
) -> dict[str, list[str]]:
    """Retrieve all claims in a session mapped by item_id to list of participant_ids."""
    rows = await conn.fetch(
        """
        SELECT item_id, participant_id
        FROM public.item_claims
        WHERE session_id = $1;
        """,
        session_id,
    )
    result: dict[str, list[str]] = defaultdict(list)
    for r in rows:
        result[str(r["item_id"])].append(str(r["participant_id"]))
    return dict(result)


async def bulk_insert_host_claims(
    conn: asyncpg.Connection,
    session_id: str,
    claims: list[tuple[str, str]],  # (item_id, participant_id)
) -> None:
    """Insert host-assigned claims during reviewing resolution."""
    if not claims:
        return
    for item_id, participant_id in claims:
        await conn.execute(
            """
            INSERT INTO public.item_claims (
              session_id, item_id, participant_id, source
            ) VALUES ($1, $2, $3, 'host_assigned')
            ON CONFLICT (item_id, participant_id) DO NOTHING;
            """,
            session_id,
            item_id,
            participant_id,
        )
