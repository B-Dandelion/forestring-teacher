-- Forestring Local QA deterministic seed
--
-- Synthetic only. Never place Production-derived people, credentials, phone numbers,
-- or identifiers in this file.
--
-- Local QA visible login credentials:
--   QA Master  / 1111
--   QA Manager / 2222
--   QA Teacher / 3333
--   QA Student / 4444
--
-- These credentials are valid only against Local Supabase. The matching local-only
-- PIN_PEPPER is defined in supabase/functions/.env.example and copied to the ignored
-- supabase/functions/.env by the staging bootstrap scripts.
--
-- Review-account behavior is intentionally NOT used here:
-- all four profiles have is_review_account = false.

-- ============================================================
-- FIXED QA IDS
-- ============================================================
-- Branch A: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1
-- Branch B: aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2
--
-- Master : 11111111-1111-4111-8111-111111111111
-- Manager: 22222222-2222-4222-8222-222222222222
-- Teacher: 33333333-3333-4333-8333-333333333333
-- Student: 44444444-4444-4444-8444-444444444444

insert into public.branches (
  id,
  name,
  is_active,
  created_at,
  updated_at
)
values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    'QA Branch A',
    true,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  ),
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid,
    'QA Branch B',
    true,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  );

-- ============================================================
-- SUPABASE AUTH IDENTITIES
--
-- These are synthetic hidden identities used by the real local Auth service.
-- The Forestring app still signs in through name + 4-digit PIN via login-with-pin.
-- ============================================================

