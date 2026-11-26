"""Infisical KMS client for Envelope Encryption (DEK wrapping & unwrapping).

Uses Infisical Universal Auth to obtain short-lived access tokens and calls
Infisical KMS `/encrypt` and `/decrypt` endpoints solely for Data Encryption Key
(DEK) wrapping/unwrapping—never for raw application payloads.
"""

import asyncio
import base64
import time
from typing import Final, Protocol, cast

import httpx

KEY_LENGTH_BYTES: Final[int] = 32
DEFAULT_TOKEN_TTL_SECONDS: Final[float] = 300.0
TOKEN_REFRESH_BUFFER_SECONDS: Final[float] = 60.0


class KMSError(Exception):
    """Base exception for KMS operations."""


class KMSAuthError(KMSError):
    """Raised when Universal Auth authentication with Infisical fails."""


class KMSKeyError(KMSError):
    """Raised when KMS key wrapping or unwrapping fails."""


class KMSProvider(Protocol):
    """Protocol for KMS providers capable of wrapping and unwrapping 256-bit DEKs."""

    async def wrap_key(self, plaintext_dek: bytes) -> bytes:
        """Encrypt (wrap) a 32-byte plaintext DEK using the KMS root key."""
        ...

    async def unwrap_key(self, wrapped_dek: bytes) -> bytes:
        """Decrypt (unwrap) a KMS-wrapped DEK back into 32 plaintext bytes."""
        ...


class InfisicalKMSClient:
    """Asynchronous client for Infisical KMS using Universal Auth."""

    def __init__(
        self,
        api_url: str,
        key_id: str,
        client_id: str,
        client_secret: str,
        http_client: httpx.AsyncClient | None = None,
        timeout_seconds: float = 10.0,
    ) -> None:
        self._api_url = api_url.rstrip("/")
        self._key_id = key_id
        self._client_id = client_id
        self._client_secret = client_secret
        self._external_client = http_client
        self._timeout_seconds = timeout_seconds

        self._access_token: str | None = None
        self._token_expires_at: float = 0.0
        self._auth_lock = asyncio.Lock()

    async def _request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict[str, str],
        headers: dict[str, str] | None = None,
    ) -> httpx.Response:
        """Execute an HTTP request using the injected or ephemeral AsyncClient."""
        url = f"{self._api_url}{path}"
        if self._external_client is not None:
            return await self._external_client.request(
                method,
                url,
                json=json_body,
                headers=headers,
                timeout=self._timeout_seconds,
            )
        async with httpx.AsyncClient(timeout=self._timeout_seconds) as client:
            return await client.request(
                method,
                url,
                json=json_body,
                headers=headers,
            )

    async def _get_access_token(self, *, force_refresh: bool = False) -> str:
        """Return a valid Universal Auth access token, refreshing if needed."""
        now = time.monotonic()
        if (
            not force_refresh
            and self._access_token is not None
            and now < (self._token_expires_at - TOKEN_REFRESH_BUFFER_SECONDS)
        ):
            return self._access_token

        async with self._auth_lock:
            now = time.monotonic()
            if (
                not force_refresh
                and self._access_token is not None
                and now < (self._token_expires_at - TOKEN_REFRESH_BUFFER_SECONDS)
            ):
                return self._access_token

            try:
                resp = await self._request(
                    "POST",
                    "/v1/auth/universal-auth/login",
                    json_body={
                        "clientId": self._client_id,
                        "clientSecret": self._client_secret,
                    },
                )
            except httpx.HTTPError as err:
                raise KMSAuthError(f"Infisical Universal Auth request failed: {err}") from err

            if resp.status_code != 200:
                raise KMSAuthError(
                    f"Infisical Universal Auth login failed with status {resp.status_code}.",
                )

            data = resp.json()
            token = data.get("accessToken")
            if not isinstance(token, str) or not token:
                raise KMSAuthError("Infisical Universal Auth response missing accessToken.")

            expires_in = float(data.get("expiresIn", DEFAULT_TOKEN_TTL_SECONDS))
            self._access_token = token
            self._token_expires_at = time.monotonic() + expires_in
            return token

    async def _kms_post(self, operation: str, payload: dict[str, str]) -> dict[str, object]:
        """Call Infisical KMS encrypt/decrypt with automatic single-retry on 401."""
        token = await self._get_access_token()
        path = f"/v1/kms/keys/{self._key_id}/{operation}"
        try:
            resp = await self._request(
                "POST",
                path,
                json_body=payload,
                headers={"Authorization": f"Bearer {token}"},
            )
            if resp.status_code == 401:
                token = await self._get_access_token(force_refresh=True)
                resp = await self._request(
                    "POST",
                    path,
                    json_body=payload,
                    headers={"Authorization": f"Bearer {token}"},
                )
        except httpx.HTTPError as err:
            raise KMSKeyError(f"Infisical KMS {operation} request failed: {err}") from err

        if resp.status_code != 200:
            raise KMSKeyError(
                f"Infisical KMS {operation} failed with status {resp.status_code}.",
            )

        data = resp.json()
        if not isinstance(data, dict):
            raise KMSKeyError(f"Unexpected Infisical KMS {operation} response format.")
        return cast("dict[str, object]", data)

    async def wrap_key(self, plaintext_dek: bytes) -> bytes:
        """Wrap a 32-byte DEK via Infisical KMS encrypt."""
        if len(plaintext_dek) != KEY_LENGTH_BYTES:
            raise KMSKeyError(
                f"DEK must be {KEY_LENGTH_BYTES} bytes, got {len(plaintext_dek)}.",
            )

        b64_dek = base64.b64encode(plaintext_dek).decode("ascii")
        data = await self._kms_post("encrypt", {"plaintext": b64_dek})
        ciphertext = data.get("ciphertext")
        if not isinstance(ciphertext, str) or not ciphertext:
            raise KMSKeyError("Infisical KMS encrypt response missing ciphertext.")
        return ciphertext.encode("utf-8")

    async def unwrap_key(self, wrapped_dek: bytes) -> bytes:
        """Unwrap a KMS-wrapped DEK via Infisical KMS decrypt."""
        try:
            wrapped_str = wrapped_dek.decode("utf-8")
        except UnicodeDecodeError as err:
            raise KMSKeyError("Wrapped DEK is not valid UTF-8 ciphertext.") from err

        data = await self._kms_post("decrypt", {"ciphertext": wrapped_str})
        b64_dek = data.get("plaintext")
        if not isinstance(b64_dek, str) or not b64_dek:
            raise KMSKeyError("Infisical KMS decrypt response missing plaintext.")

        try:
            dek = base64.b64decode(b64_dek, validate=True)
        except ValueError as err:
            raise KMSKeyError("Infisical KMS decrypt returned invalid base64 DEK.") from err

        if len(dek) != KEY_LENGTH_BYTES:
            raise KMSKeyError(
                f"Unwrapped DEK must be {KEY_LENGTH_BYTES} bytes, got {len(dek)}.",
            )
        return dek
