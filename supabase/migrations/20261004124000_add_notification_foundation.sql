-- ============================================================
-- Forestring v3.4
-- Notification foundation
--
-- Supabase remains the source of truth.
-- Firebase Cloud Messaging / APNs are delivery transports only.
--
-- Phase 1 recipient scope:
--   regular teacher profiles only.
--
-- Teacher v1 event scope:
--   - lesson assignment
--   - lesson schedule change
--   - lesson cancellation
--   - makeup lesson create / cancel
--   - flex lesson booking
-- ============================================================


-- ============================================================
-- 1. DEVICE PUSH TOKENS
-- ============================================================

create table public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),

  profile_id uuid not null
    references public.profiles(id)
    on delete cascade,

  app_id text not null,
  installation_id text not null,
  platform text not null,
  fcm_token text not null,

  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint device_push_tokens_app_id_check
    check (
      app_id in (
        'forestring.teacher.app',
        'forestring.student.app'
      )
    ),

  constraint device_push_tokens_installation_id_check
    check (
      length(installation_id) between 16 and 128
    ),

  constraint device_push_tokens_platform_check
    check (
      platform in ('android', 'ios')
    ),

  constraint device_push_tokens_fcm_token_check
    check (
      length(fcm_token) between 20 and 4096
    ),

  constraint device_push_tokens_installation_unique
    unique (app_id, installation_id),

  constraint device_push_tokens_fcm_token_unique
    unique (fcm_token)
);

create index device_push_tokens_profile_active_idx
  on public.device_push_tokens(profile_id, app_id, platform)
  where disabled_at is null;

create trigger device_push_tokens_set_updated_at
before update on public.device_push_tokens
for each row
execute function public.set_updated_at();


-- ============================================================
-- 2. NOTIFICATION PREFERENCES
--
-- Missing rows are treated as the defaults below.
-- Rows are lazily created when a device registers or when
-- preference RPCs are called.
-- ============================================================

create table public.notification_preferences (
  profile_id uuid primary key
    references public.profiles(id)
    on delete cascade,

  push_enabled boolean not null default true,

  lesson_assignment_enabled boolean not null default true,
  lesson_schedule_change_enabled boolean not null default true,
  lesson_cancellation_enabled boolean not null default true,
  makeup_enabled boolean not null default true,
  flex_booking_enabled boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger notification_preferences_set_updated_at
before update on public.notification_preferences
for each row
execute function public.set_updated_at();


-- ============================================================
-- 3. NOTIFICATION OUTBOX
--
-- No historical audit backfill is performed by this migration.
-- Only domain events created after trigger installation enqueue.
-- ============================================================

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),

  recipient_profile_id uuid not null
    references public.profiles(id)
    on delete cascade,

  event_key text not null,
  source_kind text not null,
  source_id uuid,

  dedupe_key text not null unique,

  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,

  status text not null default 'pending',
  attempt_count integer not null default 0,
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  sent_at timestamptz,
  last_error text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint notification_outbox_event_key_check
    check (
      event_key in (
        'lesson_assignment',
        'lesson_schedule_changed',
        'lesson_canceled',
        'makeup_created',
        'makeup_canceled',
        'flex_booking'
      )
    ),

  constraint notification_outbox_status_check
    check (
      status in (
        'pending',
        'processing',
        'sent',
        'failed',
        'skipped'
      )
    ),

  constraint notification_outbox_attempt_count_check
    check (attempt_count >= 0),

  constraint notification_outbox_data_object_check
    check (jsonb_typeof(data) = 'object')
);

create index notification_outbox_dispatch_idx
  on public.notification_outbox(status, available_at, created_at)
  where status in ('pending', 'failed');

create index notification_outbox_recipient_created_idx
  on public.notification_outbox(recipient_profile_id, created_at desc);

create trigger notification_outbox_set_updated_at
before update on public.notification_outbox
for each row
execute function public.set_updated_at();


-- ============================================================
-- 4. NOTIFICATION DELIVERIES
-- ============================================================

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),

  outbox_id uuid not null
    references public.notification_outbox(id)
    on delete cascade,

  device_push_token_id uuid
    references public.device_push_tokens(id)
    on delete set null,

  attempt_no integer not null,
  status text not null,

  provider_message_id text,
  error_code text,
  error_detail text,

  attempted_at timestamptz not null default now(),

  constraint notification_deliveries_attempt_no_check
    check (attempt_no > 0),

  constraint notification_deliveries_status_check
    check (
      status in (
        'accepted',
        'failed',
        'skipped'
      )
    ),

  constraint notification_deliveries_attempt_unique
    unique (outbox_id, device_push_token_id, attempt_no)
);

