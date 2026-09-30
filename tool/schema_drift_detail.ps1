$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SqlFile = Join-Path $RepoRoot "supabase/tests/inspection/schema_object_detail.sql"
$BaselineFile = Join-Path $RepoRoot "supabase/tests/inspection/production_schema_objects.tsv"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker command not found. Open a new terminal after Docker Desktop is running."
}

$containers = @(docker ps --filter "name=supabase_db_" --format "{{.Names}}")
$dbContainer = $containers | Where-Object { $_ -match "forestring" } | Select-Object -First 1
if (-not $dbContainer) {
    if ($containers.Count -eq 1) {
        $dbContainer = $containers[0]
    } else {
        Write-Error "Could not identify the Forestring local Supabase database container."
    }
}

$tempSql = "/tmp/forestring_schema_object_detail.sql"
$tempOut = "/tmp/forestring_schema_object_detail.tsv"

docker cp $SqlFile "${dbContainer}:$tempSql" | Out-Null
try {
    docker exec $dbContainer sh -lc "psql -X -U postgres -d postgres -A -F '	' -t -f $tempSql > $tempOut"
    $localLines = @(docker exec $dbContainer cat $tempOut) | Where-Object { $_ -and -not $_.StartsWith("#") }
} finally {
    docker exec $dbContainer rm -f $tempSql $tempOut | Out-Null
}

$prodLines = Get-Content $BaselineFile | Where-Object { $_ -and -not $_.StartsWith("#") }

function Parse-Line([string]$line) {
    $parts = $line -split "	", 5
    [pscustomobject]@{
        Kind = $parts[0]
        Schema = $parts[1]
        Object = $parts[2]
        Args = $parts[3]
        Hash = $parts[4]
        Key = "$($parts[0])|$($parts[1])|$($parts[2])|$($parts[3])"
    }
}

$prod = @{}
foreach ($line in $prodLines) {
    $row = Parse-Line $line
    $prod[$row.Key] = $row
}

$local = @{}
foreach ($line in $localLines) {
    $row = Parse-Line $line
    $local[$row.Key] = $row
}

$missing = @($prod.Keys | Where-Object { -not $local.ContainsKey($_) } | Sort-Object)
$extra = @($local.Keys | Where-Object { -not $prod.ContainsKey($_) } | Sort-Object)
$changed = @($prod.Keys | Where-Object { $local.ContainsKey($_) -and $prod[$_].Hash -ne $local[$_].Hash } | Sort-Object)

Write-Host ""
Write-Host "Production vs Local schema object drift"
Write-Host "  Missing locally : $($missing.Count)"
Write-Host "  Extra locally   : $($extra.Count)"
Write-Host "  Definition diff : $($changed.Count)"

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "[Missing locally]"
    $missing | ForEach-Object { Write-Host "  $_" }
}
if ($extra.Count -gt 0) {
    Write-Host ""
    Write-Host "[Extra locally]"
    $extra | ForEach-Object { Write-Host "  $_" }
}
if ($changed.Count -gt 0) {
    Write-Host ""
    Write-Host "[Different definition hash]"
    $changed | ForEach-Object {
        Write-Host "  $_"
        Write-Host "    Production: $($prod[$_].Hash)"
        Write-Host "    Local     : $($local[$_].Hash)"
    }
}
if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $changed.Count -eq 0) {
    Write-Host ""
    Write-Host "No function/trigger drift detected."
}
