"""Spliqo API v1 Package."""

from fastapi import APIRouter

from app.api.v1.health import router as health_router
from app.api.v1.participants import router as participants_router
from app.api.v1.payments import router as payments_router
from app.api.v1.sessions import router as sessions_router

api_v1_router = APIRouter()
api_v1_router.include_router(health_router, tags=["Health"])
api_v1_router.include_router(sessions_router)
api_v1_router.include_router(participants_router)
api_v1_router.include_router(payments_router)

__all__ = ["api_v1_router"]

