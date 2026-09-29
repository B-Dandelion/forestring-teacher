-- ============================================================
-- Shared lesson activity timeline + authoritative cancellation quota
-- 2026-09-29
--
-- Goals:
--   1. Student / manager / master can read the same normalized
--      lesson-right activity timeline.
--   2. Flutter no longer re-implements cancellation quota rules.
--      Remaining counts are calculated from the same authoritative
--      tables/buckets used by cancel_lesson().
-- ============================================================

create or replace function public.get_student_lesson_activity(
  p_student_id uuid default null,
  p_right_id uuid default null
)
returns table (
  lesson_right_id uuid,
  event_type text,
  event_at timestamptz,
  actor_id uuid,
  actor_name text,
  actor_role text,
  details jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_student_id uuid;
  v_student_branch_id uuid;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  v_student_id := coalesce(p_student_id, v_actor_id);

  select p.branch_id
  into v_student_branch_id
  from public.profiles p
  join public.students s on s.id = p.id
  where p.id = v_student_id
    and p.role = 'student'::public.user_role;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_id <> v_student_id
     and v_actor_role <> 'master'::public.user_role
     and not (
       v_actor_role = 'manager'::public.user_role
       and private.manager_has_branch(v_student_branch_id)
     )
     and not (
       v_actor_role = 'teacher'::public.user_role
       and private.teacher_has_student_relation(v_student_id)
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_HISTORY_FORBIDDEN';
  end if;

  if p_right_id is not null
     and not exists (
       select 1
       from public.lesson_rights r
       where r.id = p_right_id
         and r.student_id = v_student_id
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_RIGHT_NOT_FOUND';
  end if;

  return query
  with right_scope as (
    select r.*
    from public.lesson_rights r
    where r.student_id = v_student_id
      and (p_right_id is null or r.id = p_right_id)
  ),
  lesson_scope as (
    select l.*
    from public.lessons l
    join right_scope r on r.id = l.lesson_right_id
  ),
  original_events as (
    select
      r.id as lesson_right_id,
      'LESSON_ORIGINAL_SCHEDULE'::text as event_type,
      r.issued_at as event_at,
      r.created_by as actor_id,
      jsonb_build_object(
        'rightId', r.id,
        'lessonId', l.id,
        'rightOrigin', r.origin,
        'lessonType', l.lesson_type,
        'startsAt', coalesce(l.occurrence_at, l.starts_at),
        'endsAt',
          coalesce(l.occurrence_at, l.starts_at)
          + make_interval(mins => r.duration_minutes),
        'durationMinutes', r.duration_minutes,
        'occurrenceAt', l.occurrence_at
      ) as details,
      0 as event_priority
    from right_scope r
    join lesson_scope l on l.lesson_right_id = r.id
    where r.origin = 'regular_base'::public.lesson_right_origin
      and coalesce(l.occurrence_at, l.starts_at) is not null
  ),
  cancellation_events as (
    select
      ce.lesson_right_id,
      'LESSON_CANCELED'::text as event_type,
      ce.canceled_at as event_at,
      ce.actor_id,
      jsonb_build_object(
        'eventId', ce.id,
        'rightId', ce.lesson_right_id,
        'lessonId', ce.lesson_id,
        'cancellationOrigin', ce.origin,
        'countsTowardLimit', ce.counts_toward_limit,
        'reason', ce.reason,
        'startsAt', ce.lesson_starts_at,
        'endsAt',
          case
            when ce.lesson_starts_at is null
              or ce.lesson_duration_minutes is null
              then null
            else ce.lesson_starts_at
                 + make_interval(mins => ce.lesson_duration_minutes)
          end,
        'durationMinutes', ce.lesson_duration_minutes
      ) as details,
      1 as event_priority
    from public.lesson_cancellation_events ce
    join right_scope r on r.id = ce.lesson_right_id
  ),
  audit_activity as (
    select
      r.id as lesson_right_id,
      ae.event_type,
      ae.created_at as event_at,
      ae.actor_id,
      ae.details,
      2 as event_priority
    from public.audit_events ae
    join right_scope r
      on ae.details ->> 'rightId' = r.id::text
      or exists (
        select 1
        from lesson_scope l
        where l.lesson_right_id = r.id
          and ae.details ->> 'lessonId' = l.id::text
      )
    where ae.subject_profile_id = v_student_id
      and ae.event_type in (
        'LESSON_RIGHT_BOOKED',
        'LESSON_MANUALLY_UPDATED',
        'MAKEUP_LESSON_CREATED'
      )
  ),
  all_events as (
    select * from original_events
    union all
    select * from cancellation_events
    union all
    select * from audit_activity
  )
  select
    e.lesson_right_id,
    e.event_type,
    e.event_at,
    e.actor_id,
    p.display_name as actor_name,
    p.role::text as actor_role,
    e.details
  from all_events e
  left join public.profiles p on p.id = e.actor_id
  order by e.lesson_right_id, e.event_at, e.event_priority;
end;
$function$;

revoke all on function public.get_student_lesson_activity(uuid, uuid)
from public;

grant execute on function public.get_student_lesson_activity(uuid, uuid)
to authenticated;

comment on function public.get_student_lesson_activity(uuid, uuid) is
  'Returns one normalized chronological lesson-right activity source for students and authorized staff. Cancellation snapshots come from lesson_cancellation_events; bookings/rebookings and managed changes come from audit_events.';


create or replace function public.get_student_cancellation_quotas(
  p_student_id uuid default null
)
returns table (
  semester_id uuid,
  student_type text,
  cancellation_limit integer,
  counted_cancellations integer,
  remaining_cancellations integer,
  buckets jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_student_id uuid;
  v_student_branch_id uuid;
  v_plan record;
  v_limit integer;
  v_counted integer;
  v_remaining integer;
  v_buckets jsonb;
begin
  v_actor_id := auth.uid();

  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  v_student_id := coalesce(p_student_id, v_actor_id);

  select p.branch_id
  into v_student_branch_id
  from public.profiles p
  join public.students s on s.id = p.id
  where p.id = v_student_id
    and p.role = 'student'::public.user_role;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ACTIVE_USER_REQUIRED';
  end if;

  if v_actor_id <> v_student_id
     and v_actor_role <> 'master'::public.user_role
     and not (
       v_actor_role = 'manager'::public.user_role
       and private.manager_has_branch(v_student_branch_id)
     )
     and not (
       v_actor_role = 'teacher'::public.user_role
       and private.teacher_has_student_relation(v_student_id)
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_STUDENT_HISTORY_FORBIDDEN';
  end if;

  for v_plan in
    select
      sp.semester_id,
      sp.student_type_snapshot,
      sp.flex_base_right_count
    from public.student_semester_plans sp
    where sp.student_id = v_student_id
    order by sp.created_at
  loop
    v_limit := 0;
    v_counted := 0;
    v_remaining := 0;
    v_buckets := '[]'::jsonb;

    if v_plan.student_type_snapshot = 'regular'::public.student_type then
      with slot_ids as (
        select distinct r.schedule_slot_id
        from public.lesson_rights r
        where r.student_id = v_student_id
          and r.source_semester_id = v_plan.semester_id
          and r.origin = 'regular_base'::public.lesson_right_origin
          and r.schedule_slot_id is not null
      ),
      slot_counts as (
        select
          s.schedule_slot_id,
          count(e.id)::integer as counted
        from slot_ids s
        left join public.lesson_rights r
          on r.student_id = v_student_id
         and r.source_semester_id = v_plan.semester_id
         and r.origin = 'regular_base'::public.lesson_right_origin
         and r.schedule_slot_id = s.schedule_slot_id
        left join public.lesson_cancellation_events e
          on e.lesson_right_id = r.id
         and e.student_id = v_student_id
         and e.origin = 'student'::public.lesson_cancellation_origin
         and e.counts_toward_limit = true
        group by s.schedule_slot_id
      )
      select
        coalesce(sum(2), 0)::integer,
        coalesce(sum(sc.counted), 0)::integer,
        coalesce(sum(greatest(2 - sc.counted, 0)), 0)::integer,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'kind', 'regular_slot',
              'scheduleSlotId', sc.schedule_slot_id,
              'limit', 2,
              'counted', sc.counted,
              'remaining', greatest(2 - sc.counted, 0)
            )
            order by sc.schedule_slot_id
          ),
          '[]'::jsonb
        )
      into
        v_limit,
        v_counted,
        v_remaining,
        v_buckets
      from slot_counts sc;

    elsif v_plan.student_type_snapshot = 'flex'::public.student_type then
      v_limit :=
        floor(coalesce(v_plan.flex_base_right_count, 0)::numeric / 4)::integer * 2;

      select count(*)::integer
      into v_counted
      from public.lesson_cancellation_events e
      join public.lesson_rights r on r.id = e.lesson_right_id
      where e.student_id = v_student_id
        and e.origin = 'student'::public.lesson_cancellation_origin
        and e.counts_toward_limit = true
        and r.origin = 'flex_base'::public.lesson_right_origin
        and r.source_semester_id = v_plan.semester_id;

      v_remaining := greatest(v_limit - v_counted, 0);

      v_buckets := jsonb_build_array(
        jsonb_build_object(
          'kind', 'flex_semester',
          'limit', v_limit,
          'counted', v_counted,
          'remaining', v_remaining,
          'baseRightCount', coalesce(v_plan.flex_base_right_count, 0)
        )
      );
    end if;

    semester_id := v_plan.semester_id;
    student_type := v_plan.student_type_snapshot::text;
    cancellation_limit := v_limit;
    counted_cancellations := v_counted;
    remaining_cancellations := v_remaining;
    buckets := v_buckets;

    return next;
  end loop;
end;
$function$;

revoke all on function public.get_student_cancellation_quotas(uuid)
from public;

grant execute on function public.get_student_cancellation_quotas(uuid)
to authenticated;

comment on function public.get_student_cancellation_quotas(uuid) is
  'Returns authoritative cancellation quota summaries using the same regular-slot and flex-semester buckets enforced by cancel_lesson().';
