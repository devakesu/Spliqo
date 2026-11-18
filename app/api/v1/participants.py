"""FastAPI router for session invites and participant joining."""

from typing import Annotated

from fastapi import APIRouter, Depends, status

from app.core.security.auth import get_current_user_id
from app.schemas.participants import (
    CreateInviteResponse,
    JoinSessionRequest,
    ParticipantResponse,
)
from app.services import participants_service

router = APIRouter(prefix="/sessions", tags=["Participants"])


@router.post("/{session_id}/invites", response_model=CreateInviteResponse, status_code=status.HTTP_201_CREATED)
async def create_invite(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> CreateInviteResponse:
    """Host action to generate an invite token."""
    return await participants_service.create_invite(user_id=user_id, session_id=session_id)


@router.post("/join", response_model=ParticipantResponse, status_code=status.HTTP_200_OK)
async def join_session(
    data: JoinSessionRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> ParticipantResponse:
    """Participant action to join an active session using an invite token."""
    return await participants_service.join_session(
        user_id=user_id,
        invite_token=data.invite_token,
        display_name=data.display_name,
    )
