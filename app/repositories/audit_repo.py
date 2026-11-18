"""Repository for append-only audit log."""

import json
from typing import Any

import asyncpg


async def record_audit_event(
    conn: asyncpg.Connection,
    actor_id: str | None,
    action: str,
    resource_type: str,
    resource_id: str,
    before_state: dict[str, Any] | None = None,
    after_state: dict[str, Any] | None = None,
    ip_address: str | None = None,
    trace_id: str | None = None,
) -> None:
    """Record an immutable audit event (Section 8.8)."""
    before_json = json.dumps(before_state, default=str) if before_state else None
    after_json = json.dumps(after_state, default=str) if after_state else None
    await conn.execute(
        """
        INSERT INTO public.audit_log (
          actor_id, action, resource_type, resource_id,
          before_state, after_state, ip_address, trace_id
        ) VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7::inet, $8);
        """,
        actor_id,
        action,
        resource_type,
        resource_id,
        before_json,
        after_json,
        ip_address,
        trace_id,
    )
