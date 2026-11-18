"""Standard domain error model and FastAPI exception handlers.

Adheres strictly to Spliqo Engineering Standards Section 14:
Never leaks database internals, table names, SQL, or stack traces.
"""

from typing import Any

from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class SpliqoBaseError(Exception):
    """Base exception for all domain errors."""

    def __init__(
        self,
        message: str = "Request could not be processed.",
        code: str = "error",
        status_code: int = status.HTTP_400_BAD_REQUEST,
        fields: list[dict[str, str]] | None = None,
    ) -> None:
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code
        self.fields = fields or []


class UnauthorizedError(SpliqoBaseError):
    """Raised when authentication credentials are missing or invalid."""

    def __init__(self, message: str = "Authentication required.") -> None:
        super().__init__(
            message=message,
            code="unauthorized",
            status_code=status.HTTP_401_UNAUTHORIZED,
        )


class ForbiddenError(SpliqoBaseError):
    """Raised when the authenticated actor lacks permission for an object."""

    def __init__(self, message: str = "Access denied.") -> None:
        super().__init__(
            message=message,
            code="forbidden",
            status_code=status.HTTP_403_FORBIDDEN,
        )


class NotFoundError(SpliqoBaseError):
    """Raised when a resource is not found or hidden for security."""

    def __init__(self, message: str = "Resource not found.") -> None:
        super().__init__(
            message=message,
            code="not_found",
            status_code=status.HTTP_404_NOT_FOUND,
        )


class ConflictError(SpliqoBaseError):
    """Raised on state machine conflicts or concurrent revisions."""

    def __init__(
        self,
        message: str = "Request conflicts with current state.",
        code: str = "conflict",
        fields: list[dict[str, str]] | None = None,
    ) -> None:
        super().__init__(
            message=message,
            code=code,
            status_code=status.HTTP_409_CONFLICT,
            fields=fields,
        )


class UnresolvedItemsError(ConflictError):
    """Raised during finalization when bill items remain unclaimed."""

    def __init__(
        self,
        unclaimed_item_ids: list[str],
        message: str = "All items must be resolved before finalizing the session.",
    ) -> None:
        fields = [{"field": f"item:{item_id}", "reason": "unclaimed"} for item_id in unclaimed_item_ids]
        super().__init__(
            message=message,
            code="unresolved_items",
            fields=fields,
        )


class ReconciliationError(ConflictError):
    """Raised when subtotal, adjustments, and line items do not sum to total."""

    def __init__(
        self,
        message: str = "Session amounts do not reconcile with line items.",
    ) -> None:
        super().__init__(
            message=message,
            code="reconciliation_failed",
        )


def format_error_response(
    code: str,
    message: str,
    request_id: str = "unknown",
    fields: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """Format payload according to the standard error envelope (Section 14)."""
    return {
      "error": {
        "code": code,
        "message": message,
        "fields": fields or [],
        "request_id": request_id,
      },
    }


async def spliqo_exception_handler(request: Request, exc: SpliqoBaseError) -> JSONResponse:
    """Handle domain exceptions."""
    request_id = request.headers.get("X-Request-ID", "unknown")
    content = format_error_response(
        code=exc.code,
        message=exc.message,
        request_id=request_id,
        fields=exc.fields,
    )
    return JSONResponse(status_code=exc.status_code, content=content)


async def validation_exception_handler(
    request: Request,
    exc: RequestValidationError,
) -> JSONResponse:
    """Handle Pydantic validation errors."""
    request_id = request.headers.get("X-Request-ID", "unknown")
    fields: list[dict[str, str]] = []
    for err in exc.errors():
        loc = ".".join(str(p) for p in err.get("loc", []))
        fields.append({"field": loc, "reason": err.get("msg", "Invalid value")})

    content = format_error_response(
        code="validation_error",
        message="Request validation failed.",
        request_id=request_id,
        fields=fields,
    )
    return JSONResponse(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, content=content)
