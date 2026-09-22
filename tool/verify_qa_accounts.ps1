$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Error "docker command not found."
}

$containers = @(docker ps --filter "name=supabase_db_" --format "{{.Names}}")
$dbContainer = $containers | Where-Object { $_ -match "forestring" } | Select-Object -First 1
if (-not $dbContainer) {
  if ($containers.Count -eq 1) { $dbContainer = $containers[0] }
  else { Write-Error "Could not identify the Forestring local Supabase database container." }
}

$sql = @'
select
  p.display_name,
  p.role,
  b.name as branch_name,
  p.is_active,
  p.is_review_account,
  (u.id is not null) as has_auth_user,
  (i.user_id is not null) as has_email_identity,
  (c.profile_id is not null) as has_pin_credential,
  (s.id is not null) as has_student_entity,
  (t.id is not null) as has_teacher_entity
from public.profiles p
left join public.branches b on b.id = p.branch_id
left join auth.users u on u.id = p.id
left join auth.identities i
  on i.user_id = p.id
 and i.provider = 'email'
left join private.login_credentials c on c.profile_id = p.id
left join public.students s on s.id = p.id
left join public.teachers t on t.id = p.id
where p.id in (
  '11111111-1111-4111-8111-111111111111'::uuid,
  '22222222-2222-4222-8222-222222222222'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid
)
order by case p.role
  when 'master' then 1
  when 'manager' then 2
  when 'teacher' then 3
  when 'student' then 4
end;
'@

$tempSql = "/tmp/forestring_verify_qa_accounts.sql"
$tempLocal = [System.IO.Path]::GetTempFileName()

try {
  Set-Content -Path $tempLocal -Value $sql -NoNewline
  docker cp $tempLocal "${dbContainer}:$tempSql" | Out-Null
  docker exec $dbContainer psql -X -U postgres -d postgres -P pager=off -f $tempSql
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Remove-Item $tempLocal -Force -ErrorAction SilentlyContinue
  docker exec $dbContainer rm -f $tempSql 2>$null | Out-Null
}
