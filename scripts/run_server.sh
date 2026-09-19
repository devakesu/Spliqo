#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VENV_PYTHON="${WORKSPACE_ROOT}/.venv/bin/python"
if [ ! -x "${VENV_PYTHON}" ]; then
  VENV_PYTHON="python3"
fi

echo "🚀 Starting Spliqo Backend with Infisical (/public + /runtime)..."

# If infisical CLI is available, execute under infisical secrets injection
if command -v infisical >/dev/null 2>&1; then
  exec infisical run --env=dev --path=/public --path=/runtime -- \
    "${VENV_PYTHON}" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --reload-dir app
else
  echo "⚠️ Infisical CLI not detected in PATH, falling back to direct execution..."
  exec "${VENV_PYTHON}" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload --reload-dir app
fi

