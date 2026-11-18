"""Database connection pool management using asyncpg."""

import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

import asyncpg

from app.core.config import settings

logger = logging.getLogger(__name__)

_pool: asyncpg.Pool | None = None


async def init_db_pool() -> asyncpg.Pool:
    """Initialize the global asyncpg connection pool."""
    global _pool
    if _pool is None:
        logger.info("Initializing database connection pool...")
        _pool = await asyncpg.create_pool(
            dsn=settings.database_url,
            min_size=settings.database_pool_min,
            max_size=settings.database_pool_max,
            statement_cache_size=0,
        )
    return _pool


async def close_db_pool() -> None:
    """Close the global asyncpg connection pool."""
    global _pool
    if _pool is not None:
        logger.info("Closing database connection pool...")
        await _pool.close()
        _pool = None


def get_db_pool() -> asyncpg.Pool:
    """Retrieve the initialized database connection pool."""
    if _pool is None:
        raise RuntimeError("Database connection pool is not initialized.")
    return _pool


@asynccontextmanager
async def get_db_connection() -> AsyncGenerator[Any, None]:
    """Context manager for acquiring a database connection from the pool."""
    pool = get_db_pool()
    async with pool.acquire() as conn:
        yield conn
