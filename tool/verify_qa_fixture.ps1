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
select
  'assignment' as fixture,
  count(*)::text as value
from public.teacher_student_assignments
where teacher_id='33333333-3333-4333-8333-333333333333'::uuid
  and student_id='44444444-4444-4444-8444-444444444444'::uuid

union all

select
  'teacher_work_hour_segments',
  count(*)::text
from private.teacher_work_hour_entries
where version_id='cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid

union all

select
  'semester_plans_current_next',
  count(*)::text
from public.student_semester_plans
where student_id='44444444-4444-4444-8444-444444444444'::uuid
  and semester_id in (
    select id from public.semesters where code in ('2026-09','2026-10')
  )

union all

select
  'instructional_break_2026_09',
  count(*)::text
from public.closure_periods
where branch_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid
  and semester_id=(select id from public.semesters where code='2026-09')
  and starts_on=date '2026-09-21'
  and ends_on=date '2026-09-27'
  and closure_kind='instructional_break'::public.closure_kind

union all

select
  'regular_schedule_slot',
  count(*)::text
from public.regular_schedule_slots
where id='66666666-6666-4666-8666-666666666661'::uuid

union all

select
  'regular_series',
  count(*)::text
from public.lesson_series
where id='77777777-7777-4777-8777-777777777771'::uuid

union all

select
  'current_regular_rights',
  count(*)::text
from public.lesson_rights
where student_id='44444444-4444-4444-8444-444444444444'::uuid
  and source_semester_id=(select id from public.semesters where code='2026-09')
  and origin='regular_base'::public.lesson_right_origin

union all

select
  'e2e_reserved_right_status',
  status::text
from public.lesson_rights
where id='88888888-8888-4888-8888-888888888884'::uuid

union all

select
  'e2e_start_lesson',
  to_char(starts_at at time zone 'Asia/Seoul','YYYY-MM-DD HH24:MI') || ' / ' || status::text
from public.lessons
where id='99999999-9999-4999-8999-999999999994'::uuid

union all

select
  'active_forestring_cron_jobs',
  count(*)::text
from cron.job
where jobname like 'forestring-%'
  and active=true
order by fixture;
'@

$tempSql = "/tmp/forestring_verify_qa_fixture.sql"
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
