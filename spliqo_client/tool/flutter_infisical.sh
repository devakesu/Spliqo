#!/usr/bin/env bash
set -eo pipefail

CMD="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Switch to Flutter project root if invoked from workspace root
if [[ ! -f "pubspec.yaml" && -f "$CLIENT_DIR/pubspec.yaml" ]]; then
  cd "$CLIENT_DIR"
fi

# When flutter is invoked to run or test, inject in-memory Infisical defines
if [[ "$CMD" == "run" || "$CMD" == "test" ]]; then
  # Ensure ADB forward bridge is active when inside container using host ADB
  if [[ -n "$ADB_SERVER_SOCKET" ]] && ! pgrep -f "adb_forward_bridge.py" >/dev/null 2>&1; then
    nohup python3 "$WORKSPACE_ROOT/scripts/adb_forward_bridge.py" >/tmp/adb_forward_bridge.log 2>&1 &
  fi

  INFISICAL_ENV="${INFISICAL_ENVIRONMENT:-dev}"
  PROJECT_ID="${INFISICAL_PROJECT_ID:-${INFISICAL_SECRETS_PROJECT_ID:-}}"
  EXPORT_FLAGS=(--env="$INFISICAL_ENV" --path=/public --format=json)
  if [[ -n "$PROJECT_ID" ]]; then
    EXPORT_FLAGS+=(--projectId="$PROJECT_ID")
  fi
  if [[ -n "${INFISICAL_SITE_URL:-}" ]]; then
    SITE_URL="${INFISICAL_SITE_URL%/}"
    [[ "$SITE_URL" != */api ]] && SITE_URL="${SITE_URL}/api"
    EXPORT_FLAGS+=(--domain="$SITE_URL")
  fi

  DEFINES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && DEFINES+=("$line")
  done < <(
    if command -v direnv >/dev/null 2>&1 && [[ -d "$WORKSPACE_ROOT" ]]; then
      direnv exec "$WORKSPACE_ROOT" infisical export "${EXPORT_FLAGS[@]}" 2>/dev/null | jq -r '.[] | "--dart-define=\(.key)=\(.value)"' 2>/dev/null || true
    else
      infisical export "${EXPORT_FLAGS[@]}" 2>/dev/null | jq -r '.[] | "--dart-define=\(.key)=\(.value)"' 2>/dev/null || true
    fi
  )

  shift # Remove 'run' or 'test'
  exec flutter "$CMD" "${DEFINES[@]}" "$@"
else
  exec flutter "$@"
fi
