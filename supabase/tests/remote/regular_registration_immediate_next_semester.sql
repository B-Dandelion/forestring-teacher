-- Rollback-only QA for immediate next-semester materialization.
--
-- Run against Local/Staging Supabase AFTER migrations + seed.sql.
-- Nothing in this file should persist.
--
-- Expectations:
--   1) current semester materializes immediately
--   2) consecutive next semester also materializes in the same registration call
--   3) next semester contains exactly four regular rights/lessons for the single slot
--   4) running the normal materializer again is idempotent
--   5) rollback leaves the seeded fixture unchanged

begin;

-- Deterministic synthetic test student. This UUID exists only inside this transaction.
-- Local seed supplies the manager/teacher/branch/Auth identities.
insert into auth.users (
  instance_id,id,aud,role,email,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  email_change_token_current,email_change_confirm_status,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous
)
select
  coalesce(
    (select i.id from auth.instances i order by i.created_at limit 1),
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  '49494949-4949-4949-8949-494949494949'::uuid,
  'authenticated','authenticated',
  'qa-immediate-next-semester@auth.forestring.invalid',
  pg_catalog.now(),'','','','','',0,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),pg_catalog.now(),false,false;

insert into public.profiles (
  id,display_name,role,branch_id,is_active,is_review_account
) values (
  '49494949-4949-4949-8949-494949494949'::uuid,
  'QA Immediate Next Semester',
  'student'::public.user_role,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  true,
  false
);

insert into public.students (
  id,status,withdrawal_date,student_type
) values (
  '49494949-4949-4949-8949-494949494949'::uuid,
  'active'::public.student_status,
  null,
  'regular'::public.student_type
);

-- Force the registration date into the current QA semester.
update public.student_enrollment_periods
set starts_on=date '2026-09-29'
where student_id='49494949-4949-4949-8949-494949494949'::uuid
  and ends_on is null;

set local role authenticated;
select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',
  true
);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',true);

do $qa$
declare
  v_current_semester_id uuid;
  v_next_semester_id uuid;
  v_result jsonb;
  v_current_plan_id uuid;
  v_next_plan_id uuid;
  v_current_rights integer;
  v_current_lessons integer;
  v_next_rights integer;
  v_next_lessons integer;
begin
  select s.id
    into v_current_semester_id
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id
  ) e
  where date '2026-09-29' between e.starts_on and e.ends_on
  order by e.starts_on desc
  limit 1;

  if v_current_semester_id is null then
    raise exception 'TEST_FAIL current semester not found';
  end if;

  select s2.id
    into v_next_semester_id
  from public.semesters s1
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s1.id
  ) e1
  join public.semesters s2 on true
  cross join lateral private.get_effective_semester_bounds(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s2.id
  ) e2
  where s1.id=v_current_semester_id
    and e2.starts_on=e1.ends_on+1
  order by e2.starts_on
  limit 1;

  if v_next_semester_id is null then
    raise exception 'TEST_FAIL next semester not found';
  end if;

  v_result := public.initialize_regular_student_semester(
    '49494949-4949-4949-8949-494949494949'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    v_current_semester_id,
    '[{"weekday":2,"startTime":"14:00","durationMinutes":30}]'::jsonb
  );

  select id into v_current_plan_id
  from public.student_semester_plans
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and semester_id=v_current_semester_id;

  select id into v_next_plan_id
  from public.student_semester_plans
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and semester_id=v_next_semester_id;

  if v_current_plan_id is null then
    raise exception 'TEST_FAIL current plan not created';
  end if;

  if v_next_plan_id is null then
    raise exception 'TEST_FAIL next plan not created immediately';
  end if;

  if (select status from public.student_semester_plans where id=v_current_plan_id)
     <> 'active'::public.student_semester_plan_status then
    raise exception 'TEST_FAIL current plan not active';
  end if;

  if (select status from public.student_semester_plans where id=v_next_plan_id)
     <> 'active'::public.student_semester_plan_status then
    raise exception 'TEST_FAIL next plan not active';
  end if;

  select count(*)::integer into v_current_rights
  from public.lesson_rights
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and source_semester_id=v_current_semester_id
    and origin='regular_base'::public.lesson_right_origin;

  select count(*)::integer into v_current_lessons
  from public.lessons
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and lesson_type='regular'::public.lesson_type
    and lesson_right_id in (
      select id from public.lesson_rights
      where student_id='49494949-4949-4949-8949-494949494949'::uuid
        and source_semester_id=v_current_semester_id
    );

  select count(*)::integer into v_next_rights
  from public.lesson_rights
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and source_semester_id=v_next_semester_id
    and origin='regular_base'::public.lesson_right_origin;

  select count(*)::integer into v_next_lessons
  from public.lessons
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and lesson_type='regular'::public.lesson_type
    and lesson_right_id in (
      select id from public.lesson_rights
      where student_id='49494949-4949-4949-8949-494949494949'::uuid
        and source_semester_id=v_next_semester_id
    );

  -- 2026-09-29 is the last Tuesday occurrence in the current QA semester.
  if v_current_rights <> 1 or v_current_lessons <> 1 then
    raise exception
      'TEST_FAIL current semester expected 1 right/lesson, got rights=% lessons=%',
      v_current_rights,v_current_lessons;
  end if;

  if v_next_rights <> 4 or v_next_lessons <> 4 then
    raise exception
      'TEST_FAIL next semester expected 4 rights/lessons, got rights=% lessons=%',
      v_next_rights,v_next_lessons;
  end if;
