"""Application configuration settings management via Pydantic BaseSettings.

Defines environment variables, runtime secret validation, and rate-limiting
configuration loaded dynamically from Infisical or environment variables.
"""

from typing import Any

from pydantic.fields import FieldInfo
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

# Keys that must NOT be loaded from .env statically under any circumstances.
# They are only allowed to be loaded from the runtime environment injected via Infisical.
BLOCKED_DOTENV_KEYS: set[str] = {
    "supabase_service_role_key",
    "supabase_jwt_secret",
    "redis_url",
    "admin_api_key",
    "hmac_signing_key",
}


class Settings(BaseSettings):
    """Application settings loaded from runtime-injected environment variables.

    Sensitive credentials and secrets are expected to be injected by Infisical
    at runtime rather than sourced from an insecure local .env file.
    """

    # --- Application Metadata ---
    app_name: str = "Spliqo"
    app_version: str = "0.1.0"
    app_commit_sha: str = "dev"
    app_domain: str = "localhost:8000"
    environment: str = "development"
    debug: bool = True
    backend_url: str | None = None

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

    # --- Supabase Integration ---
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    supabase_jwt_secret: str = ""

    # --- Security & Administrative Keys ---
    admin_api_key: str | None = None
    hmac_signing_key: str | None = None

    model_config = SettingsConfigDict(
        env_file=".env",
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
        """Customizes settings sources to strip blocked keys from .env files.

        Ensures that critical secrets can only be injected through runtime environment
        variables managed by Infisical.
        """

        class FilteredDotenvSource(PydanticBaseSettingsSource):
            """Source that filters out sensitive keys from .env files."""

            def get_field_value(
                self,
                field: FieldInfo,
                field_name: str,
            ) -> tuple[Any, str, bool]:
                if field_name in BLOCKED_DOTENV_KEYS:
                    return None, field_name, False
                return dotenv_settings.get_field_value(field, field_name)

            def __call__(self) -> dict[str, Any]:
                raw_data = dotenv_settings()
                return {
                    k: v
                    for k, v in raw_data.items()
                    if k not in BLOCKED_DOTENV_KEYS
                }

        return (
            init_settings,
            env_settings,
            FilteredDotenvSource(settings_cls),
            file_secret_settings,
        )


try:
    # Settings are validated at import time to fail fast if required configuration is missing
    settings = Settings()
except Exception as e:
    raise RuntimeError(
        "CRITICAL: Failed to validate Spliqo application settings.\n"
        "Ensure you are running the application wrapped inside Infisical:\n"
        "  infisical run --env=dev --path=/public --path=/runtime -- "
        "uvicorn app.main:app --reload --reload-dir app\n"
        f"Error Details: {e}",
    ) from e

