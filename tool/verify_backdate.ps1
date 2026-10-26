param(
    [string]$Container = "supabase_db_forestring_teacher_2"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$QaDatabase = "forestring_backdate_qa_" + [guid]::NewGuid().ToString("N")
$QaDirectory = Join-Path $RepoRoot "build/backdate_qa/$QaDatabase"
$ContainerDirectory = "/tmp/$QaDatabase"
$CreatedDatabase = $false

function Invoke-Docker {
    # Keep this a simple function: Docker flags such as -p/-v must not bind
    # to PowerShell advanced-function common parameters.
    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Local Docker QA command failed (exit $LASTEXITCODE)."
    }
}

# Reject remote Docker contexts. This script never uses a Supabase project link,
# an API key, or a remote connection string, and never resets the source DB.
$DockerEndpoint = & docker context inspect --format '{{.Endpoints.docker.Host}}'
if ($LASTEXITCODE -ne 0 -or $DockerEndpoint -notmatch '^(npipe://|unix://)') {
    throw "Select a local Docker context before running backdate QA."
}
if ($Container -notmatch '^supabase_db_[a-zA-Z0-9_-]+$') {
    throw "Expected the name of a local supabase_db_ container."
}

New-Item -ItemType Directory -Path $QaDirectory -Force | Out-Null
try {
    Invoke-Docker exec $Container mkdir -p $ContainerDirectory
    Invoke-Docker exec $Container pg_dump -U postgres -d postgres --schema-only --no-owner --schema=auth --schema=public --schema=private --schema=extensions "--file=$ContainerDirectory/schema.sql"
    $SchemaPath = Join-Path $QaDirectory "schema.sql"
    Invoke-Docker cp "${Container}:$ContainerDirectory/schema.sql" $SchemaPath
    $Schema = [System.IO.File]::ReadAllText($SchemaPath)
    $Schema = $Schema.Replace('CREATE SCHEMA extensions;', 'CREATE SCHEMA IF NOT EXISTS extensions;').Replace('CREATE SCHEMA public;', 'CREATE SCHEMA IF NOT EXISTS public;')
    # Managed Auth/admin owners cannot be altered by the local postgres role.
    # Preserve existing object ACLs and postgres defaults; skip only defaults
    # belonging to managed roles (no new Auth/admin objects are needed here).
    $Schema = [regex]::Replace($Schema, '(?m)^ALTER DEFAULT PRIVILEGES FOR ROLE (?!postgres\b)[^\r\n]*\r?\n', '')
    [System.IO.File]::WriteAllText($SchemaPath, $Schema, [System.Text.UTF8Encoding]::new($false))
    Invoke-Docker cp $SchemaPath "${Container}:$ContainerDirectory/schema.sql"

    Invoke-Docker exec $Container createdb -U postgres $QaDatabase
    $CreatedDatabase = $true
    Invoke-Docker exec $Container psql -X -U postgres -d $QaDatabase -v ON_ERROR_STOP=1 -q -c 'create schema extensions; create extension btree_gist with schema extensions; create extension pgcrypto with schema extensions; create extension "uuid-ossp" with schema extensions;'
    Invoke-Docker exec $Container psql -X -U postgres -d $QaDatabase -v ON_ERROR_STOP=1 -q -f "$ContainerDirectory/schema.sql"

    $SqlFiles = @(
        "supabase/migrations/20261026134010_support_backdated_student_withdrawal.sql",
        "supabase/migrations/20261026134021_support_backdated_makeup_lessons.sql",
        "supabase/tests/local/backdated_student_withdrawal.sql",
        "supabase/migrations/20261026231956_finalize_withdrawal_with_archived_history.sql",
        "supabase/tests/local/terminal_student_withdrawal.sql",
        "supabase/tests/local/backdated_makeup_lessons.sql"
    )
    $AlreadyTerminal = @(Invoke-Docker exec $Container psql -X -U postgres -d $QaDatabase -A -t -c "select to_regclass('private.student_withdrawal_finalization_archives') is not null;") -contains 't'
    if ($AlreadyTerminal) {
        # An up-to-date source schema must not be downgraded to the old veto
        # policy, nor have its already-applied archive tables created twice.
        $SqlFiles = @(
            "supabase/tests/local/terminal_student_withdrawal.sql",
            "supabase/tests/local/backdated_makeup_lessons.sql"
        )
    }
    foreach ($SqlFile in $SqlFiles) {
        $SourcePath = Join-Path $RepoRoot $SqlFile
        $TargetPath = "$ContainerDirectory/" + [System.IO.Path]::GetFileName($SqlFile)
        Write-Host "Checking $SqlFile"
        Invoke-Docker cp $SourcePath "${Container}:$TargetPath"
        Invoke-Docker exec $Container psql -X -U postgres -d $QaDatabase -v ON_ERROR_STOP=1 -f $TargetPath
    }
    Write-Host "PASS: backdate SQL regression. Source local DB was preserved."
} finally {
    # QaDatabase is generated above, never supplied by the caller.
    if ($CreatedDatabase -and $QaDatabase -match '^forestring_backdate_qa_[a-f0-9]{32}$') {
        & docker exec $Container dropdb -U postgres --if-exists $QaDatabase
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not remove disposable QA database $QaDatabase."
        }
    }
}
