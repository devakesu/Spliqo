#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VENV_PYTHON="${WORKSPACE_ROOT}/.venv/bin/python"
if [ ! -x "${VENV_PYTHON}" ]; then
  VENV_PYTHON="python3"
fi

if ! command -v infisical >/dev/null 2>&1; then
  echo "❌ ERROR: Infisical CLI is required for strict environment loading." >&2
  echo "Install Infisical CLI and authenticate via direnv (.envrc) or INFISICAL_TOKEN." >&2
  exit 1
fi

INFISICAL_ENV="${INFISICAL_ENVIRONMENT:-dev}"
PROJECT_ID="${INFISICAL_PROJECT_ID:-${INFISICAL_SECRETS_PROJECT_ID:-}}"

INFISICAL_FLAGS=(--env="${INFISICAL_ENV}" --path=/public --path=/runtime)
if [ -n "${PROJECT_ID}" ]; then
  INFISICAL_FLAGS+=(--projectId="${PROJECT_ID}")
fi
if [ -n "${INFISICAL_SITE_URL:-}" ]; then
  SITE_URL="${INFISICAL_SITE_URL%/}"
  if [[ "${SITE_URL}" != */api ]]; then
    SITE_URL="${SITE_URL}/api"
  fi
  INFISICAL_FLAGS+=(--domain="${SITE_URL}")
fi

echo "🚀 Starting Spliqo Backend with strict Infisical injection (env=${INFISICAL_ENV}, paths=/public,/runtime)..."

exec infisical run "${INFISICAL_FLAGS[@]}" -- \
  "${VENV_PYTHON}" -m uvicorn app.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8000}" --reload --reload-dir app
