$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupabaseCli = Join-Path $RepoRoot "node_modules\.bin\supabase.cmd"

Set-Location $RepoRoot

$FunctionEnvExample = Join-Path $RepoRoot "supabase\functions\.env.example"
$FunctionEnv = Join-Path $RepoRoot "supabase\functions\.env"

if (-not (Test-Path $FunctionEnv) -and (Test-Path $FunctionEnvExample)) {
  Copy-Item $FunctionEnvExample $FunctionEnv
  Write-Host "Created ignored local Edge Function env from .env.example."
}

if (-not (Test-Path $SupabaseCli)) {
  Write-Error "Project-local Supabase CLI was not found. Run 'npm ci' from the repository root first."
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "Docker-compatible runtime was not found. Install/start Docker Desktop first."
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Error "Docker is installed but not running."
}

$CrlfSql = @(
  git ls-files --eol -- supabase |
    Where-Object { $_ -match 'w/crlf' -and $_ -match '\.sql$' }
)

if ($CrlfSql.Count -gt 0) {
  Write-Host "SQL files with CRLF were found:" -ForegroundColor Yellow
  $CrlfSql | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  Write-Error "Supabase migrations must use LF. See docs/qa-staging.md: force-refresh tracked SQL files after applying .gitattributes."
}

Write-Host "[1/4] Reloading local Supabase runtime so Edge Function env is current..."
& $SupabaseCli stop
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[2/4] Starting local Supabase..."
& $SupabaseCli start
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[3/4] Rebuilding local database from migrations + seed..."
& $SupabaseCli db reset
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[4/4] Local staging status"
& $SupabaseCli status
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Local staging is ready."
Write-Host "Next: copy env/staging.example.json to env/staging.json"
Write-Host "and replace SUPABASE_PUBLISHABLE_KEY with the local key shown above."
