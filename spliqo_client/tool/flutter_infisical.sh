#!/usr/bin/env bash
set -eo pipefail

CMD="$1"

# When flutter is invoked to run or test, inject in-memory Infisical defines
if [[ "$CMD" == "run" || "$CMD" == "test" ]]; then
  DEFINES=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && DEFINES+=("$line")
  done < <(infisical export --path=/public --format=json 2>/dev/null | jq -r '.[] | "--dart-define=\(.key)=\(.value)"' 2>/dev/null || true)

  shift # Remove 'run' or 'test'
  exec flutter "$CMD" "${DEFINES[@]}" "$@"
else
  exec flutter "$@"
fi

