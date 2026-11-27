"""FastAPI router for authenticated user profile endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request, status

from app.core.config import settings
from app.core.infra.limiter import limiter
from app.core.security.auth import get_current_user_id
from app.schemas.users import UpdateProfileRequest, UserProfileResponse
from app.services import users_service

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/me/profile", response_model=UserProfileResponse, status_code=status.HTTP_200_OK)
@limiter.limit(settings.rate_limit_profile)  # pyright: ignore[reportUntypedFunctionDecorator,reportUnknownMemberType]
async def get_my_profile(
    request: Request,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> UserProfileResponse:
    """Fetch the authenticated user's profile."""
    _ = request
    return await users_service.get_my_profile(user_id=user_id)


@router.put("/me/profile", response_model=UserProfileResponse, status_code=status.HTTP_200_OK)
@limiter.limit(settings.rate_limit_profile)  # pyright: ignore[reportUntypedFunctionDecorator,reportUnknownMemberType]
async def update_my_profile(
    request: Request,
    data: UpdateProfileRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> UserProfileResponse:
    """Create or update display_name and FLE-encrypted phone number for caller."""
    _ = request
    return await users_service.upsert_my_profile(user_id=user_id, data=data)