with qa_users (
  id,
  email
) as (
  values
    (
      '11111111-1111-4111-8111-111111111111'::uuid,
      'qa-master@auth.forestring.invalid'::text
    ),
    (
      '22222222-2222-4222-8222-222222222222'::uuid,
      'qa-manager@auth.forestring.invalid'::text
    ),
    (
      '33333333-3333-4333-8333-333333333333'::uuid,
      'qa-teacher@auth.forestring.invalid'::text
    ),
    (
      '44444444-4444-4444-8444-444444444444'::uuid,
      'qa-student@auth.forestring.invalid'::text
    )
)
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  confirmation_token,
  recovery_token,
  email_change_token_new,
  email_change,
  email_change_token_current,
  email_change_confirm_status,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_sso_user,
  is_anonymous
)
select
  coalesce(
    (select i.id from auth.instances i order by i.created_at limit 1),
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  q.id,
  'authenticated',
  'authenticated',
  q.email,
  null,
  '2026-09-22 00:00:00+00'::timestamptz,
  '',
  '',
  '',
  '',
  '',
  0,
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz,
  false,
  false
from qa_users q;

with qa_users (
  id,
  email
) as (
  values
    (
      '11111111-1111-4111-8111-111111111111'::uuid,
      'qa-master@auth.forestring.invalid'::text
    ),
    (
      '22222222-2222-4222-8222-222222222222'::uuid,
      'qa-manager@auth.forestring.invalid'::text
    ),
    (
      '33333333-3333-4333-8333-333333333333'::uuid,
      'qa-teacher@auth.forestring.invalid'::text
    ),
    (
      '44444444-4444-4444-8444-444444444444'::uuid,
      'qa-student@auth.forestring.invalid'::text
    )
)
insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  q.id,
  q.id::text,
  q.id,
  jsonb_build_object(
    'sub', q.id::text,
    'email', q.email,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  null,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from qa_users q;

-- ============================================================
-- FORESTRING PROFILES / ROLE ENTITIES
-- ============================================================

insert into public.profiles (
  id,
  display_name,
  role,
  branch_id,
  is_active,
  is_review_account,
  created_at,
  updated_at
)
values
  (
    '11111111-1111-4111-8111-111111111111'::uuid,
    'QA Master',
    'master'::public.user_role,
    null,
    true,
    false,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  ),
  (
    '22222222-2222-4222-8222-222222222222'::uuid,
    'QA Manager',
    'manager'::public.user_role,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    true,
    false,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  ),
  (
    '33333333-3333-4333-8333-333333333333'::uuid,
    'QA Teacher',
    'teacher'::public.user_role,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    true,
    false,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  ),
  (
    '44444444-4444-4444-8444-444444444444'::uuid,
    'QA Student',
    'student'::public.user_role,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    true,
    false,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  );

insert into public.teachers (
  id,
  created_at,
  updated_at
)
values
  (
    '22222222-2222-4222-8222-222222222222'::uuid,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  ),
  (
    '33333333-3333-4333-8333-333333333333'::uuid,
    '2026-09-22 00:00:00+00'::timestamptz,
    '2026-09-22 00:00:00+00'::timestamptz
  );

insert into public.students (
  id,
  status,
  withdrawal_date,
  student_type,
  created_at,
  updated_at
)
values (
  '44444444-4444-4444-8444-444444444444'::uuid,
  'active'::public.student_status,
  null,
  'regular'::public.student_type,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
);

-- ============================================================
-- FORESTRING NAME + PIN CREDENTIALS
--
-- bcryptjs in login-with-pin verifies these hashes. PostgreSQL pgcrypto creates
-- bcrypt-compatible Blowfish hashes. Fingerprints use the same local-only QA
-- pepper as the Edge Function.
-- ============================================================

with qa_credentials (
  profile_id,
  login_name,
  pin
) as (
  values
    (
      '11111111-1111-4111-8111-111111111111'::uuid,
      'QA Master'::text,
      '1111'::text
    ),
    (
      '22222222-2222-4222-8222-222222222222'::uuid,
      'QA Manager'::text,
      '2222'::text
    ),
    (
      '33333333-3333-4333-8333-333333333333'::uuid,
      'QA Teacher'::text,
      '3333'::text
    ),
    (
      '44444444-4444-4444-8444-444444444444'::uuid,
      'QA Student'::text,
      '4444'::text
    )
),
qa_settings as (
  select 'forestring-local-qa-pin-pepper-v1'::text as pin_pepper
)
insert into private.login_credentials (
  profile_id,
  login_name_normalized,
  pin_hash,
  pin_fingerprint,
  created_at,
  updated_at
)
select
  c.profile_id,
  c.login_name,
  extensions.crypt(
    c.pin || ':' || s.pin_pepper,
    extensions.gen_salt('bf', 12)
  ),
  encode(
    extensions.hmac(
      c.pin,
      s.pin_pepper,
      'sha256'
    ),
    'hex'
  ),
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from qa_credentials c
cross join qa_settings s;


-- ============================================================
-- QA CALENDAR DEFAULT CLOSURE
--
-- The 2026 academy-calendar migration originally promoted branch closure rows into
-- default_closure_periods using the branches that existed at migration time.
-- A clean Local database has no business branches until this seed runs, so that
-- data-dependent promotion intentionally produces no default rows.
--
-- Recreate the representative September instructional break as synthetic QA
-- configuration. This is fixture data, not a schema migration and not Production data.
-- ============================================================

insert into public.default_closure_periods (
  id,
  semester_id,
  starts_on,
  ends_on,
  reason,
  closure_kind,
  created_by,
  created_at,
  updated_at
)
select
  'abababab-abab-4bab-8bab-ababababab01'::uuid,
  s.id,
  date '2026-09-21',
  date '2026-09-27',
  'QA September instructional break',
  'instructional_break'::public.closure_kind,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from public.semesters s
where s.code = '2026-09';

insert into public.closure_periods (
  id,
  semester_id,
  branch_id,
  starts_on,
  ends_on,
  reason,
  created_by,
  closure_kind,
  default_closure_id,
  created_at,
  updated_at
)
select
  case b.id
    when 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid
      then 'acacacac-acac-4cac-8cac-acacacacac01'::uuid
    when 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid
      then 'acacacac-acac-4cac-8cac-acacacacac02'::uuid
  end,
  s.id,
  b.id,
  date '2026-09-21',
  date '2026-09-27',
  'QA September instructional break',
  '11111111-1111-4111-8111-111111111111'::uuid,
  'instructional_break'::public.closure_kind,
  'abababab-abab-4bab-8bab-ababababab01'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from public.branches b
cross join public.semesters s
where b.id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid
)
and s.code = '2026-09';


-- ============================================================
-- QA DOMAIN FIXTURE
--
-- Canonical Phase 1 fixture for later manual QA / E2E.
-- The dates intentionally target the 2026-09 / 2026-10 academy calendar that is
-- already created by committed migrations.
--
-- Current logical state on 2026-09-22:
--   - current semester: 2026-09
--   - instructional break: 2026-09-21 ~ 2026-09-27
--   - next semester: 2026-10
--   - regular QA Student assigned to QA Teacher
--   - four regular entitlements for the current semester
--   - the 2026-09-29 lesson/right remains reserved and is the cancellation/rebooking
--     E2E starting point
-- ============================================================

-- Keep Local QA deterministic. Database automation can be exercised explicitly in
-- dedicated tests later, but it must not mutate the baseline fixture in the background.
--
-- cron.job is intentionally protected by pg_cron. Use its public API instead of
-- directly updating the extension-owned table.
do $qa_disable_cron$
declare
  v_job_name text;
begin
  foreach v_job_name in array array[
    'forestring-finalize-due-student-withdrawals',
    'forestring-finalize-due-staff-departures',
    'forestring-semester-automation',
    'forestring-sync-teacher-work-hours'
  ]
  loop
    if not cron.unschedule(v_job_name) then
      raise exception 'QA_SEED_EXPECTED_CRON_JOB_MISSING: %', v_job_name;
    end if;
  end loop;
end;
$qa_disable_cron$;

-- The student row trigger creates an enrollment period beginning on reset day.
-- For this historical September fixture, move the synthetic enrollment start to the
-- beginning of the current QA semester.
update public.student_enrollment_periods
set
  starts_on = date '2026-08-31',
  updated_at = '2026-09-22 00:00:00+00'::timestamptz
where student_id = '44444444-4444-4444-8444-444444444444'::uuid
  and ends_on is null;

-- ------------------------------------------------------------
-- Teacher <-> student assignment
-- ------------------------------------------------------------

insert into public.teacher_student_assignments (
  id,
  teacher_id,
  student_id,
  starts_on,
  ends_on,
  branch_id,
  created_at,
  updated_at
)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  date '2026-08-31',
  null,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
);