end;
$qa$;

-- The private helper is intentionally not executable by authenticated clients.
reset role;

do $qa_idempotency$
declare
  v_next_semester_id uuid;
  v_result jsonb;
  v_before_rights integer;
  v_before_lessons integer;
  v_after_rights integer;
  v_after_lessons integer;
begin
  select sp.semester_id into v_next_semester_id
  from public.student_semester_plans sp
  join public.semesters s on s.id=sp.semester_id
  where sp.student_id='49494949-4949-4949-8949-494949494949'::uuid
  order by s.starts_on desc
  limit 1;

  select count(*)::integer into v_before_rights
  from public.lesson_rights
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and source_semester_id=v_next_semester_id;

  select count(*)::integer into v_before_lessons
  from public.lessons
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and lesson_right_id in (
      select id from public.lesson_rights
      where student_id='49494949-4949-4949-8949-494949494949'::uuid
        and source_semester_id=v_next_semester_id
    );

  -- Simulate a subsequent nightly-cron retry.
  perform pg_catalog.set_config('request.jwt.claim.sub','',true);
  perform pg_catalog.set_config('request.jwt.claim.role','',true);
  perform pg_catalog.set_config('forestring.system_semester_transition','cron',true);
  perform pg_catalog.set_config('forestring.system_semester_run_date','2026-09-29',true);

  v_result := private.ensure_semester_plan_materialized(
    '49494949-4949-4949-8949-494949494949'::uuid,
    v_next_semester_id
  );

  if coalesce((v_result->>'changed')::boolean,true) then
    raise exception 'TEST_FAIL repeated materialization should be unchanged: %',v_result;
  end if;

  select count(*)::integer into v_after_rights
  from public.lesson_rights
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and source_semester_id=v_next_semester_id;

  select count(*)::integer into v_after_lessons
  from public.lessons
  where student_id='49494949-4949-4949-8949-494949494949'::uuid
    and lesson_right_id in (
      select id from public.lesson_rights
      where student_id='49494949-4949-4949-8949-494949494949'::uuid
        and source_semester_id=v_next_semester_id
    );

  if v_after_rights <> v_before_rights or v_after_lessons <> v_before_lessons then
    raise exception
      'TEST_FAIL idempotency counts changed: rights %->%, lessons %->%',
      v_before_rights,v_after_rights,v_before_lessons,v_after_lessons;
  end if;
end;
$qa_idempotency$;

-- Security boundary: no client-role direct EXECUTE on the private helper.
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
end;
$qa_acl$;

rollback;
