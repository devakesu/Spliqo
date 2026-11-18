"""Shared pytest fixtures and test configuration for Spliqo."""

import os
from collections.abc import AsyncIterator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

os.environ.setdefault("DEBUG", "false")
if os.environ.get("DEBUG") == "release":
    os.environ["DEBUG"] = "false"

from app.core.database import close_db_pool, init_db_pool
from app.main import app


@pytest_asyncio.fixture
async def async_client() -> AsyncIterator[AsyncClient]:
    """Provides an asynchronous HTTP test client for the FastAPI app."""
    await init_db_pool()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    await close_db_pool()

