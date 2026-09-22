create or replace function public.migration_import_future_lessons_batch_20260825(
  p_actor_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_received integer;
  v_inserted integer;
  v_skipped_id integer;
  v_skipped_semantic integer;
  v_conflict jsonb;
begin
  if p_actor_id is null or not exists (
    select 1
    from public.profiles p
    where p.id = p_actor_id
      and p.role = 'master'::public.user_role
      and p.is_active = true
  ) then
    raise exception using errcode='P0001', message='FORESTRING_MIGRATION_MASTER_REQUIRED';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception using errcode='P0001', message='FORESTRING_MIGRATION_ROWS_REQUIRED';
  end if;

  v_received := jsonb_array_length(p_rows);
  if v_received < 1 or v_received > 100 then
    raise exception using errcode='P0001', message='FORESTRING_MIGRATION_BATCH_SIZE_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_rows) as x(
      id uuid,
      series_id uuid,
      student_id uuid,
      teacher_id uuid,
      occurrence_at timestamptz,
      starts_at timestamptz,
      duration_minutes integer,
      lesson_type text,
      status text,
      canceled_at timestamptz
    )
    where x.id is null
       or x.student_id is null
       or x.teacher_id is null
       or x.starts_at is null
       or x.starts_at < '2026-08-24 15:00:00+00'::timestamptz
       or x.starts_at >= '2027-01-01 00:00:00+00'::timestamptz
       or x.duration_minutes is null
       or x.duration_minutes <= 0
       or x.duration_minutes > 720
       or mod(x.duration_minutes, 15) <> 0
       or x.lesson_type not in ('regular','makeup')
       or x.status not in ('scheduled','canceled')
       or (x.lesson_type='regular' and (x.series_id is null or x.occurrence_at is null))
       or (x.lesson_type='makeup' and (x.series_id is not null or x.occurrence_at is not null))
       or (x.status='canceled' and x.canceled_at is null)
       or (x.status='scheduled' and x.canceled_at is not null)
  ) then
    raise exception using errcode='P0001', message='FORESTRING_MIGRATION_ROW_INVALID';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_rows) as x(
      series_id uuid,
      occurrence_at timestamptz,
      lesson_type text
    )
    where x.lesson_type='regular'
    group by x.series_id, x.occurrence_at
    having count(*) > 1
  ) then
    raise exception using errcode='P0001', message='FORESTRING_MIGRATION_DUPLICATE_OCCURRENCE_IN_BATCH';
  end if;

  with incoming as (
    select *
    from jsonb_to_recordset(p_rows) as x(
      id uuid,
      series_id uuid,
      student_id uuid,
      teacher_id uuid,
      occurrence_at timestamptz,
      starts_at timestamptz,
      duration_minutes integer,
      lesson_type text,
      status text,
      rescheduled_by uuid,
      canceled_by uuid,
      canceled_at timestamptz,
      cancellation_reason text,
      created_at timestamptz,
      updated_at timestamptz
    )
  ), matched as (
    select
      x.*,
      e.id as existing_id,
      e.series_id as existing_series_id,
      e.occurrence_at as existing_occurrence_at,
      e.student_id as existing_student_id,
      e.teacher_id as existing_teacher_id,
      e.starts_at as existing_starts_at,
      e.duration_minutes as existing_duration_minutes,
      e.lesson_type as existing_lesson_type,
      e.status as existing_status,
      e.rescheduled_by as existing_rescheduled_by,
      e.canceled_by as existing_canceled_by,
      e.canceled_at as existing_canceled_at,
      e.cancellation_reason as existing_cancellation_reason,
      e.lesson_right_id as existing_lesson_right_id,
      e.manual_makeup_right_id as existing_manual_makeup_right_id
    from incoming x
    join public.lessons e
      on e.id = x.id
      or (
        x.lesson_type='regular'
        and x.series_id is not null
        and e.series_id=x.series_id
        and e.occurrence_at=x.occurrence_at
      )
      or (
        x.lesson_type='makeup'
        and e.lesson_type='makeup'::public.lesson_type
        and e.student_id=x.student_id
        and e.teacher_id=x.teacher_id
        and e.starts_at=x.starts_at
      )
  ), conflicts as (
    select *
    from matched m
    where not (
      m.existing_student_id = m.student_id
      and m.existing_teacher_id = m.teacher_id
      and m.existing_series_id is not distinct from m.series_id
      and m.existing_occurrence_at is not distinct from m.occurrence_at
      and m.existing_starts_at = m.starts_at
      and m.existing_duration_minutes = m.duration_minutes
      and m.existing_lesson_type = m.lesson_type::public.lesson_type
      and m.existing_status = m.status::public.lesson_status
      and m.existing_rescheduled_by is not distinct from m.rescheduled_by
      and m.existing_canceled_by is not distinct from m.canceled_by
      and m.existing_canceled_at is not distinct from m.canceled_at
      and m.existing_cancellation_reason is not distinct from m.cancellation_reason
      and m.existing_lesson_right_id is null
      and m.existing_manual_makeup_right_id is null
    )
    limit 1
  )
  select jsonb_build_object(
    'incomingId', id,
    'existingId', existing_id,
    'lessonType', lesson_type,
    'startsAt', starts_at,
    'seriesId', series_id,
    'occurrenceAt', occurrence_at
  )
  into v_conflict
  from conflicts;

  if v_conflict is not null then
    raise exception using
      errcode='P0001',
      message='FORESTRING_MIGRATION_EXISTING_LESSON_MISMATCH',
      detail=v_conflict::text;
  end if;

  with incoming as (
    select *
    from jsonb_to_recordset(p_rows) as x(id uuid)
  )
  select count(*)::integer
  into v_skipped_id
  from incoming x
  where exists (select 1 from public.lessons e where e.id=x.id);

  with incoming as (
    select *
    from jsonb_to_recordset(p_rows) as x(
      id uuid,
      series_id uuid,
      student_id uuid,
      teacher_id uuid,
      occurrence_at timestamptz,
      starts_at timestamptz,
      duration_minutes integer,
      lesson_type text,
      status text,
      rescheduled_by uuid,
      canceled_by uuid,
      canceled_at timestamptz,
      cancellation_reason text
    )
  )
  select count(*)::integer
  into v_skipped_semantic
  from incoming x
  where not exists (select 1 from public.lessons e where e.id=x.id)
    and (
      (
        x.lesson_type='regular'
        and exists (
          select 1
          from public.lessons e
          where e.series_id=x.series_id
            and e.occurrence_at=x.occurrence_at
        )
      )
      or
      (
        x.lesson_type='makeup'
        and exists (
          select 1
          from public.lessons e
          where e.lesson_type='makeup'::public.lesson_type
            and e.student_id=x.student_id
            and e.teacher_id=x.teacher_id
            and e.starts_at=x.starts_at
            and e.duration_minutes=x.duration_minutes
            and e.status=x.status::public.lesson_status
            and e.rescheduled_by is not distinct from x.rescheduled_by
            and e.canceled_by is not distinct from x.canceled_by
            and e.canceled_at is not distinct from x.canceled_at
            and e.cancellation_reason is not distinct from x.cancellation_reason
            and e.lesson_right_id is null
            and e.manual_makeup_right_id is null
        )
      )
    );

  with incoming as (
    select *
    from jsonb_to_recordset(p_rows) as x(
      id uuid,
      series_id uuid,
      student_id uuid,
      teacher_id uuid,
      occurrence_at timestamptz,
      starts_at timestamptz,
      duration_minutes integer,
      lesson_type text,
      status text,
      rescheduled_by uuid,
      canceled_by uuid,
      canceled_at timestamptz,
      cancellation_reason text,
      created_at timestamptz,
      updated_at timestamptz
    )
  ), candidates as (
    select x.*
    from incoming x
    where not exists (select 1 from public.lessons e where e.id=x.id)
      and not (
        x.lesson_type='regular'
        and exists (
          select 1
          from public.lessons e
          where e.series_id=x.series_id
            and e.occurrence_at=x.occurrence_at
        )
      )
      and not (
        x.lesson_type='makeup'
        and exists (
          select 1
          from public.lessons e
          where e.lesson_type='makeup'::public.lesson_type
            and e.student_id=x.student_id
            and e.teacher_id=x.teacher_id
            and e.starts_at=x.starts_at
            and e.duration_minutes=x.duration_minutes
            and e.status=x.status::public.lesson_status
            and e.rescheduled_by is not distinct from x.rescheduled_by
            and e.canceled_by is not distinct from x.canceled_by
            and e.canceled_at is not distinct from x.canceled_at
            and e.cancellation_reason is not distinct from x.cancellation_reason
            and e.lesson_right_id is null
            and e.manual_makeup_right_id is null
        )
      )
  ), ins as (
    insert into public.lessons(
      id, series_id, student_id, teacher_id, occurrence_at, starts_at,
      duration_minutes, lesson_type, status, rescheduled_by, canceled_by,
      canceled_at, cancellation_reason, created_at, updated_at,
      lesson_right_id, manual_makeup_right_id
    )
    select
      x.id, x.series_id, x.student_id, x.teacher_id, x.occurrence_at, x.starts_at,
      x.duration_minutes, x.lesson_type::public.lesson_type, x.status::public.lesson_status,
      x.rescheduled_by, x.canceled_by, x.canceled_at, x.cancellation_reason,
      x.created_at, x.updated_at, null, null
    from candidates x
    on conflict(id) do nothing
    returning 1
  )
  select count(*)::integer into v_inserted from ins;

  return jsonb_build_object(
    'received', v_received,
    'inserted', v_inserted,
    'skippedExistingId', v_skipped_id,
    'skippedSemantic', v_skipped_semantic
  );
end;
$function$;

revoke all on function public.migration_import_future_lessons_batch_20260825(uuid,jsonb) from public;
revoke all on function public.migration_import_future_lessons_batch_20260825(uuid,jsonb) from anon;
revoke all on function public.migration_import_future_lessons_batch_20260825(uuid,jsonb) from authenticated;
grant execute on function public.migration_import_future_lessons_batch_20260825(uuid,jsonb) to service_role;
