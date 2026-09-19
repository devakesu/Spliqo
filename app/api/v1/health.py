"""Health check endpoints for Spliqo backend services."""

from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.infra.limiter import limiter

router = APIRouter()


class HealthResponse(BaseModel):
    """Health check payload representation."""

    status: Literal["ok", "degraded", "down"] = Field(
        default="ok",
        description="Current health status of the service",
    )
    app: str = Field(description="Application name")
    version: str = Field(description="Application version")
    commit_sha: str = Field(description="Commit SHA identifier")
    environment: str = Field(description="Deployment environment")
    timestamp: str = Field(description="ISO 8601 UTC timestamp")


@router.get(
    "/health",
    response_model=HealthResponse,
    summary="Service Health Check",
    description="Returns operational status, version, and runtime environment metadata.",
)
@limiter.limit(settings.rate_limit_health)  # pyright: ignore[reportUntypedFunctionDecorator,reportUnknownMemberType]
async def health_check(request: Request) -> HealthResponse:
    """Evaluates and returns API service health status.

    Args:
        request: Incoming FastAPI HTTP request.

    Returns:
        HealthResponse: Health status and metadata payload.
    """
    _ = request
    return HealthResponse(
        status="ok",
        app=settings.app_name,
        version=settings.app_version,
        commit_sha=settings.app_commit_sha,
        environment=settings.environment,
        timestamp=datetime.now(UTC).isoformat(),
    )