-- ------------------------------------------------------------
-- QA Teacher work hours
--
-- Public snapshot + private version rows are both seeded because current scheduling
-- RPCs resolve availability through the private effective-date model.
-- ------------------------------------------------------------

insert into private.teacher_work_hour_versions (
  id,
  teacher_id,
  effective_from,
  effective_until,
  created_by,
  created_at,
  updated_at
)
values (
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  date '2026-08-31',
  null,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
);

insert into private.teacher_work_hour_entries (
  id,
  version_id,
  weekday,
  start_time,
  end_time,
  created_at
)
values
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 1, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 2, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd3'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 3, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd4'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 4, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd5'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 5, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd6'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 6, time '09:00', time '21:00', '2026-09-22 00:00:00+00'),
  ('dddddddd-dddd-4ddd-8ddd-ddddddddddd7'::uuid, 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1'::uuid, 7, time '09:00', time '21:00', '2026-09-22 00:00:00+00');

insert into public.teacher_work_hours (
  id,
  teacher_id,
  weekday,
  start_time,
  end_time,
  created_at,
  updated_at
)
values
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 1, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 2, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 3, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 4, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 5, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee6'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 6, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee7'::uuid, '33333333-3333-4333-8333-333333333333'::uuid, 7, time '09:00', time '21:00', '2026-09-22 00:00:00+00', '2026-09-22 00:00:00+00');

-- ------------------------------------------------------------
-- Current + next student semester plans
-- ------------------------------------------------------------

insert into public.student_semester_plans (
  id,
  student_id,
  semester_id,
  branch_id,
  student_type_snapshot,
  flex_base_right_count,
  flex_duration_minutes,
  status,
  created_by,
  updated_by,
  created_at,
  updated_at
)
select
  '55555555-5555-4555-8555-555555555551'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  s.id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'regular'::public.student_type,
  null,
  null,
  'active'::public.student_semester_plan_status,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from public.semesters s
where s.code = '2026-09';

insert into public.student_semester_plans (
  id,
  student_id,
  semester_id,
  branch_id,
  student_type_snapshot,
  flex_base_right_count,
  flex_duration_minutes,
  status,
  created_by,
  updated_by,
  created_at,
  updated_at
)
select
  '55555555-5555-4555-8555-555555555552'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  s.id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'regular'::public.student_type,
  null,
  null,
  'planned'::public.student_semester_plan_status,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
