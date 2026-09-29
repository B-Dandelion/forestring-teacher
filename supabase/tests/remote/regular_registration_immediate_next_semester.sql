-- Rollback-only QA for immediate next-semester materialization.
--
-- Run against Local/Staging Supabase AFTER migrations + seed.sql.
-- Uses only deterministic QA fixture accounts and rolls everything back.
--
-- Covers:
--   1) current-semester initial registration => current + next materialized immediately
--   2) repeated materialization => idempotent, no duplicates
--   3) future-semester initial registration => selected future semester only
--   4) next-semester warm-up failure => current registration survives + failure audit
--   5) retry after transient failure => next semester materializes successfully
--   6) private helper remains inaccessible to client roles

begin;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',
  true
);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);

-- Rewind only the seeded QA Student's scheduling state.
delete from public.lessons
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

delete from public.lesson_rights
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

delete from public.student_semester_plans
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

delete from public.lesson_series
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

delete from public.regular_schedule_slots
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

-- Simulate a student first registered on 2026-09-29.
update public.student_enrollment_periods
set starts_on=date '2026-09-29'
where student_id='44444444-4444-4444-8444-444444444444'::uuid
  and ends_on is null;

-- ============================================================
-- QA 1: current semester => current + next immediately.
-- ============================================================
do $qa_current$
declare
  v_current_semester_id uuid;
  v_next_semester_id uuid;
  v_result jsonb;
  v_replay jsonb;
  v_current_rights integer;
  v_current_lessons integer;
  v_next_rights integer;
  v_next_lessons integer;
  v_next_created_by uuid;
begin
  select s.id into v_current_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where date '2026-09-29' between e.starts_on and e.ends_on
  order by e.starts_on desc
  limit 1;

  select s.id into v_next_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where e.starts_on=(
    select e0.ends_on+1
    from private.get_effective_semester_bounds(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      v_current_semester_id
    ) e0
  )
  limit 1;

  if v_current_semester_id is null or v_next_semester_id is null then
    raise exception 'TEST_FAIL semester lookup failed';
  end if;

  v_result := public.initialize_regular_student_semester(
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    v_current_semester_id,
    '[{"weekday":2,"startTime":"18:00","durationMinutes":60}]'::jsonb
  );

  if not exists (
    select 1 from public.student_semester_plans
    where student_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_current_semester_id
      and status='active'::public.student_semester_plan_status
  ) then
    raise exception 'TEST_FAIL current plan not active';
  end if;

  select created_by into v_next_created_by
  from public.student_semester_plans
  where student_id='44444444-4444-4444-8444-444444444444'::uuid
    and semester_id=v_next_semester_id
    and status='active'::public.student_semester_plan_status;

  if not found then
    raise exception 'TEST_FAIL next plan not materialized immediately';
  end if;

  if v_next_created_by is distinct from
     '22222222-2222-4222-8222-222222222222'::uuid then
    raise exception 'TEST_FAIL next plan actor provenance missing: %',v_next_created_by;
  end if;

  select count(*)::integer into v_current_rights
  from public.lesson_rights
  where student_id='44444444-4444-4444-8444-444444444444'::uuid
    and source_semester_id=v_current_semester_id
    and origin='regular_base'::public.lesson_right_origin;

  select count(*)::integer into v_current_lessons
  from public.lessons l
  join public.lesson_rights r on r.id=l.lesson_right_id
  where l.student_id='44444444-4444-4444-8444-444444444444'::uuid
    and r.source_semester_id=v_current_semester_id;

  select count(*)::integer into v_next_rights
  from public.lesson_rights
  where student_id='44444444-4444-4444-8444-444444444444'::uuid
    and source_semester_id=v_next_semester_id
    and origin='regular_base'::public.lesson_right_origin;

  select count(*)::integer into v_next_lessons
  from public.lessons l
  join public.lesson_rights r on r.id=l.lesson_right_id
  where l.student_id='44444444-4444-4444-8444-444444444444'::uuid
    and r.source_semester_id=v_next_semester_id;

  if v_current_rights <> 1 or v_current_lessons <> 1 then
    raise exception
      'TEST_FAIL current expected 1/1 rights/lessons, got %/%',
      v_current_rights,v_current_lessons;
  end if;

  if v_next_rights <> 4 or v_next_lessons <> 4 then
    raise exception
      'TEST_FAIL next expected 4/4 rights/lessons, got %/%',
      v_next_rights,v_next_lessons;
  end if;

  v_replay := private.ensure_semester_plan_materialized(
    '44444444-4444-4444-8444-444444444444'::uuid,
    v_next_semester_id
  );

  if coalesce((v_replay->>'changed')::boolean,true) then
    raise exception 'TEST_FAIL repeated materialization changed state: %',v_replay;
  end if;

  if (select count(*) from public.lesson_rights
      where student_id='44444444-4444-4444-8444-444444444444'::uuid
        and source_semester_id=v_next_semester_id) <> 4 then
    raise exception 'TEST_FAIL replay duplicated next rights';
  end if;
end;
$qa_current$;

-- ============================================================
-- QA 2: selecting a future start semester must not create +1.
-- ============================================================
delete from public.lessons
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.lesson_rights
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.student_semester_plans
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.lesson_series
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.regular_schedule_slots
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

do $qa_future$
declare
  v_current_semester_id uuid;
  v_future_semester_id uuid;
  v_after_future_semester_id uuid;
  v_result jsonb;
