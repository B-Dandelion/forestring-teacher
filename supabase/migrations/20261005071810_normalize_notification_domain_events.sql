-- Forestring v3.4 notification domain normalization.
-- Keeps the existing Flutter notification-settings RPC contract compatible,
-- while moving enqueue policy to an event catalog / role policy / event preference model.
-- REGULAR_SCHEDULE_ENDED remains an audit event only and is intentionally not a Push event.

-- ============================================================
-- 1. INTERNAL EVENT CATALOG / ROLE POLICY / EVENT PREFERENCES
-- ============================================================

create table if not exists private.notification_event_catalog (
  event_key text primary key,
  target_kind text not null,
  navigation_kind text,
  preference_group text not null,
  is_deprecated boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists private.notification_role_policy (
  event_key text not null
    references private.notification_event_catalog(event_key)
    on delete cascade,
  recipient_role public.user_role not null,
  enabled_by_default boolean not null default false,
  release_enabled boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (event_key, recipient_role)
);

create table if not exists private.notification_event_preferences (
  profile_id uuid not null
    references public.profiles(id)
    on delete cascade,
  event_key text not null
    references private.notification_event_catalog(event_key)
    on delete cascade,
  enabled boolean not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (profile_id, event_key)
);

alter table private.notification_event_catalog enable row level security;
alter table private.notification_role_policy enable row level security;
alter table private.notification_event_preferences enable row level security;

revoke all on table private.notification_event_catalog
  from public, anon, authenticated, service_role;
revoke all on table private.notification_role_policy
  from public, anon, authenticated, service_role;
revoke all on table private.notification_event_preferences
  from public, anon, authenticated, service_role;

insert into private.notification_event_catalog (
  event_key,
  target_kind,
  navigation_kind,
  preference_group,
  is_deprecated
)
values
  ('student_assigned', 'assignment', 'student_detail', 'assignment', false),
  ('lesson_changed', 'lesson', 'lesson_week', 'schedule_change', false),
  ('lesson_canceled', 'lesson', 'lesson_week', 'cancellation', false),
  ('makeup_created', 'lesson', 'lesson_week', 'makeup', false),
  ('makeup_canceled', 'lesson', 'lesson_week', 'makeup', false),
  ('flex_lesson_booked', 'lesson', 'lesson_week', 'flex_booking', false),
  ('regular_schedule_changed', 'regularSchedule', 'student_detail', 'schedule_change', false),
  ('student_teacher_assigned', 'assignment', 'student_detail', 'assignment', false),

  -- Historical outbox keys retained so old delivery history keeps referential integrity.
  ('lesson_assignment', 'legacy', null, 'assignment', true),
  ('lesson_schedule_changed', 'legacy', null, 'schedule_change', true),
  ('flex_booking', 'legacy', null, 'flex_booking', true)
on conflict (event_key)
do update
set
  target_kind = excluded.target_kind,
  navigation_kind = excluded.navigation_kind,
  preference_group = excluded.preference_group,
  is_deprecated = excluded.is_deprecated,
  updated_at = pg_catalog.now();

insert into private.notification_role_policy (
  event_key,
  recipient_role,
  enabled_by_default,
  release_enabled
)
select
  c.event_key,
  r.role,
  case
    when r.role = 'teacher'::public.user_role
      and c.is_deprecated = false
    then true
    else false
  end as enabled_by_default,
  case
    when r.role = 'teacher'::public.user_role
      and c.is_deprecated = false
    then true
    else false
  end as release_enabled
from private.notification_event_catalog c
cross join (
  values
    ('teacher'::public.user_role),
    ('manager'::public.user_role),
    ('master'::public.user_role)
) as r(role)
on conflict (event_key, recipient_role)
do update
set
  enabled_by_default = excluded.enabled_by_default,
  release_enabled = excluded.release_enabled,
  updated_at = pg_catalog.now();

-- ============================================================
-- 2. OUTBOX EVENT KEY INTEGRITY
-- ============================================================

alter table public.notification_outbox
  drop constraint if exists notification_outbox_event_key_check;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_event_key_fkey;

alter table public.notification_outbox
  add constraint notification_outbox_event_key_fkey
  foreign key (event_key)
  references private.notification_event_catalog(event_key);

-- ============================================================
-- 3. MAP EXISTING GROUPED SETTINGS TO EVENT PREFERENCES
-- ============================================================

create or replace function private.sync_notification_event_preferences_from_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role public.user_role;
begin
  select p.role
  into v_role
  from public.profiles p
  where p.id = new.profile_id;

  if not found then
    return new;
  end if;

  insert into private.notification_event_preferences (
    profile_id,
    event_key,
    enabled,
    created_at,
    updated_at
  )
  select
    new.profile_id,
    c.event_key,
    case
      when v_role <> 'teacher'::public.user_role then
        rp.enabled_by_default
      when c.preference_group = 'assignment' then
        new.lesson_assignment_enabled
      when c.preference_group = 'schedule_change' then
        new.lesson_schedule_change_enabled
      when c.preference_group = 'cancellation' then
        new.lesson_cancellation_enabled
      when c.preference_group = 'makeup' then
        new.makeup_enabled
      when c.preference_group = 'flex_booking' then
        new.flex_booking_enabled
      else
        rp.enabled_by_default
    end,
    pg_catalog.now(),
    pg_catalog.now()
  from private.notification_event_catalog c
  join private.notification_role_policy rp
    on rp.event_key = c.event_key
   and rp.recipient_role = v_role
  where c.is_deprecated = false
  on conflict (profile_id, event_key)
  do update
  set
    enabled = excluded.enabled,
    updated_at = pg_catalog.now();

  return new;
end;
$function$;

revoke all
on function private.sync_notification_event_preferences_from_legacy()
from public, anon, authenticated, service_role;

drop trigger if exists notification_preferences_sync_event_preferences
on public.notification_preferences;

create trigger notification_preferences_sync_event_preferences
after insert or update of
  lesson_assignment_enabled,
  lesson_schedule_change_enabled,
  lesson_cancellation_enabled,
  makeup_enabled,
  flex_booking_enabled
on public.notification_preferences
for each row
execute function private.sync_notification_event_preferences_from_legacy();

insert into private.notification_event_preferences (
  profile_id,
  event_key,
  enabled,
  created_at,
  updated_at
)
select
  np.profile_id,
  c.event_key,
  case
    when p.role <> 'teacher'::public.user_role then
      rp.enabled_by_default
    when c.preference_group = 'assignment' then
      np.lesson_assignment_enabled
    when c.preference_group = 'schedule_change' then
      np.lesson_schedule_change_enabled
    when c.preference_group = 'cancellation' then
      np.lesson_cancellation_enabled
    when c.preference_group = 'makeup' then
      np.makeup_enabled
    when c.preference_group = 'flex_booking' then
      np.flex_booking_enabled
    else
      rp.enabled_by_default
  end,
  pg_catalog.now(),
  pg_catalog.now()
from public.notification_preferences np
join public.profiles p
  on p.id = np.profile_id
join private.notification_role_policy rp
  on rp.recipient_role = p.role
join private.notification_event_catalog c
  on c.event_key = rp.event_key
where c.is_deprecated = false
on conflict (profile_id, event_key)
do update
set
  enabled = excluded.enabled,
  updated_at = pg_catalog.now();

-- ============================================================
-- 4. GENERIC POLICY-AWARE ENQUEUE
-- ============================================================

create or replace function private.enqueue_notification(
  p_recipient_profile_id uuid,
  p_event_key text,
  p_target_id uuid,
  p_teacher_id uuid,
  p_student_id uuid,
  p_branch_id uuid,
  p_source_kind text,
  p_source_id uuid,
  p_dedupe_key text,
  p_title text,
  p_body text,
  p_occurred_at timestamptz,
  p_context jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role public.user_role;
  v_target_kind text;
  v_navigation_kind text;
  v_enabled_by_default boolean;
  v_release_enabled boolean;
  v_push_enabled boolean := true;
  v_event_enabled boolean;
  v_outbox_id uuid := gen_random_uuid();
  v_data jsonb;
begin
  if p_recipient_profile_id is null
     or p_event_key is null
     or p_target_id is null
     or p_teacher_id is null
     or p_student_id is null
     or p_branch_id is null then
    return;
  end if;

  select p.role
  into v_role
  from public.profiles p
  where p.id = p_recipient_profile_id
    and p.is_active = true
    and coalesce(p.is_review_account, false) = false;

  if not found then
    return;
  end if;

  select
    c.target_kind,
    c.navigation_kind,
    rp.enabled_by_default,
    rp.release_enabled
  into
    v_target_kind,
    v_navigation_kind,
    v_enabled_by_default,
    v_release_enabled
  from private.notification_event_catalog c
  join private.notification_role_policy rp
    on rp.event_key = c.event_key
   and rp.recipient_role = v_role
  where c.event_key = p_event_key
    and c.is_deprecated = false;

  if not found
     or coalesce(v_release_enabled, false) = false
     or v_navigation_kind is null then
    return;
  end if;

  select np.push_enabled
  into v_push_enabled
  from public.notification_preferences np
  where np.profile_id = p_recipient_profile_id;

  if found and coalesce(v_push_enabled, true) = false then
    return;
  end if;

  select ep.enabled
  into v_event_enabled
  from private.notification_event_preferences ep
  where ep.profile_id = p_recipient_profile_id
    and ep.event_key = p_event_key;

  if not found then
    v_event_enabled := v_enabled_by_default;
  end if;

  if coalesce(v_event_enabled, false) = false then
    return;
  end if;

  v_data :=
    coalesce(p_context, '{}'::jsonb)
    || jsonb_build_object(
      'schemaVersion', 1,
      'notificationId', v_outbox_id,
      'eventKey', p_event_key,
      'targetKind', v_target_kind,
      'targetId', p_target_id,
      'navigationKind', v_navigation_kind,
      'recipientProfileId', p_recipient_profile_id,
      'branchId', p_branch_id,
      'teacherId', p_teacher_id,
      'studentId', p_student_id,
      'occurredAt', coalesce(p_occurred_at, pg_catalog.now())
    );

  insert into public.notification_outbox (
    id,
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
    v_outbox_id,
    p_recipient_profile_id,
    p_event_key,
    p_source_kind,
    p_source_id,
    p_dedupe_key,
    p_title,
    p_body,
    v_data
  )
  on conflict (dedupe_key) do nothing;
end;
$function$;

revoke all
on function private.enqueue_notification(
  uuid, text, uuid, uuid, uuid, uuid,
  text, uuid, text, text, text, timestamptz, jsonb
)
from public, anon, authenticated, service_role;

-- ============================================================
-- 5. INITIAL ASSIGNMENT -> SEMANTIC AUDIT EVENT
-- ============================================================

drop trigger if exists teacher_student_assignments_enqueue_notification
on public.teacher_student_assignments;

create or replace function private.audit_initial_teacher_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_student_type public.student_type;
begin
  -- Any other assignment row means this INSERT is a reassignment/version,
  -- not the student's first teacher assignment.
  if exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = new.student_id
      and a.id <> new.id
  ) then
    return new;
  end if;

  begin
    v_student_type :=
      private.student_type_on_date(
        new.student_id,
        new.starts_on
      );
  exception
    when others then
      select s.student_type
      into v_student_type
      from public.students s
      where s.id = new.student_id;
  end;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    new.student_id,
    new.branch_id,
    null,
    'STUDENT_ASSIGNED',
    new.starts_on,
    auth.uid(),
    jsonb_build_object(
      'assignmentId', new.id,
      'teacherId', new.teacher_id,
      'studentType', v_student_type
    )
  );

  return new;