from public.semesters s
where s.code = '2026-10';

-- ------------------------------------------------------------
-- Regular schedule + series
-- ------------------------------------------------------------

insert into public.regular_schedule_slots (
  id,
  student_id,
  branch_id,
  starts_on,
  ends_on,
  created_by,
  created_at,
  updated_at
)
values (
  '66666666-6666-4666-8666-666666666661'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  date '2026-08-31',
  null,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
);

insert into public.lesson_series (
  id,
  student_id,
  teacher_id,
  weekday,
  start_time,
  duration_minutes,
  effective_from,
  effective_until,
  legacy_code,
  branch_id,
  schedule_slot_id,
  created_at,
  updated_at
)
values (
  '77777777-7777-4777-8777-777777777771'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  2,
  time '18:00',
  60,
  date '2026-08-31',
  null,
  null,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  '66666666-6666-4666-8666-666666666661'::uuid,
  '2026-09-22 00:00:00+00'::timestamptz,
  '2026-09-22 00:00:00+00'::timestamptz
);

-- ------------------------------------------------------------
-- Four current-semester regular entitlements
--
-- The first three model already-used historical entitlements.
-- Sequence #4 remains reserved for the 2026-09-29 cancellation -> available ->
-- rebooking E2E journey.
-- ------------------------------------------------------------

with current_semester as (
  select id
  from public.semesters
  where code = '2026-09'
)
insert into public.lesson_rights (
  id,
  student_id,
  branch_id,
  source_semester_id,
  usable_semester_id,
  schedule_slot_id,
  source_right_id,
  origin,
  sequence_no,
  duration_minutes,
  status,
  carryover_count,
  created_by,
  issued_at,
  reserved_at,
  consumed_at,
  created_at,
  updated_at
)
select *
from (
  select
    '88888888-8888-4888-8888-888888888881'::uuid as id,
    '44444444-4444-4444-8444-444444444444'::uuid as student_id,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid as branch_id,
    s.id as source_semester_id,
    s.id as usable_semester_id,
    '66666666-6666-4666-8666-666666666661'::uuid as schedule_slot_id,
    null::uuid as source_right_id,
    'regular_base'::public.lesson_right_origin as origin,
    1 as sequence_no,
    60 as duration_minutes,
    'consumed'::public.lesson_right_status as status,
    0::smallint as carryover_count,
    '11111111-1111-4111-8111-111111111111'::uuid as created_by,
    '2026-08-31 00:00:00+09'::timestamptz as issued_at,
    '2026-08-31 00:00:00+09'::timestamptz as reserved_at,
    '2026-09-01 19:00:00+09'::timestamptz as consumed_at,
    '2026-08-31 00:00:00+09'::timestamptz as created_at,
    '2026-09-01 19:00:00+09'::timestamptz as updated_at
  from current_semester s

  union all

  select
    '88888888-8888-4888-8888-888888888882'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id,
    s.id,
    '66666666-6666-4666-8666-666666666661'::uuid,
    null::uuid,
    'regular_base'::public.lesson_right_origin,
    2,
    60,
    'consumed'::public.lesson_right_status,
    0::smallint,
    '11111111-1111-4111-8111-111111111111'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-08 19:00:00+09'::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-08 19:00:00+09'::timestamptz
  from current_semester s

  union all

  select
    '88888888-8888-4888-8888-888888888883'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id,
    s.id,
    '66666666-6666-4666-8666-666666666661'::uuid,
    null::uuid,
    'regular_base'::public.lesson_right_origin,
    3,
    60,
    'consumed'::public.lesson_right_status,
    0::smallint,
    '11111111-1111-4111-8111-111111111111'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-15 19:00:00+09'::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-15 19:00:00+09'::timestamptz
  from current_semester s

  union all

  select
    '88888888-8888-4888-8888-888888888884'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
    s.id,
    s.id,
    '66666666-6666-4666-8666-666666666661'::uuid,
    null::uuid,
    'regular_base'::public.lesson_right_origin,
    4,
    60,
    'reserved'::public.lesson_right_status,
    0::smallint,
    '11111111-1111-4111-8111-111111111111'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    null::timestamptz,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-22 00:00:00+09'::timestamptz
  from current_semester s
) seeded_rights;

