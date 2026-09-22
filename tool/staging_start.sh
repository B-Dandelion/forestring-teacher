#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUPABASE_CLI="$REPO_ROOT/node_modules/.bin/supabase"

if [ ! -x "$SUPABASE_CLI" ]; then
  echo "ERROR: Project-local Supabase CLI was not found."
  echo "Run 'npm ci' from the repository root first."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker-compatible runtime was not found."
  echo "Start Docker Desktop (or another compatible runtime) first."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is installed but not running."
  exit 1
fi

cd "$REPO_ROOT"

if git ls-files --eol -- supabase | grep -E 'w/crlf.*\.sql$' >/dev/null 2>&1; then
  echo "ERROR: Supabase SQL files are checked out with CRLF line endings."
  echo "See docs/qa-staging.md for the tracked-file LF refresh procedure."
  exit 1
fi

echo "[1/3] Starting local Supabase..."
"$SUPABASE_CLI" start

echo "[2/3] Rebuilding local database from migrations + seed..."
"$SUPABASE_CLI" db reset

echo "[3/3] Local staging status"
"$SUPABASE_CLI" status

echo ""
echo "Local staging is ready."
echo "Next: copy env/staging.example.json to env/staging.json"
echo "and replace SUPABASE_PUBLISHABLE_KEY with the local key shown above."
