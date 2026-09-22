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
