-- Reconstruct a historical Production function that existed before
-- 20260907131340_make_regular_schedule_change_closure_aware.sql but was never
-- captured in the recorded migration history.
--
-- This definition is reconstructed from the current Production function by
-- reversing only the exact transformations performed by migration
-- 20260907131340. That lets the original historical migration replay normally.
--
-- Production was inspected read-only; this migration changes Local/QA replay
-- only until explicitly promoted later.

CREATE OR REPLACE FUNCTION private.rematerialize_academy_canceled_regular_rights(p_change_event_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_event public.audit_events%rowtype;
  v_slot public.regular_schedule_slots%rowtype;
  v_series public.lesson_series%rowtype;
  v_teacher_id uuid;
  v_weekday integer;
  v_start_time time;
  v_duration integer;
  v_item record;
  v_sem_start date;
  v_sem_end date;
  v_target_ordinal integer;
  v_base_ordinal integer;
  v_pre_rank integer;
  v_new_date date;
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_count integer := 0;
begin
  select * into v_event
  from public.audit_events
  where id = p_change_event_id
    and event_type = 'REGULAR_SCHEDULE_CHANGED';
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_CHANGE_EVENT_NOT_FOUND';
  end if;

  select * into v_slot
  from public.regular_schedule_slots
  where id = (v_event.details->>'scheduleSlotId')::uuid;
  if not found or v_slot.student_id <> v_event.subject_profile_id then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_CHANGE_EVENT_SLOT_MISMATCH';
  end if;

  select * into v_series
  from public.lesson_series
  where id = (v_event.details->>'newSeriesId')::uuid
    and schedule_slot_id = v_slot.id;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_CHANGE_EVENT_SERIES_NOT_FOUND';
  end if;

  v_teacher_id := (v_event.details->'after'->>'teacherId')::uuid;
  v_weekday := (v_event.details->'after'->>'weekday')::integer;
  v_start_time := (v_event.details->'after'->>'startTime')::time;
  v_duration := (v_event.details->'after'->>'durationMinutes')::integer;

  for v_item in
    select r.id right_id, r.source_semester_id, l.id lesson_id,
           l.occurrence_at, l.starts_at previous_starts_at,
           ce.id cancellation_event_id
    from public.lesson_rights r
    join public.lessons l on l.lesson_right_id = r.id
    join lateral (
      select e.id, e.origin, e.counts_toward_limit
      from public.lesson_cancellation_events e
      where e.lesson_right_id = r.id
      order by e.canceled_at desc, e.created_at desc, e.id desc
      limit 1
    ) ce on true
    where r.student_id = v_slot.student_id
      and r.branch_id = v_slot.branch_id
      and r.schedule_slot_id = v_slot.id
      and r.origin = 'regular_base'::public.lesson_right_origin
      and ce.origin = 'academy'::public.lesson_cancellation_origin
      and ce.counts_toward_limit = false
      and l.lesson_type = 'regular'::public.lesson_type
      and l.occurrence_at is not null
      and (
        (r.status='available'::public.lesson_right_status and l.status='canceled'::public.lesson_status)
        or
        (r.status='reserved'::public.lesson_right_status and l.status='scheduled'::public.lesson_status and l.rescheduled_by is null)
      )
      and not exists (
        select 1 from public.audit_events done
        where done.event_type='REGULAR_ACADEMY_CANCELED_RIGHT_REMATERIALIZED'
          and done.details->>'changeEventId'=p_change_event_id::text
          and done.details->>'rightId'=r.id::text
      )
    order by r.source_semester_id, l.occurrence_at, l.id
  loop
    select e.starts_on, e.ends_on into v_sem_start, v_sem_end
    from private.get_effective_semester_bounds(v_slot.branch_id, v_item.source_semester_id) e;
    if not found or v_sem_end < v_event.effective_on
       or v_sem_start > coalesce(v_series.effective_until, v_sem_end) then
      continue;
    end if;

    if (v_item.occurrence_at at time zone 'Asia/Seoul')::date >= v_event.effective_on then
      select count(*)::integer into v_target_ordinal
      from public.lessons pl
      join public.lesson_rights pr on pr.id=pl.lesson_right_id
      where pr.student_id=v_slot.student_id
        and pr.branch_id=v_slot.branch_id
        and pr.schedule_slot_id=v_slot.id
        and pr.origin='regular_base'::public.lesson_right_origin
        and pr.source_semester_id=v_item.source_semester_id
        and pl.lesson_type='regular'::public.lesson_type
        and pl.occurrence_at is not null
        and (pl.occurrence_at at time zone 'Asia/Seoul')::date >= v_event.effective_on
        and (pl.occurrence_at < v_item.occurrence_at
             or (pl.occurrence_at=v_item.occurrence_at and pl.id <= v_item.lesson_id));
    else
      select count(*)::integer into v_base_ordinal
      from public.lessons pl
      join public.lesson_rights pr on pr.id=pl.lesson_right_id
      where pr.student_id=v_slot.student_id
        and pr.branch_id=v_slot.branch_id
        and pr.schedule_slot_id=v_slot.id
        and pr.origin='regular_base'::public.lesson_right_origin
        and pr.source_semester_id=v_item.source_semester_id
        and pl.lesson_type='regular'::public.lesson_type
        and pl.occurrence_at is not null
        and (pl.occurrence_at at time zone 'Asia/Seoul')::date >= v_event.effective_on;

      select count(*)::integer into v_pre_rank
      from public.lesson_rights rr
      join public.lessons ll on ll.lesson_right_id=rr.id
      join lateral (
        select e.origin, e.counts_toward_limit
        from public.lesson_cancellation_events e
        where e.lesson_right_id=rr.id
        order by e.canceled_at desc, e.created_at desc, e.id desc
        limit 1
      ) latest on true
      where rr.student_id=v_slot.student_id
        and rr.branch_id=v_slot.branch_id
        and rr.schedule_slot_id=v_slot.id
        and rr.source_semester_id=v_item.source_semester_id
        and rr.origin='regular_base'::public.lesson_right_origin
        and latest.origin='academy'::public.lesson_cancellation_origin
        and latest.counts_toward_limit=false
        and ll.lesson_type='regular'::public.lesson_type
        and ll.occurrence_at is not null
        and (ll.occurrence_at at time zone 'Asia/Seoul')::date < v_event.effective_on
        and (ll.occurrence_at < v_item.occurrence_at
             or (ll.occurrence_at=v_item.occurrence_at and ll.id <= v_item.lesson_id));
      v_target_ordinal := v_base_ordinal + v_pre_rank;
    end if;

    select x.lesson_date into v_new_date
    from (
      select d::date lesson_date
      from pg_catalog.generate_series(
        greatest(v_sem_start, v_event.effective_on, v_slot.starts_on)::timestamp,
        least(v_sem_end, coalesce(v_series.effective_until,v_sem_end), coalesce(v_slot.ends_on,v_sem_end))::timestamp,
        interval '1 day'
      ) d
      where extract(isodow from d::date)::integer = v_weekday
        and not exists (
          select 1 from public.closure_periods cp
          where cp.branch_id=v_slot.branch_id
            and cp.semester_id=v_item.source_semester_id
            and cp.closure_kind='instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      order by d::date
      offset greatest(v_target_ordinal-1,0) limit 1
    ) x;
    if v_new_date is null then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_COUNT_MISMATCH';
    end if;

    v_new_start := (v_new_date + v_start_time) at time zone 'Asia/Seoul';
    v_new_end := v_new_start + pg_catalog.make_interval(mins=>v_duration);
    if v_new_start <= pg_catalog.now() then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_IN_PAST';
    end if;
    if exists (select 1 from public.closure_periods cp where cp.branch_id=v_slot.branch_id and cp.closure_kind='ordinary'::public.closure_kind and v_new_date between cp.starts_on and cp.ends_on) then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_ON_CLOSURE';
    end if;
    if exists (select 1 from public.blocked_periods bp where bp.teacher_id=v_teacher_id and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_new_start,v_new_end,'[)')) then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_BLOCKED';
    end if;
    if not exists (select 1 from public.teacher_student_assignments a where a.student_id=v_slot.student_id and a.teacher_id=v_teacher_id and a.branch_id=v_slot.branch_id and a.starts_on<=v_new_date and (a.ends_on is null or a.ends_on>=v_new_date)) then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_ASSIGNMENT_MISMATCH';
    end if;
    if not exists (select 1 from private.teacher_work_hours_for_date(v_teacher_id,v_new_date) wh where wh.weekday=v_weekday and wh.start_time<=v_start_time and wh.end_time>=(v_start_time+pg_catalog.make_interval(mins=>v_duration))::time) then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_OUTSIDE_WORK_HOURS';
    end if;

    update public.lesson_rights set status='reserved'::public.lesson_right_status, reserved_at=pg_catalog.now(), duration_minutes=v_duration where id=v_item.right_id;
    begin
      update public.lessons set teacher_id=v_teacher_id, starts_at=v_new_start, duration_minutes=v_duration, status='scheduled'::public.lesson_status, rescheduled_by=null, canceled_by=null, canceled_at=null, cancellation_reason=null where id=v_item.lesson_id;
    exception when exclusion_violation then
      raise exception using errcode='P0001', message='FORESTRING_ACADEMY_CANCELED_RIGHT_REMATERIALIZATION_TIME_CONFLICT';
    end;

    insert into public.audit_events(subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details)
    values(v_slot.student_id,v_slot.branch_id,v_item.source_semester_id,'REGULAR_ACADEMY_CANCELED_RIGHT_REMATERIALIZED',v_new_date,v_event.actor_id,
      jsonb_build_object('changeEventId',p_change_event_id,'scheduleSlotId',v_slot.id,'rightId',v_item.right_id,'lessonId',v_item.lesson_id,'latestCancellationEventId',v_item.cancellation_event_id,'previousStartsAt',v_item.previous_starts_at,'startsAt',v_new_start,'durationMinutes',v_duration,'executionSource','regular_schedule_change'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all
on function private.rematerialize_academy_canceled_regular_rights(uuid)
from public, anon, authenticated, service_role;

grant execute
on function private.rematerialize_academy_canceled_regular_rights(uuid)
to postgres;
