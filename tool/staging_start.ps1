$ErrorActionPreference = "Stop"

if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  Write-Error "Supabase CLI is not installed. Install it first, then rerun this script."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker-compatible runtime was not found. Install/start Docker Desktop first."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Error "Docker is installed but not running."
}

Write-Host "[1/3] Starting local Supabase..."
supabase start
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[2/3] Rebuilding local database from migrations + seed..."
supabase db reset
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[3/3] Local staging status"
supabase status
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Local staging is ready."
Write-Host "Next: copy env/staging.example.json to env/staging.json"
Write-Host "and replace SUPABASE_PUBLISHABLE_KEY with the local key shown above."