create index notification_deliveries_outbox_idx
  on public.notification_deliveries(outbox_id, attempted_at desc);


-- ============================================================
-- 5. RLS / TABLE PRIVILEGES
--
-- Clients do not read raw FCM tokens or mutate outbox rows.
-- Authenticated access is through the RPC boundary below.
-- service_role keeps its normal RLS bypass behavior.
-- ============================================================

alter table public.device_push_tokens enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.notification_deliveries enable row level security;

revoke all on table public.device_push_tokens
  from anon, authenticated;

revoke all on table public.notification_preferences
  from anon, authenticated;

revoke all on table public.notification_outbox
  from anon, authenticated;

revoke all on table public.notification_deliveries
  from anon, authenticated;


-- ============================================================
-- 6. CLIENT DEVICE REGISTRATION RPC
-- ============================================================

create or replace function public.register_push_device(
  p_installation_id text,
  p_fcm_token text,
  p_platform text,
  p_app_id text default 'forestring.teacher.app'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_profile_role public.user_role;
  v_token_id uuid;
  v_installation_id text := btrim(coalesce(p_installation_id, ''));
  v_fcm_token text := btrim(coalesce(p_fcm_token, ''));
  v_platform text := lower(btrim(coalesce(p_platform, '')));
  v_app_id text := btrim(coalesce(p_app_id, ''));
begin
  if v_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_profile_id);

  select p.role
  into v_profile_role
  from public.profiles p
  where p.id = v_profile_id
    and p.is_active = true;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PROFILE_NOT_FOUND';
  end if;

  if v_app_id = 'forestring.teacher.app'
     and v_profile_role = 'student'::public.user_role then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PUSH_APP_ROLE_MISMATCH';
  end if;

  if v_app_id = 'forestring.student.app'
     and v_profile_role <> 'student'::public.user_role then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_PUSH_APP_ROLE_MISMATCH';
  end if;

  if length(v_installation_id) not between 16 and 128 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_PUSH_INSTALLATION_ID';
  end if;

  if length(v_fcm_token) not between 20 and 4096 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_FCM_TOKEN';
  end if;

  if v_platform not in ('android', 'ios') then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_PUSH_PLATFORM';
  end if;

  if v_app_id not in (
    'forestring.teacher.app',
    'forestring.student.app'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_PUSH_APP';
  end if;

  -- A valid FCM token belongs to one active app installation.
  -- Reclaim the token if a stale row survived reinstall/login
  -- transitions before upserting the stable installation row.
  delete from public.device_push_tokens t
  where t.fcm_token = v_fcm_token
    and (
      t.app_id is distinct from v_app_id
      or t.installation_id is distinct from v_installation_id
    );

  insert into public.device_push_tokens (
    profile_id,
    app_id,
    installation_id,
    platform,
    fcm_token,
    last_seen_at,
    disabled_at
  )
  values (
    v_profile_id,
    v_app_id,
    v_installation_id,
    v_platform,
    v_fcm_token,
    pg_catalog.now(),
    null
  )
  on conflict (app_id, installation_id)
  do update
  set
    profile_id = excluded.profile_id,
    platform = excluded.platform,
    fcm_token = excluded.fcm_token,
    last_seen_at = pg_catalog.now(),
    disabled_at = null
  returning id
  into v_token_id;

  insert into public.notification_preferences(profile_id)
  values (v_profile_id)
  on conflict (profile_id) do nothing;

  return v_token_id;
end;
$$;

revoke all
on function public.register_push_device(text, text, text, text)
from public, anon;

grant execute
on function public.register_push_device(text, text, text, text)
to authenticated;


create or replace function public.unregister_push_device(
  p_installation_id text,
  p_app_id text default 'forestring.teacher.app'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_changed boolean;
begin
  if v_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  update public.device_push_tokens t
  set
    disabled_at = pg_catalog.now(),
    last_seen_at = pg_catalog.now()
  where t.profile_id = v_profile_id
    and t.app_id = btrim(coalesce(p_app_id, ''))
    and t.installation_id = btrim(coalesce(p_installation_id, ''))
    and t.disabled_at is null;

  v_changed := found;
  return v_changed;
end;
$$;

revoke all
on function public.unregister_push_device(text, text)
from public, anon;

grant execute
on function public.unregister_push_device(text, text)
to authenticated;


-- ============================================================
-- 7. PREFERENCE RPCs
-- ============================================================

create or replace function public.get_notification_preferences()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_preferences public.notification_preferences%rowtype;
begin
  if v_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_profile_id);

  insert into public.notification_preferences(profile_id)
  values (v_profile_id)
  on conflict (profile_id) do nothing;

  select *
  into v_preferences
  from public.notification_preferences p
  where p.profile_id = v_profile_id;

  return jsonb_build_object(
    'pushEnabled', v_preferences.push_enabled,
    'lessonAssignmentEnabled', v_preferences.lesson_assignment_enabled,
    'lessonScheduleChangeEnabled', v_preferences.lesson_schedule_change_enabled,
    'lessonCancellationEnabled', v_preferences.lesson_cancellation_enabled,
    'makeupEnabled', v_preferences.makeup_enabled,
    'flexBookingEnabled', v_preferences.flex_booking_enabled
  );
end;
$$;

revoke all
on function public.get_notification_preferences()
from public, anon;

grant execute
on function public.get_notification_preferences()
to authenticated;


create or replace function public.update_notification_preferences(
  p_push_enabled boolean default null,
  p_lesson_assignment_enabled boolean default null,
  p_lesson_schedule_change_enabled boolean default null,
  p_lesson_cancellation_enabled boolean default null,
  p_makeup_enabled boolean default null,
  p_flex_booking_enabled boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_preferences public.notification_preferences%rowtype;
begin
  if v_profile_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_profile_id);

  insert into public.notification_preferences(profile_id)
  values (v_profile_id)
  on conflict (profile_id) do nothing;

  update public.notification_preferences p
  set
    push_enabled = coalesce(p_push_enabled, p.push_enabled),
    lesson_assignment_enabled =
      coalesce(p_lesson_assignment_enabled, p.lesson_assignment_enabled),
    lesson_schedule_change_enabled =
      coalesce(
        p_lesson_schedule_change_enabled,
        p.lesson_schedule_change_enabled
      ),
    lesson_cancellation_enabled =
      coalesce(
        p_lesson_cancellation_enabled,
        p.lesson_cancellation_enabled
      ),
    makeup_enabled = coalesce(p_makeup_enabled, p.makeup_enabled),
    flex_booking_enabled =
      coalesce(p_flex_booking_enabled, p.flex_booking_enabled)
  where p.profile_id = v_profile_id
  returning *
  into v_preferences;

  return jsonb_build_object(
    'pushEnabled', v_preferences.push_enabled,
    'lessonAssignmentEnabled', v_preferences.lesson_assignment_enabled,
    'lessonScheduleChangeEnabled', v_preferences.lesson_schedule_change_enabled,
    'lessonCancellationEnabled', v_preferences.lesson_cancellation_enabled,
    'makeupEnabled', v_preferences.makeup_enabled,
    'flexBookingEnabled', v_preferences.flex_booking_enabled
  );
end;
$$;

revoke all
on function public.update_notification_preferences(
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean
)
from public, anon;

grant execute
on function public.update_notification_preferences(
  boolean,
  boolean,
  boolean,
  boolean,
  boolean,
  boolean
)
to authenticated;


-- ============================================================
-- 8. PRIVATE ENQUEUE HELPER
--
-- Phase 1 deliberately restricts recipients to role=teacher.
-- Manager/master recipient policies are added in the next phase.
-- ============================================================

create or replace function private.enqueue_teacher_notification(
  p_recipient_profile_id uuid,
  p_event_key text,
  p_source_kind text,
  p_source_id uuid,
  p_dedupe_key text,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_preferences public.notification_preferences%rowtype;
  v_enabled boolean := true;
begin
  if p_recipient_profile_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_recipient_profile_id
      and p.role = 'teacher'::public.user_role
      and p.is_active = true
      and p.is_review_account = false
  ) then
    return;
  end if;

  select *
  into v_preferences
  from public.notification_preferences p
  where p.profile_id = p_recipient_profile_id;

  if found then
    if not v_preferences.push_enabled then
      return;
    end if;

    v_enabled :=
      case p_event_key
        when 'lesson_assignment'
          then v_preferences.lesson_assignment_enabled
        when 'lesson_schedule_changed'
          then v_preferences.lesson_schedule_change_enabled
        when 'lesson_canceled'
          then v_preferences.lesson_cancellation_enabled
        when 'makeup_created'
          then v_preferences.makeup_enabled
        when 'makeup_canceled'
          then v_preferences.makeup_enabled
        when 'flex_booking'
          then v_preferences.flex_booking_enabled
        else false
      end;

    if not v_enabled then
      return;
    end if;
  end if;

  insert into public.notification_outbox (
    recipient_profile_id,
    event_key,
    source_kind,
    source_id,
    dedupe_key,
    title,
    body,
    data
  )
  values (
    p_recipient_profile_id,
    p_event_key,
    p_source_kind,
    p_source_id,
    p_dedupe_key,
    p_title,
    p_body,
    coalesce(p_data, '{}'::jsonb)
  )
  on conflict (dedupe_key) do nothing;
end;
$$;

revoke all
on function private.enqueue_teacher_notification(
  uuid,
  text,
  text,
  uuid,
  text,
  text,
  text,
  jsonb
)
from public, anon, authenticated;


-- ============================================================
-- 9. NEW TEACHER ASSIGNMENT -> OUTBOX
-- ============================================================

create or replace function private.enqueue_teacher_assignment_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_name text;
  v_dedupe_key text;
begin
  if tg_op = 'UPDATE'
     and old.teacher_id is not distinct from new.teacher_id then
    return new;
  end if;

  select p.display_name
  into v_student_name
  from public.profiles p
  where p.id = new.student_id;

  v_dedupe_key :=
    'assignment:' ||
    new.id::text ||
    ':' ||
    new.teacher_id::text ||
    ':' ||
    new.starts_on::text;

  perform private.enqueue_teacher_notification(
    new.teacher_id,
    'lesson_assignment',
    'teacher_student_assignment',
    new.id,
    v_dedupe_key,
    '새 수업이 배정되었습니다',
    coalesce(v_student_name, '학생') ||
      ' 학생의 새 수업 배정을 확인해주세요.',
    jsonb_build_object(
      'eventKey', 'lesson_assignment',
      'assignmentId', new.id,
      'studentId', new.student_id,
      'startsOn', new.starts_on,
      'branchId', new.branch_id
    )
  );

  return new;
end;
$$;

revoke all
on function private.enqueue_teacher_assignment_notification()
from public, anon, authenticated;

create trigger teacher_student_assignments_enqueue_notification
after insert or update of teacher_id
on public.teacher_student_assignments
for each row
execute function private.enqueue_teacher_assignment_notification();


-- ============================================================
-- 10. AUDIT EVENT -> OUTBOX
--
-- Existing domain audit events are reused as the notification
-- source. No Push is sent from a Flutter button tap.
-- ============================================================

create or replace function private.enqueue_teacher_notification_from_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_teacher_id uuid;
  v_before_teacher_id uuid;
  v_lesson_id uuid;
  v_lesson_type public.lesson_type;
  v_starts_at timestamptz;
  v_ends_at timestamptz;

  v_event_key text;
  v_title text;
  v_body text;
  v_student_name text;
  v_data jsonb := '{}'::jsonb;
begin
  if new.event_type not in (
    'LESSON_MANUALLY_UPDATED',
    'REGULAR_SCHEDULE_CHANGED',
    'LESSON_CANCELED',
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED',
    'LESSON_RIGHT_BOOKED'
  ) then
    return new;
  end if;

  select p.display_name
  into v_student_name
  from public.profiles p
  where p.id = new.subject_profile_id;

  if new.event_type = 'LESSON_MANUALLY_UPDATED' then
    begin
      v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    v_event_key := 'lesson_schedule_changed';
    v_title := '수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 일정을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', new.details ->> 'lessonId',
        'branchId', new.branch_id,
        'before', new.details -> 'before',
        'after', new.details -> 'after'
      );

  elsif new.event_type = 'REGULAR_SCHEDULE_CHANGED' then
    begin
      v_teacher_id :=
        nullif(new.details #>> '{after,teacherId}', '')::uuid;

      v_before_teacher_id :=
        nullif(new.details #>> '{before,teacherId}', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    -- Teacher reassignment is covered by the assignment trigger.
    -- Avoid a duplicate "schedule changed" Push to the new teacher.
    if v_before_teacher_id is distinct from v_teacher_id then
      return new;
    end if;

    v_event_key := 'lesson_schedule_changed';
    v_title := '정규 수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 정규 일정을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'branchId', new.branch_id,
        'scheduleSlotId', new.details ->> 'scheduleSlotId',
        'before', new.details -> 'before',
        'after', new.details -> 'after'
      );

  elsif new.event_type = 'LESSON_CANCELED' then
    begin
      v_lesson_id := nullif(new.details ->> 'lessonId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at
    from public.lessons l
    where l.id = v_lesson_id;

    if not found then
      return new;
    end if;

    v_event_key := 'lesson_canceled';
    v_title := '수업이 취소되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 취소된 수업을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', v_lesson_id,
        'lessonType', v_lesson_type,
        'branchId', new.branch_id,
        'startsAt', v_starts_at,
        'endsAt', v_ends_at,
        'cancellationOrigin', new.details ->> 'cancellationOrigin'
      );

  elsif new.event_type in (
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED'
  ) then
    begin
      v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    if new.event_type = 'MAKEUP_LESSON_CREATED' then
      v_event_key := 'makeup_created';
      v_title := '보강 수업이 등록되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 보강 수업을 확인해주세요.';
    else
      v_event_key := 'makeup_canceled';
      v_title := '보강 수업이 취소되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 취소된 보강 수업을 확인해주세요.';
    end if;

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', new.details ->> 'lessonId',
        'branchId', new.branch_id,
        'startsAt', new.details -> 'startsAt',
        'endsAt', new.details -> 'endsAt'
      );

  elsif new.event_type = 'LESSON_RIGHT_BOOKED' then
    begin
      v_lesson_id := nullif(new.details ->> 'lessonId', '')::uuid;
    exception
      when invalid_text_representation then
        return new;
    end;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at
    from public.lessons l
    where l.id = v_lesson_id;

    if not found
       or v_lesson_type <> 'flex'::public.lesson_type then
      return new;
    end if;

    v_event_key := 'flex_booking';
    v_title := '자율 학생이 수업을 예약했습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 새 예약을 확인해주세요.';

    v_data :=
      jsonb_build_object(
        'eventKey', v_event_key,
        'auditEventId', new.id,
        'studentId', new.subject_profile_id,
        'lessonId', v_lesson_id,
        'branchId', new.branch_id,
        'startsAt', v_starts_at,
        'endsAt', v_ends_at
      );
  end if;

  if v_teacher_id is null
     or v_event_key is null then
    return new;
  end if;

  perform private.enqueue_teacher_notification(
    v_teacher_id,
    v_event_key,
    'audit_event',
    new.id,
    'audit:' || new.id::text || ':' || v_teacher_id::text || ':' || v_event_key,
    v_title,
    v_body,
    v_data
  );

  return new;
end;
$$;

revoke all
on function private.enqueue_teacher_notification_from_audit()
from public, anon, authenticated;

create trigger audit_events_enqueue_teacher_notification
after insert
on public.audit_events
for each row
execute function private.enqueue_teacher_notification_from_audit();


-- ============================================================
-- 11. COMMENTS
-- ============================================================

comment on table public.device_push_tokens is
  'FCM registration tokens bound to one authenticated Forestring profile and one local app installation. Disabled on logout and rebound on account changes.';

comment on table public.notification_preferences is
  'Per-profile Push preferences. Phase 1 columns cover regular-teacher v3.4 notification events.';

comment on table public.notification_outbox is
  'Durable, idempotent Push queue created from successful database domain events. Clients cannot write this table directly.';

comment on table public.notification_deliveries is
  'Per-device provider attempt history for notification_outbox rows. FCM acceptance/failure is recorded here; this is not a device-read receipt.';

comment on function public.register_push_device(text, text, text, text) is
  'Registers or rebinds an FCM token to the current authenticated profile and local installation. Re-enables the installation after a later login.';

comment on function public.unregister_push_device(text, text) is
  'Disables the current profile app installation before Supabase logout so an old account cannot continue receiving Push notifications.';
