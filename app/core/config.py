"""Application configuration settings management via Pydantic BaseSettings.

Defines environment variables, runtime secret validation, and rate-limiting
configuration loaded strictly from runtime environment variables injected by Infisical.
"""

from typing import Any

from pydantic import AliasChoices, Field, ValidationInfo, field_validator
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    """Application settings loaded strictly from Infisical-injected environment variables.

    Sensitive credentials and secrets must be injected into process memory by
    Infisical at runtime (`infisical run ...`). Local `.env` files are never loaded.
    """

    # --- Application Metadata ---
    app_name: str = "Spliqo"
    app_version: str = "0.1.0"
    app_commit_sha: str = "dev"
    app_domain: str = "localhost:8000"
    environment: str = Field(
        default="development",
        validation_alias=AliasChoices("ENVIRONMENT", "APP_ENV"),
    )
    debug: bool = True
    backend_url: str | None = None
    host: str = "127.0.0.1"
    port: int = 8000

    @field_validator("debug", mode="before")
    @classmethod
    def parse_debug(cls, v: Any) -> bool:
        """Parse boolean debug flag permissively for container environments."""
        if isinstance(v, str):
            if v.lower() in ("release", "prod", "production", "false", "0", "no"):
                return False
            if v.lower() in ("debug", "dev", "development", "true", "1", "yes"):
                return True
        return bool(v)

    # --- Networking & CORS ---
    allowed_origins: str = (
        "http://localhost:3000,http://localhost:8080,http://127.0.0.1:8000"
    )
    proxy_headers: bool = True
    forwarded_allow_ips: str = "*"

    # --- Rate Limiting & Caching ---
    enable_rate_limiting: bool = True
    rate_limit_health: str = "60/minute"
    redis_url: str | None = None

    # --- Database Settings ---
    database_url: str
    database_pool_min: int = 2
    database_pool_max: int = 10

    # --- Supabase Integration (Publishable / Secret / ECC P-256 JWKS) ---
    supabase_url: str
    supabase_publishable_key: str
    supabase_secret_key: str
    supabase_jwks_url: str | None = None
    supabase_jwt_issuer: str | None = None
    supabase_jwt_audience: str = "authenticated"

    # --- AI & Vision Services ---
    gemini_api_key: str | None = None
    gemini_model_id: str = "gemini-2.0-flash"

    # --- Infisical KMS Envelope Encryption ---
    infisical_site_url: str = "https://app.infisical.com"
    infisical_environment: str = "dev"
    infisical_kms_key_id: str
    infisical_kms_universal_auth_client_id: str
    infisical_kms_universal_auth_client_secret: str

    # --- Security & Cryptographic Keys (Blind Index & Signing) ---
    admin_api_key: str | None = None
    hmac_signing_key: str | None = None
    fle_blind_index_key_hex: str

    @field_validator(
        "database_url",
        "supabase_url",
        "supabase_publishable_key",
        "supabase_secret_key",
        "infisical_kms_key_id",
        "infisical_kms_universal_auth_client_id",
        "infisical_kms_universal_auth_client_secret",
    )
    @classmethod
    def validate_non_empty_required(cls, v: str) -> str:
        """Ensure required Infisical-injected values are non-empty and not placeholders."""
        cleaned = v.strip()
        if not cleaned or cleaned.startswith("<YOUR_"):
            raise ValueError("Required runtime secret must be injected by Infisical.")
        return cleaned

    @field_validator("supabase_url")
    @classmethod
    def validate_online_supabase_url(cls, v: str, info: ValidationInfo) -> str:
        """Require HTTPS online Supabase URL outside of test environments."""
        cleaned = v.strip().rstrip("/")
        env = str(info.data.get("environment", "development")).lower()
        if env != "test" and not cleaned.startswith("https://"):
            raise ValueError("SUPABASE_URL must be an https:// online Supabase URL.")
        return cleaned

    @field_validator("fle_blind_index_key_hex")
    @classmethod
    def validate_blind_index_key_hex(cls, v: str) -> str:
        """Validate that the blind index key is a 32-byte (64-char) hex string."""
        cleaned = v.strip()
        try:
            raw = bytes.fromhex(cleaned)
        except ValueError as err:
            raise ValueError("FLE_BLIND_INDEX_KEY_HEX must be valid hex.") from err
        if len(raw) != 32:
            raise ValueError(
                f"FLE_BLIND_INDEX_KEY_HEX must decode to 32 bytes, got {len(raw)}.",
            )
        return cleaned

    @property
    def fle_blind_index_key(self) -> bytes:
        """Return the 32-byte binary HMAC blind index key."""
        return bytes.fromhex(self.fle_blind_index_key_hex)

    @property
    def resolved_jwks_url(self) -> str:
        """Return the Supabase JWKS endpoint URL for ECC (P-256 / ES256) verification."""
        if self.supabase_jwks_url:
            return self.supabase_jwks_url.strip()
        return f"{self.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"

    @property
    def resolved_jwt_issuer(self) -> str:
        """Return the expected Supabase JWT issuer URL."""
        if self.supabase_jwt_issuer:
            return self.supabase_jwt_issuer.strip()
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def resolved_infisical_api_url(self) -> str:
        """Return the normalized Infisical API base URL ending in /api."""
        base = self.infisical_site_url.rstrip("/")
        if not base.endswith("/api"):
            base = f"{base}/api"
        return base

    model_config = SettingsConfigDict(
        extra="ignore",
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        """Strictly disable .env file loading; only allow runtime environment variables."""
        _ = (settings_cls, dotenv_settings)
        return (
            init_settings,
            env_settings,
            file_secret_settings,
        )


try:
    # Settings are validated at import time to fail fast if Infisical secrets are missing
    settings = Settings()  # type: ignore[call-arg]
except Exception as e:
    raise RuntimeError(
        "CRITICAL: Failed to validate Spliqo application settings.\n"
        "Strict Infisical env loading is enabled (.env files are ignored).\n"
        "Ensure you are running the application wrapped inside Infisical:\n"
        "  infisical run --env=dev --path=/public --path=/runtime -- "
        "uvicorn app.main:app --reload --reload-dir app\n"
        f"Error Details: {e}",
    ) from e
