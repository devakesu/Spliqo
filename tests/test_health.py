"""Tests for health check endpoints, security headers, and request tracking."""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_root_index(async_client: AsyncClient) -> None:
    """Verifies that the root endpoint returns service identity."""
    response = await async_client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["app"] == "Spliqo"
    assert data["status"] == "operational"


@pytest.mark.asyncio
async def test_health_check(async_client: AsyncClient) -> None:
    """Verifies that the health endpoint returns structured health data."""
    response = await async_client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert data["app"] == "Spliqo"
    assert "version" in data
    assert "timestamp" in data


@pytest.mark.asyncio
async def test_security_headers_present(async_client: AsyncClient) -> None:
    """Verifies that standard security headers are attached to responses."""
    response = await async_client.get("/api/v1/health")
    headers = response.headers

    assert headers.get("x-content-type-options") == "nosniff"
    assert headers.get("x-frame-options") == "DENY"
    assert "default-src 'self'" in headers.get("content-security-policy", "")
    assert headers.get("x-xss-protection") == "1; mode=block"
    assert headers.get("server") == "Spliqo-Engine"


@pytest.mark.asyncio
async def test_correlation_id_propagation(async_client: AsyncClient) -> None:
    """Verifies that custom request correlation IDs are propagated."""
    custom_id = "test-request-id-12345"
    response = await async_client.get(
        "/api/v1/health",
        headers={"X-Request-ID": custom_id},
    )
    assert response.headers.get("x-request-id") == custom_id


@pytest.mark.asyncio
async def test_request_size_limit_rejection(async_client: AsyncClient) -> None:
    """Verifies that requests with content-length > 10MB are rejected with 413."""
    oversized = str(11 * 1024 * 1024)
    response = await async_client.post(
        "/",
        headers={"Content-Length": oversized},
    )
    assert response.status_code == 413
    assert "Payload too large" in response.json()["detail"]

