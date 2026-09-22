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

function Normalize-Bool([string]$value) {
    switch ($value.ToLowerInvariant()) {
        "t" { return "true" }
        "true" { return "true" }
        "f" { return "false" }
        "false" { return "false" }
        default { return $value.ToLowerInvariant() }
    }
}

function Parse-Line([string]$line) {
    $p = $line -split "	", 12
    [pscustomobject]@{
        Schema = $p[0]
        Name = $p[1]
        Args = $p[2]
        RawBody = $p[3]
        NormalizedBody = $p[4]
        SecurityDefiner = Normalize-Bool $p[5]
        Volatility = $p[6]
        Leakproof = Normalize-Bool $p[7]
        Parallel = $p[8]
        Proconfig = $p[9]
        Language = $p[10]
        Result = $p[11]
        Key = "$($p[0])|$($p[1])|$($p[2])"
    }
}

$prod = @{}
foreach ($line in $prodLines) { $r = Parse-Line $line; $prod[$r.Key] = $r }
$local = @{}
foreach ($line in $localLines) { if ($line) { $r = Parse-Line $line; $local[$r.Key] = $r } }

$shared = @($prod.Keys | Where-Object { $local.ContainsKey($_) })
$rawBodyDiff = @($shared | Where-Object { $prod[$_].RawBody -ne $local[$_].RawBody } | Sort-Object)
$normalizedBodyDiff = @($shared | Where-Object { $prod[$_].NormalizedBody -ne $local[$_].NormalizedBody } | Sort-Object)
$formatCommentOnly = @(
    $shared | Where-Object {
        $prod[$_].RawBody -ne $local[$_].RawBody -and
        $prod[$_].NormalizedBody -eq $local[$_].NormalizedBody
    } | Sort-Object
)
$configDiff = @(
    $shared | Where-Object {
        $prod[$_].SecurityDefiner -ne $local[$_].SecurityDefiner -or
        $prod[$_].Volatility -ne $local[$_].Volatility -or
        $prod[$_].Leakproof -ne $local[$_].Leakproof -or
        $prod[$_].Parallel -ne $local[$_].Parallel -or
        $prod[$_].Proconfig -ne $local[$_].Proconfig -or
        $prod[$_].Language -ne $local[$_].Language -or
        $prod[$_].Result -ne $local[$_].Result
    } | Sort-Object
)

Write-Host ""
Write-Host "Function drift classification"
Write-Host "  Raw body differences             : $($rawBodyDiff.Count)"
Write-Host "  Comment/format-only candidates   : $($formatCommentOnly.Count)"
Write-Host "  Normalized body differences      : $($normalizedBodyDiff.Count)"
Write-Host "  Actual metadata/config diff      : $($configDiff.Count)"

if ($formatCommentOnly.Count -gt 0) {
    Write-Host ""
    Write-Host "[Comment/format-only candidates]"
    $formatCommentOnly | ForEach-Object { Write-Host "  $_" }
}

if ($normalizedBodyDiff.Count -gt 0) {
    Write-Host ""
    Write-Host "[Normalized body differences - inspect further]"
    $normalizedBodyDiff | ForEach-Object { Write-Host "  $_" }
}

if ($configDiff.Count -gt 0) {
    Write-Host ""
    Write-Host "[Actual metadata/config differences]"
    foreach ($key in $configDiff) {
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
