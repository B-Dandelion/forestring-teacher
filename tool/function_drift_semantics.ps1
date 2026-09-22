$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SqlFile = Join-Path $RepoRoot "supabase/tests/inspection/function_metadata.sql"
$BaselineFile = Join-Path $RepoRoot "supabase/tests/inspection/production_function_metadata.tsv"

$containers = @(docker ps --filter "name=supabase_db_" --format "{{.Names}}")
$dbContainer = $containers | Where-Object { $_ -match "forestring" } | Select-Object -First 1
if (-not $dbContainer) {
    if ($containers.Count -eq 1) { $dbContainer = $containers[0] }
    else { Write-Error "Could not identify the Forestring local Supabase database container." }
}

$tempSql = "/tmp/forestring_function_metadata.sql"
$tempOut = "/tmp/forestring_function_metadata.tsv"

docker cp $SqlFile "${dbContainer}:$tempSql" | Out-Null
try {
    docker exec $dbContainer sh -lc "psql -X -U postgres -d postgres -A -F '	' -t -f $tempSql > $tempOut"
    $localLines = @(docker exec $dbContainer cat $tempOut)
} finally {
    docker exec $dbContainer rm -f $tempSql $tempOut | Out-Null
}

$prodLines = Get-Content $BaselineFile | Where-Object { $_ -and -not $_.StartsWith("#") }

function Parse-Line([string]$line) {
    $p = $line -split "	", 11
    [pscustomobject]@{
        Schema = $p[0]; Name = $p[1]; Args = $p[2]; Body = $p[3]
        SecurityDefiner = $p[4]; Volatility = $p[5]; Leakproof = $p[6]
        Parallel = $p[7]; Proconfig = $p[8]; Language = $p[9]; Result = $p[10]
        Key = "$($p[0])|$($p[1])|$($p[2])"
    }
}

$prod = @{}
foreach ($line in $prodLines) { $r = Parse-Line $line; $prod[$r.Key] = $r }
$local = @{}
foreach ($line in $localLines) { if ($line) { $r = Parse-Line $line; $local[$r.Key] = $r } }

$shared = @($prod.Keys | Where-Object { $local.ContainsKey($_) })
$bodyDiff = @($shared | Where-Object { $prod[$_].Body -ne $local[$_].Body } | Sort-Object)
$configOnly = @(
    $shared | Where-Object {
        $prod[$_].Body -eq $local[$_].Body -and (
            $prod[$_].SecurityDefiner -ne $local[$_].SecurityDefiner -or
            $prod[$_].Volatility -ne $local[$_].Volatility -or
            $prod[$_].Leakproof -ne $local[$_].Leakproof -or
            $prod[$_].Parallel -ne $local[$_].Parallel -or
            $prod[$_].Proconfig -ne $local[$_].Proconfig -or
            $prod[$_].Language -ne $local[$_].Language -or
            $prod[$_].Result -ne $local[$_].Result
        )
    } | Sort-Object
)

Write-Host ""
Write-Host "Function semantic drift classification"
Write-Host "  Body differences          : $($bodyDiff.Count)"
Write-Host "  Metadata/config-only diff : $($configOnly.Count)"

if ($bodyDiff.Count -gt 0) {
    Write-Host ""
    Write-Host "[Body differences]"
    $bodyDiff | ForEach-Object { Write-Host "  $_" }
}

if ($configOnly.Count -gt 0) {
    Write-Host ""
    Write-Host "[Metadata/config-only differences]"
    foreach ($key in $configOnly) {
        Write-Host "  $key"
        if ($prod[$key].SecurityDefiner -ne $local[$key].SecurityDefiner) {
            Write-Host "    security_definer: prod=$($prod[$key].SecurityDefiner) local=$($local[$key].SecurityDefiner)"
        }
        if ($prod[$key].Volatility -ne $local[$key].Volatility) {
            Write-Host "    volatility: prod=$($prod[$key].Volatility) local=$($local[$key].Volatility)"
        }
        if ($prod[$key].Leakproof -ne $local[$key].Leakproof) {
            Write-Host "    leakproof: prod=$($prod[$key].Leakproof) local=$($local[$key].Leakproof)"
        }
        if ($prod[$key].Parallel -ne $local[$key].Parallel) {
            Write-Host "    parallel: prod=$($prod[$key].Parallel) local=$($local[$key].Parallel)"
        }
        if ($prod[$key].Proconfig -ne $local[$key].Proconfig) {
            Write-Host "    proconfig: prod='$($prod[$key].Proconfig)' local='$($local[$key].Proconfig)'"
        }
        if ($prod[$key].Language -ne $local[$key].Language) {
            Write-Host "    language: prod=$($prod[$key].Language) local=$($local[$key].Language)"
        }
        if ($prod[$key].Result -ne $local[$key].Result) {
            Write-Host "    result: prod='$($prod[$key].Result)' local='$($local[$key].Result)'"
        }
    }
}
