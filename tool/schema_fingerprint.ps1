$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SqlFile = Join-Path $RepoRoot "supabase/tests/inspection/schema_fingerprint.sql"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker command not found. Open a new terminal after Docker Desktop is running."
}

if (-not (Test-Path $SqlFile)) {
    Write-Error "Schema fingerprint SQL not found: $SqlFile"
}

$containers = @(
    docker ps --filter "name=supabase_db_" --format "{{.Names}}"
)

$dbContainer = $containers |
    Where-Object { $_ -match "forestring" } |
    Select-Object -First 1

if (-not $dbContainer) {
    if ($containers.Count -eq 1) {
        $dbContainer = $containers[0]
    } else {
        Write-Error "Could not identify the Forestring local Supabase database container. Run .\tool\staging_start.ps1 first."
    }
}

$tempFile = "/tmp/forestring_schema_fingerprint.sql"

Write-Host "Local database container: $dbContainer"
docker cp $SqlFile "${dbContainer}:$tempFile" | Out-Null

try {
    docker exec $dbContainer psql -X -U postgres -d postgres -P pager=off -f $tempFile
} finally {
    docker exec $dbContainer rm -f $tempFile | Out-Null
}
