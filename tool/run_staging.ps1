$ErrorActionPreference = "Stop"

$EnvFile = "env/staging.json"

if (-not (Test-Path $EnvFile)) {
  Write-Error "$EnvFile not found. Copy env/staging.example.json to $EnvFile and fill the local Supabase key."
}

$content = Get-Content $EnvFile -Raw
$localPattern = '"SUPABASE_URL"\s*:\s*"http://(127\.0\.0\.1|localhost|10\.0\.2\.2):54321"'

if ($content -notmatch $localPattern) {
  Write-Error "staging.json does not point to the expected local Supabase API. Refusing to run to reduce the risk of accidentally testing against Production."
}

flutter run --dart-define-from-file=$EnvFile @args
