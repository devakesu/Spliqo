"""Service for invites and participant joining."""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

from app.core.database import get_db_connection
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.repositories import audit_repo, invites_repo, sessions_repo
from app.schemas.participants import CreateInviteResponse, ParticipantResponse


async def create_invite(
    user_id: str,
    session_id: str,
) -> CreateInviteResponse:
    """Host action to generate a secure random session invite token (Section 5.6)."""
    async with get_db_connection() as conn, conn.transaction():
        session_row = await sessions_repo.get_session_by_id(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        if str(session_row["host_id"]) != user_id:
            raise ForbiddenError("Only the host can generate invite links.")

        if session_row["status"] not in ("draft", "active"):
            raise ConflictError(f"Cannot generate invites for session in '{session_row['status']}' status.")

        # Generate 256-bit cryptographic token (at least 128 bits entropy)
        raw_token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
        expires_at = datetime.now(UTC) + timedelta(days=7)

        await invites_repo.create_invite(
            conn=conn,
            session_id=session_id,
            token_hash=token_hash,
            created_by=user_id,
            expires_at=expires_at,
        )

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="invite_created",
            resource_type="session",
            resource_id=session_id,
            after_state={"token_hash": token_hash, "expires_at": expires_at.isoformat()},
        )

        return CreateInviteResponse(
            invite_token=raw_token,
            session_id=session_id,
            expires_at=expires_at.isoformat(),
        )


async def join_session(
    user_id: str,
    invite_token: str,
    display_name: str,
) -> ParticipantResponse:
    """Participant action to join an active session via an invite token."""
    token_hash = hashlib.sha256(invite_token.strip().encode("utf-8")).hexdigest()

    async with get_db_connection() as conn, conn.transaction():
        invite = await invites_repo.get_active_invite(conn, token_hash)
        if not invite:
            raise NotFoundError("Invite link is invalid, expired, or revoked.")

        session_id = str(invite["session_id"])

        # Lock session row to serialize participant additions against the cap
        session_row = await sessions_repo.lock_session_for_update(conn, session_id)
        if not session_row:
            raise NotFoundError("Session not found.")

        # Invites only valid while active (Section 5.6)
        if session_row["status"] != "active":
            raise ConflictError("Session is not currently active for joining.")

        # Idempotent check if already participant
        existing = await sessions_repo.get_participant(conn, session_id, user_id)
        if existing:
            return ParticipantResponse(
                id=str(existing["id"]),
                session_id=str(existing["session_id"]),
                user_id=str(existing["user_id"]),
                role=existing["role"],
                display_name=existing["display_name"],
                selection_completed_at=existing["selection_completed_at"].isoformat()
                if existing["selection_completed_at"]
                else None,
            )

        # Check participant cap (Section 7.2: 30 participants)
        current_count = await invites_repo.count_participants(conn, session_id)
        if current_count >= 30:
            raise ConflictError("Participant cap (30) reached for this session.")

        new_participant = await invites_repo.add_participant(
            conn=conn,
            session_id=session_id,
            user_id=user_id,
            display_name=display_name,
        )

        await audit_repo.record_audit_event(
            conn=conn,
            actor_id=user_id,
            action="participant_joined",
            resource_type="session",
            resource_id=session_id,
            after_state={"participant_id": str(new_participant["id"]), "display_name": display_name},
        )

        return ParticipantResponse(
            id=str(new_participant["id"]),
            session_id=str(new_participant["session_id"]),
            user_id=str(new_participant["user_id"]),
            role=new_participant["role"],
            display_name=new_participant["display_name"],
            selection_completed_at=None,
        )
