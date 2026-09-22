#!/bin/zsh

set -euo pipefail

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: Supabase CLI is not installed."
  echo "Install it first, then rerun this script."
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

echo "[1/3] Starting local Supabase..."
supabase start

echo "[2/3] Rebuilding local database from migrations + seed..."
supabase db reset

echo "[3/3] Local staging status"
supabase status

echo ""
echo "Local staging is ready."
echo "Next: copy env/staging.example.json to env/staging.json"
echo "and replace SUPABASE_PUBLISHABLE_KEY with the local key shown above."
