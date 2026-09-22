$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$containers = @(docker ps --filter "name=supabase_db_" --format "{{.Names}}")
$dbContainer = $containers | Where-Object { $_ -match "forestring" } | Select-Object -First 1
if (-not $dbContainer) {
  if ($containers.Count -eq 1) { $dbContainer = $containers[0] }
  else { Write-Error "Could not identify the Forestring local Supabase database container." }
}

$sql = @'
\set ON_ERROR_STOP on

create temporary table qa_rls_results (
  actor text,
  self_profile_count integer,
  visible_branch_count integer,
  branch_b_visible integer,
  visible_lesson_count integer
);

-- Helper pattern: each transaction sets the same JWT context PostgREST would expose.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
insert into qa_rls_results
select
  'QA Master',
  (select count(*) from public.profiles where id=auth.uid()),
  (select count(*) from public.branches),
  (select count(*) from public.branches where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid),
  (select count(*) from public.lessons where id like '99999999-%');
reset role;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}', true);
insert into qa_rls_results
select
  'QA Manager',
  (select count(*) from public.profiles where id=auth.uid()),
  (select count(*) from public.branches),
  (select count(*) from public.branches where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid),
  (select count(*) from public.lessons where id like '99999999-%');
reset role;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}', true);
insert into qa_rls_results
select
  'QA Teacher',
  (select count(*) from public.profiles where id=auth.uid()),
  (select count(*) from public.branches),
  (select count(*) from public.branches where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid),
  (select count(*) from public.lessons where id like '99999999-%');
reset role;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-8444-444444444444","role":"authenticated"}', true);
insert into qa_rls_results
select
  'QA Student',
  (select count(*) from public.profiles where id=auth.uid()),
  (select count(*) from public.branches),
  (select count(*) from public.branches where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid),
  (select count(*) from public.lessons where id like '99999999-%');
reset role;
commit;

select * from qa_rls_results order by actor;

do $qa_rls_assert$
declare
  r record;
begin
  for r in select * from qa_rls_results loop
    if r.self_profile_count <> 1 then
      raise exception 'QA_RLS_SELF_PROFILE_FAILED: %', r.actor;
    end if;

    if r.visible_lesson_count <> 4 then
      raise exception 'QA_RLS_LESSON_VISIBILITY_FAILED: % saw %', r.actor, r.visible_lesson_count;
    end if;

    if r.actor = 'QA Master' then
      if r.visible_branch_count <> 2 or r.branch_b_visible <> 1 then
        raise exception 'QA_RLS_MASTER_BRANCH_SCOPE_FAILED';
      end if;
    else
      if r.visible_branch_count <> 1 or r.branch_b_visible <> 0 then
        raise exception 'QA_RLS_BRANCH_DENY_FAILED: %', r.actor;
      end if;
    end if;
  end loop;
end;
$qa_rls_assert$;

select 'QA RLS smoke: PASS' as result;
'@

$tempSql = "/tmp/forestring_verify_qa_rls.sql"
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