end;
$function$;

revoke all
on function private.audit_initial_teacher_assignment()
from public, anon, authenticated, service_role;

drop trigger if exists teacher_student_assignments_audit_initial_assignment
on public.teacher_student_assignments;

create trigger teacher_student_assignments_audit_initial_assignment
after insert
on public.teacher_student_assignments
for each row
execute function private.audit_initial_teacher_assignment();

-- ============================================================
-- 6. AUDIT -> NOTIFICATION DOMAIN TRANSFORMER
-- ============================================================

drop trigger if exists audit_events_enqueue_teacher_notification
on public.audit_events;

drop trigger if exists audit_events_enqueue_notification
on public.audit_events;

create or replace function private.enqueue_notification_from_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_teacher_id uuid;
  v_before_teacher_id uuid;
  v_target_id uuid;
  v_lesson_type public.lesson_type;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_duration_minutes integer;

  v_event_key text;
  v_title text;
  v_body text;
  v_student_name text;
  v_context jsonb := '{}'::jsonb;
begin
  if new.event_type not in (
    'STUDENT_ASSIGNED',
    'LESSON_MANUALLY_UPDATED',
    'REGULAR_SCHEDULE_CHANGED',
    'LESSON_CANCELED',
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED',
    'LESSON_RIGHT_BOOKED',
    'STUDENT_TEACHER_CHANGED'
  ) then
    return new;
  end if;

  select p.display_name
  into v_student_name
  from public.profiles p
  where p.id = new.subject_profile_id;

  if new.event_type = 'STUDENT_ASSIGNED' then
    v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    v_target_id := nullif(new.details ->> 'assignmentId', '')::uuid;
    v_event_key := 'student_assigned';
    v_title := '새 학생이 배정되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 정보를 확인해주세요.';

    v_context := jsonb_build_object(
      'assignmentStartsOn', new.effective_on,
      'studentType', new.details -> 'studentType'
    );

  elsif new.event_type = 'LESSON_MANUALLY_UPDATED' then
    v_teacher_id := nullif(new.details ->> 'teacherId', '')::uuid;
    v_target_id := nullif(new.details ->> 'lessonId', '')::uuid;
    v_event_key := 'lesson_changed';
    v_title := '수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 일정을 확인해주세요.';

    v_context := jsonb_build_object(
      'previousStartsAt', new.details #> '{before,startsAt}',
      'startsAt', new.details #> '{after,startsAt}',
      'previousDurationMinutes', new.details #> '{before,durationMinutes}',
      'durationMinutes', new.details #> '{after,durationMinutes}'
    );

  elsif new.event_type = 'REGULAR_SCHEDULE_CHANGED' then
    v_teacher_id :=
      nullif(new.details #>> '{after,teacherId}', '')::uuid;
    v_before_teacher_id :=
      nullif(new.details #>> '{before,teacherId}', '')::uuid;

    -- Teacher reassignment has its own semantic notification.
    if v_before_teacher_id is distinct from v_teacher_id then
      return new;
    end if;

    v_target_id :=
      nullif(new.details ->> 'scheduleSlotId', '')::uuid;
    v_event_key := 'regular_schedule_changed';
    v_title := '정규 수업 일정이 변경되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 변경된 정규 일정을 확인해주세요.';

    v_context := jsonb_build_object(
      'effectiveFrom', new.effective_on,
      'previousWeekday', new.details #> '{before,weekday}',
      'previousStartTime', new.details #> '{before,startTime}',
      'previousDurationMinutes', new.details #> '{before,durationMinutes}',
      'weekday', new.details #> '{after,weekday}',
      'startTime', new.details #> '{after,startTime}',
      'durationMinutes', new.details #> '{after,durationMinutes}'
    );

  elsif new.event_type = 'LESSON_CANCELED' then
    -- Ending a regular schedule is intentionally not a Push event.
    -- Suppress its child lesson cancellations as well.
    if new.details ->> 'reason' = 'regular_schedule_ended' then
      return new;
    end if;

    v_target_id :=
      nullif(new.details ->> 'lessonId', '')::uuid;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at,
      l.duration_minutes
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at,
      v_duration_minutes
    from public.lessons l
    where l.id = v_target_id;

    if not found then
      return new;
    end if;

    v_event_key := 'lesson_canceled';
    v_title := '수업이 취소되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 취소된 수업을 확인해주세요.';

    v_context := jsonb_build_object(
      'startsAt', v_starts_at,
      'durationMinutes', v_duration_minutes,
      'reason', new.details -> 'reason'
    );

  elsif new.event_type in (
    'MAKEUP_LESSON_CREATED',
    'MAKEUP_LESSON_CANCELED'
  ) then
    v_teacher_id :=
      nullif(new.details ->> 'teacherId', '')::uuid;
    v_target_id :=
      nullif(new.details ->> 'lessonId', '')::uuid;

    if new.event_type = 'MAKEUP_LESSON_CREATED' then
      v_event_key := 'makeup_created';
      v_title := '보강 수업이 등록되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 보강 수업을 확인해주세요.';

      v_context := jsonb_build_object(
        'startsAt', new.details -> 'startsAt',
        'durationMinutes', new.details -> 'durationMinutes'
      );
    else
      v_event_key := 'makeup_canceled';
      v_title := '보강 수업이 취소되었습니다';
      v_body :=
        coalesce(v_student_name, '학생') ||
        ' 학생의 취소된 보강 수업을 확인해주세요.';

      v_context := jsonb_build_object(
        'startsAt', new.details -> 'startsAt',
        'durationMinutes', new.details -> 'durationMinutes',
        'reason', new.details -> 'reason'
      );
    end if;

  elsif new.event_type = 'LESSON_RIGHT_BOOKED' then
    v_target_id :=
      nullif(new.details ->> 'lessonId', '')::uuid;

    select
      l.teacher_id,
      l.lesson_type,
      l.starts_at,
      l.ends_at,
      l.duration_minutes
    into
      v_teacher_id,
      v_lesson_type,
      v_starts_at,
      v_ends_at,
      v_duration_minutes
    from public.lessons l
    where l.id = v_target_id;

    if not found
       or v_lesson_type <> 'flex'::public.lesson_type then
      return new;
    end if;

    v_event_key := 'flex_lesson_booked';
    v_title := '자율 학생이 수업을 예약했습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 새 예약을 확인해주세요.';

    v_context := jsonb_build_object(
      'startsAt', v_starts_at,
      'durationMinutes', v_duration_minutes
    );

  elsif new.event_type = 'STUDENT_TEACHER_CHANGED' then
    -- v1 policy: notify only the newly assigned teacher.
    v_teacher_id :=
      nullif(new.details ->> 'newTeacherId', '')::uuid;
    v_target_id :=
      nullif(new.details ->> 'newAssignmentId', '')::uuid;
    v_event_key := 'student_teacher_assigned';
    v_title := '담당 학생이 배정되었습니다';
    v_body :=
      coalesce(v_student_name, '학생') ||
      ' 학생의 정보를 확인해주세요.';

    v_context := jsonb_build_object(
      'effectiveFrom', new.effective_on
    );
  end if;

  if v_event_key is null
     or v_teacher_id is null
     or v_target_id is null
     or new.subject_profile_id is null
     or new.branch_id is null then
    return new;
  end if;

  perform private.enqueue_notification(
    v_teacher_id,
    v_event_key,
    v_target_id,
    v_teacher_id,
    new.subject_profile_id,
    new.branch_id,
    'audit_event',
    new.id,
    'audit:' || new.id::text || ':' ||
      v_teacher_id::text || ':' || v_event_key,
    v_title,
    v_body,
    new.created_at,
    v_context
  );

  return new;

exception
  when others then
    raise warning
      'FORESTRING_NOTIFICATION_DOMAIN_ENQUEUE_FAILED event_type=% audit_id=% error=%',
      new.event_type,
      new.id,
      sqlerrm;
    return new;
end;
$function$;

revoke all
on function private.enqueue_notification_from_audit()
from public, anon, authenticated, service_role;

create trigger audit_events_enqueue_notification
after insert
on public.audit_events
for each row
execute function private.enqueue_notification_from_audit();

-- ============================================================
-- 7. REMOVE LEGACY ENQUEUE FUNCTIONS
-- ============================================================

drop function if exists private.enqueue_teacher_assignment_notification();
drop function if exists private.enqueue_teacher_notification_from_audit();

drop function if exists private.enqueue_teacher_notification(
  uuid,
  text,
  text,
  uuid,
  text,
  text,
  text,
  jsonb
);

-- ============================================================
-- 8. COMMENTS
-- ============================================================

comment on table private.notification_event_catalog is
  'Internal notification-domain catalog. Defines semantic event, target kind, navigation kind, and grouped preference compatibility metadata.';

comment on table private.notification_role_policy is
  'Internal role policy for notification events. Teacher v1 events are release-enabled; manager/master rows remain disabled until their release phase.';

comment on table private.notification_event_preferences is
  'Per-profile event-level notification preferences. Currently synchronized from the existing grouped Flutter settings contract.';

comment on function private.enqueue_notification(
  uuid, text, uuid, uuid, uuid, uuid,
  text, uuid, text, text, text, timestamptz, jsonb
) is
  'Policy-aware notification outbox writer. Builds the v1 common payload envelope and preserves event-specific context.';

comment on function private.enqueue_notification_from_audit() is
  'Transforms selected audit events into semantic notification domain events. REGULAR_SCHEDULE_ENDED is intentionally excluded from Push.';

comment on function private.audit_initial_teacher_assignment() is
  'Creates STUDENT_ASSIGNED only for the first teacher assignment. Reassignments are represented by STUDENT_TEACHER_CHANGED.';