begin
  select s.id into v_current_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where date '2026-09-29' between e.starts_on and e.ends_on
  limit 1;

  select s.id into v_future_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where e.starts_on=(
    select e0.ends_on+1
    from private.get_effective_semester_bounds(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      v_current_semester_id
    ) e0
  )
  limit 1;

  select s.id into v_after_future_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where e.starts_on=(
    select e0.ends_on+1
    from private.get_effective_semester_bounds(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      v_future_semester_id
    ) e0
  )
  limit 1;

  v_result := public.initialize_regular_student_semester(
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    v_future_semester_id,
    '[{"weekday":2,"startTime":"18:00","durationMinutes":60}]'::jsonb
  );

  if not exists (
    select 1 from public.student_semester_plans
    where student_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_future_semester_id
      and status='active'::public.student_semester_plan_status
  ) then
    raise exception 'TEST_FAIL selected future semester not active';
  end if;

  if v_after_future_semester_id is not null and exists (
    select 1 from public.student_semester_plans
    where student_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_after_future_semester_id
  ) then
    raise exception 'TEST_FAIL future registration incorrectly created following semester';
  end if;
end;
$qa_future$;

-- ============================================================
-- QA 3: transient next-semester failure is isolated + retry works.
-- ============================================================
delete from public.lessons
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.lesson_rights
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.student_semester_plans
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.lesson_series
where student_id='44444444-4444-4444-8444-444444444444'::uuid;
delete from public.regular_schedule_slots
where student_id='44444444-4444-4444-8444-444444444444'::uuid;

insert into public.blocked_periods(
  teacher_id,starts_at,ends_at,reason,created_by
) values (
  '33333333-3333-4333-8333-333333333333'::uuid,
  timestamptz '2026-10-06 18:00:00+09',
  timestamptz '2026-10-06 19:00:00+09',
  'ROLLBACK_QA_NEXT_SEMESTER_FAILURE',
  '22222222-2222-4222-8222-222222222222'::uuid
);

do $qa_failure$
declare
  v_current_semester_id uuid;
  v_next_semester_id uuid;
  v_result jsonb;
begin
  select s.id into v_current_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where date '2026-09-29' between e.starts_on and e.ends_on
  limit 1;

  select s.id into v_next_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where e.starts_on=(
    select e0.ends_on+1
    from private.get_effective_semester_bounds(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      v_current_semester_id
    ) e0
  )
  limit 1;

  v_result := public.initialize_regular_student_semester(
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    v_current_semester_id,
    '[{"weekday":2,"startTime":"18:00","durationMinutes":60}]'::jsonb
  );

  if not exists (
    select 1 from public.student_semester_plans
    where student_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_current_semester_id
      and status='active'::public.student_semester_plan_status
  ) then
    raise exception 'TEST_FAIL current registration rolled back with future failure';
  end if;

  if exists (
    select 1 from public.student_semester_plans
    where student_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_next_semester_id
  ) then
    raise exception 'TEST_FAIL failed future subtransaction left a plan';
  end if;

  if not exists (
    select 1 from public.audit_events
    where subject_profile_id='44444444-4444-4444-8444-444444444444'::uuid
      and semester_id=v_next_semester_id
      and event_type='STUDENT_NEXT_SEMESTER_AUTO_FAILED'
      and actor_id='22222222-2222-4222-8222-222222222222'::uuid
      and details->>'executionSource'='staff_registration'
  ) then
    raise exception 'TEST_FAIL failure audit missing';
  end if;
end;
$qa_failure$;

delete from public.blocked_periods
where reason='ROLLBACK_QA_NEXT_SEMESTER_FAILURE'
  and teacher_id='33333333-3333-4333-8333-333333333333'::uuid;

do $qa_retry$
declare
  v_current_semester_id uuid;
  v_next_semester_id uuid;
  v_result jsonb;
begin
  select s.id into v_current_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where date '2026-09-29' between e.starts_on and e.ends_on
  limit 1;

  select s.id into v_next_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where e.starts_on=(
    select e0.ends_on+1
    from private.get_effective_semester_bounds(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
      v_current_semester_id
    ) e0
  )
  limit 1;

  v_result := private.ensure_semester_plan_materialized(
    '44444444-4444-4444-8444-444444444444'::uuid,
    v_next_semester_id
  );

  if not coalesce((v_result->>'changed')::boolean,false) then
    raise exception 'TEST_FAIL retry did not materialize next semester: %',v_result;
  end if;

  if (select count(*) from public.lesson_rights
      where student_id='44444444-4444-4444-8444-444444444444'::uuid
        and source_semester_id=v_next_semester_id) <> 4 then
    raise exception 'TEST_FAIL retry expected four next-semester rights';
  end if;
end;
$qa_retry$;

-- ============================================================
-- QA 4: private helper still cannot be called directly by app roles.
-- ============================================================
do $qa_acl$
begin
  if has_function_privilege(
       'authenticated',
       'private.ensure_semester_plan_materialized(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'TEST_FAIL authenticated can execute private materializer';
  end if;

  if has_function_privilege(
       'anon',
       'private.ensure_semester_plan_materialized(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'TEST_FAIL anon can execute private materializer';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.initialize_regular_student_semester(uuid,uuid,uuid,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'TEST_FAIL authenticated lost initializer access';
  end if;
end;
$qa_acl$;

rollback;
