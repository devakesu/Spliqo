"""FastAPI router for session management and lifecycle."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, Form, UploadFile, status

from app.core.security.auth import get_current_user_id
from app.schemas.sessions import (
    CreateDraftSessionRequest,
    FinalizeSessionResponse,
    ParseReceiptResponse,
    ResolveUnclaimedRequest,
    SessionResponse,
    UpdateDraftSessionRequest,
)
from app.services import sessions_service

router = APIRouter(prefix="/sessions", tags=["Sessions"])


@router.post("/parse", response_model=ParseReceiptResponse, status_code=status.HTTP_201_CREATED)
async def parse_receipt_session(
    user_id: Annotated[str, Depends(get_current_user_id)],
    file: Annotated[UploadFile, File(...)],
    host_display_name: Annotated[str, Form()] = "Host",
) -> ParseReceiptResponse:
    """Upload and parse receipt image using Gemini Vision and create a draft session."""
    image_bytes = await file.read()
    content_type = file.content_type or "image/jpeg"
    return await sessions_service.parse_and_create_draft(
        user_id=user_id,
        image_bytes=image_bytes,
        content_type=content_type,
        host_display_name=host_display_name,
    )


@router.post("/draft", response_model=SessionResponse, status_code=status.HTTP_201_CREATED)
async def create_draft_session(
    data: CreateDraftSessionRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SessionResponse:
    """Create a new draft session and items."""
    return await sessions_service.create_draft(user_id=user_id, data=data)


@router.put("/{session_id}/draft", response_model=SessionResponse)
async def update_draft_session(
    session_id: str,
    data: UpdateDraftSessionRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SessionResponse:
    """Update line items and adjustments in an existing draft session before activation."""
    return await sessions_service.update_draft(user_id=user_id, session_id=session_id, data=data)


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SessionResponse:
    """Fetch session details for authorized members."""
    return await sessions_service.get_session(user_id=user_id, session_id=session_id)


@router.post("/{session_id}/activate", response_model=SessionResponse)
async def activate_session(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> SessionResponse:
    """Host action to activate a draft session."""
    return await sessions_service.activate_session(user_id=user_id, session_id=session_id)


@router.post("/{session_id}/resolve-unclaimed")
async def resolve_unclaimed(
    session_id: str,
    data: ResolveUnclaimedRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> dict[str, Any]:
    """Host action to bulk resolve unclaimed items during reviewing."""
    return await sessions_service.resolve_unclaimed_items(
        user_id=user_id,
        session_id=session_id,
        data=data,
    )


@router.post("/{session_id}/finalize", response_model=FinalizeSessionResponse)
async def finalize_session(
    session_id: str,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> FinalizeSessionResponse:
    """Host action to authoritatively finalize a session and compute final shares."""
    return await sessions_service.finalize_session(user_id=user_id, session_id=session_id)
