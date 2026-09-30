#!/bin/zsh

set -euo pipefail

ENV_FILE="env/staging.json"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found."
  echo "Copy env/staging.example.json to $ENV_FILE and fill the local Supabase key."
  exit 1
fi

if ! grep -Eq '"SUPABASE_URL"[[:space:]]*:[[:space:]]*"http://(127\.0\.0\.1|localhost|10\.0\.2\.2):54321"' "$ENV_FILE"; then
  echo "ERROR: staging.json does not point to the expected local Supabase API."
  echo "Refusing to run to reduce the risk of accidentally testing against Production."
  echo "Expected host: 127.0.0.1, localhost, or Android emulator 10.0.2.2 on port 54321."
  exit 1
fi

flutter run \
  --dart-define-from-file="$ENV_FILE" \
  "$@"