-- ------------------------------------------------------------
-- Canonical regular lesson instances
-- ------------------------------------------------------------

insert into public.lessons (
  id,
  series_id,
  student_id,
  teacher_id,
  occurrence_at,
  starts_at,
  duration_minutes,
  lesson_type,
  status,
  lesson_right_id,
  created_at,
  updated_at
)
values
  (
    '99999999-9999-4999-8999-999999999991'::uuid,
    '77777777-7777-4777-8777-777777777771'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    '2026-09-01 18:00:00+09'::timestamptz,
    '2026-09-01 18:00:00+09'::timestamptz,
    60,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    '88888888-8888-4888-8888-888888888881'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-01 19:00:00+09'::timestamptz
  ),
  (
    '99999999-9999-4999-8999-999999999992'::uuid,
    '77777777-7777-4777-8777-777777777771'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    '2026-09-08 18:00:00+09'::timestamptz,
    '2026-09-08 18:00:00+09'::timestamptz,
    60,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    '88888888-8888-4888-8888-888888888882'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-08 19:00:00+09'::timestamptz
  ),
  (
    '99999999-9999-4999-8999-999999999993'::uuid,
    '77777777-7777-4777-8777-777777777771'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    '2026-09-15 18:00:00+09'::timestamptz,
    '2026-09-15 18:00:00+09'::timestamptz,
    60,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    '88888888-8888-4888-8888-888888888883'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-15 19:00:00+09'::timestamptz
  ),
  (
    '99999999-9999-4999-8999-999999999994'::uuid,
    '77777777-7777-4777-8777-777777777771'::uuid,
    '44444444-4444-4444-8444-444444444444'::uuid,
    '33333333-3333-4333-8333-333333333333'::uuid,
    '2026-09-29 18:00:00+09'::timestamptz,
    '2026-09-29 18:00:00+09'::timestamptz,
    60,
    'regular'::public.lesson_type,
    'scheduled'::public.lesson_status,
    '88888888-8888-4888-8888-888888888884'::uuid,
    '2026-08-31 00:00:00+09'::timestamptz,
    '2026-09-22 00:00:00+09'::timestamptz
  );

-- ------------------------------------------------------------
-- Seed assertions
-- ------------------------------------------------------------

do $qa_seed_validation$
declare
  v_current_semester_id uuid;
begin
  select id into v_current_semester_id
  from public.semesters
  where code = '2026-09';

  if v_current_semester_id is null then
    raise exception 'QA_SEED_CURRENT_SEMESTER_MISSING';
  end if;

  if not exists (
    select 1
    from public.semesters
    where code = '2026-10'
  ) then
    raise exception 'QA_SEED_NEXT_SEMESTER_MISSING';
  end if;

  if not exists (
    select 1
    from public.closure_periods cp
    where cp.branch_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid
      and cp.semester_id = v_current_semester_id
      and cp.starts_on = date '2026-09-21'
      and cp.ends_on = date '2026-09-27'
      and cp.closure_kind = 'instructional_break'::public.closure_kind
  ) then
    raise exception 'QA_SEED_INSTRUCTIONAL_BREAK_MISSING';
  end if;

  if (
    select count(*)
    from public.lesson_rights r
    where r.student_id = '44444444-4444-4444-8444-444444444444'::uuid
      and r.source_semester_id = v_current_semester_id
      and r.origin = 'regular_base'::public.lesson_right_origin
  ) <> 4 then
    raise exception 'QA_SEED_REGULAR_RIGHT_COUNT_MISMATCH';
  end if;

  if not exists (
    select 1
    from public.lessons l
    where l.id = '99999999-9999-4999-8999-999999999994'::uuid
      and l.starts_at = '2026-09-29 18:00:00+09'::timestamptz
      and l.status = 'scheduled'::public.lesson_status
      and l.lesson_right_id = '88888888-8888-4888-8888-888888888884'::uuid
  ) then
    raise exception 'QA_SEED_E2E_START_LESSON_MISSING';
  end if;
end;
$qa_seed_validation$;
