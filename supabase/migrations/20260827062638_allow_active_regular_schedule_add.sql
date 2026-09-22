create or replace function public.add_regular_schedule(
  p_student_id uuid,
  p_teacher_id uuid,
  p_weekday smallint,
  p_start_time time without time zone,
  p_duration_minutes integer,
  p_effective_on date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;

  v_student_branch_id uuid;
  v_student_active boolean;
  v_student_status public.student_status;
  v_student_type public.student_type;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_semester_id uuid;
  v_semester_end date;
  v_target_plan_id uuid;
  v_target_plan_type public.student_type;
  v_target_plan_status public.student_semester_plan_status;

  v_end_time time;
  v_slot_id uuid;
  v_series_id uuid;

  v_candidate_count integer := 0;
  v_created_right_count integer := 0;
  v_created_lesson_count integer := 0;
  v_candidate record;
  v_right_id uuid;
begin
  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found
     or v_actor_role not in (
       'master'::public.user_role,
       'manager'::public.user_role
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_weekday not between 1 and 7 then
    raise exception using errcode = 'P0001', message = 'FORESTRING_INVALID_WEEKDAY';
  end if;

  if p_start_time is null
     or extract(second from p_start_time) <> 0
     or mod(extract(minute from p_start_time)::integer, 15) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_INVALID_REGULAR_DURATION';
  end if;

  if extract(hour from p_start_time)::integer * 60
       + extract(minute from p_start_time)::integer
       + p_duration_minutes > 1440 then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_LESSON_CROSSES_MIDNIGHT';
  end if;

  v_end_time := (
    p_start_time + pg_catalog.make_interval(mins => p_duration_minutes)
  )::time;

  select p.branch_id, p.is_active, s.status, s.student_type
  into v_student_branch_id, v_student_active, v_student_status, v_student_type
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = p_student_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true
     or v_student_status <> 'active'::public.student_status then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'regular'::public.student_type then
    raise exception using errcode = 'P0001', message = 'FORESTRING_REGULAR_STUDENT_REQUIRED';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.branch_id, p.is_active, t.withdrawal_date
  into v_teacher_branch_id, v_teacher_active, v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id = t.id
  where t.id = p_teacher_id;

  if not found or v_teacher_active <> true then
    raise exception using errcode = 'P0001', message = 'FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using errcode = 'P0001', message = 'FORESTRING_BRANCH_MISMATCH';
  end if;

  select s.id, bounds.ends_on
  into v_semester_id, v_semester_end
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(
    v_student_branch_id,
    s.id
  ) bounds
  where bounds.starts_on = p_effective_on
  order by s.starts_on
  limit 1;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_ADD_REQUIRES_SEMESTER_START';
  end if;

  if v_teacher_withdrawal_date is not null
     and v_teacher_withdrawal_date <= v_semester_end then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if not exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id = p_student_id
      and a.teacher_id = p_teacher_id
      and a.branch_id = v_student_branch_id
      and a.starts_on <= p_effective_on
      and (a.ends_on is null or a.ends_on >= v_semester_end)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH';
  end if;

  if not exists (
    select 1
    from public.teacher_work_hours wh
    where wh.teacher_id = p_teacher_id
      and wh.weekday = p_weekday
      and wh.start_time <= p_start_time
      and wh.end_time >= v_end_time
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS';
  end if;

  select sp.id, sp.student_type_snapshot, sp.status
  into v_target_plan_id, v_target_plan_type, v_target_plan_status
  from public.student_semester_plans sp
  where sp.student_id = p_student_id
    and sp.semester_id = v_semester_id
  for update;

  if found then
    if v_target_plan_type <> 'regular'::public.student_type then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_TARGET_SEMESTER_NOT_REGULAR';
    end if;

    if v_target_plan_status = 'completed'::public.student_semester_plan_status then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_COMPLETED_PLAN_IMMUTABLE';
    end if;
  end if;

  insert into public.regular_schedule_slots (
    student_id,
    branch_id,
    starts_on,
    ends_on,
    created_by
  )
  values (
    p_student_id,
    v_student_branch_id,
    p_effective_on,
    null,
    v_actor_id
  )
  returning id into v_slot_id;

  begin
    insert into public.lesson_series (
      student_id,
      teacher_id,
      weekday,
      start_time,
      duration_minutes,
      effective_from,
      effective_until,
      branch_id,
      schedule_slot_id
    )
    values (
      p_student_id,
      p_teacher_id,
      p_weekday,
      p_start_time,
      p_duration_minutes,
      p_effective_on,
      null,
      v_student_branch_id,
      v_slot_id
    )
    returning id into v_series_id;
  exception
    when exclusion_violation then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_SERIES_TIME_CONFLICT';
  end;

  if v_target_plan_status = 'active'::public.student_semester_plan_status then
    select count(*)::integer
    into v_candidate_count
    from generate_series(
      p_effective_on::timestamp,
      v_semester_end::timestamp,
      interval '1 day'
    ) d
    where extract(isodow from d)::integer = p_weekday
      and not exists (
        select 1
        from public.closure_periods cp
        where cp.branch_id = v_student_branch_id
          and cp.semester_id = v_semester_id
          and cp.closure_kind = 'instructional_break'::public.closure_kind
          and d::date between cp.starts_on and cp.ends_on
      );

    if v_candidate_count <> 4 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES',
        detail = 'schedule_slot_id=' || v_slot_id::text || ', candidate_count=' || v_candidate_count::text;
    end if;

    for v_candidate in
      with candidate_dates as (
        select d::date as lesson_date
        from generate_series(
          p_effective_on::timestamp,
          v_semester_end::timestamp,
          interval '1 day'
        ) d
        where extract(isodow from d)::integer = p_weekday
          and not exists (
            select 1
            from public.closure_periods cp
            where cp.branch_id = v_student_branch_id
              and cp.semester_id = v_semester_id
              and cp.closure_kind = 'instructional_break'::public.closure_kind
              and d::date between cp.starts_on and cp.ends_on
          )
      )
      select
        row_number() over(order by cd.lesson_date)::integer as sequence_no,
        cd.lesson_date,
        (cd.lesson_date + p_start_time) at time zone 'Asia/Seoul' as starts_at,
        ((cd.lesson_date + p_start_time) at time zone 'Asia/Seoul')
          + pg_catalog.make_interval(mins => p_duration_minutes) as ends_at
      from candidate_dates cd
      order by cd.lesson_date
    loop
      if exists (
        select 1
        from public.closure_periods cp
        where cp.branch_id = v_student_branch_id
          and cp.semester_id = v_semester_id
          and cp.closure_kind = 'ordinary'::public.closure_kind
          and v_candidate.lesson_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE';
      end if;

      if exists (
        select 1
        from public.blocked_periods bp
        where bp.teacher_id = p_teacher_id
          and tstzrange(bp.starts_at, bp.ends_at, '[)')
              && tstzrange(v_candidate.starts_at, v_candidate.ends_at, '[)')
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'FORESTRING_REGULAR_OCCURRENCE_BLOCKED',
          detail = 'schedule_slot_id=' || v_slot_id::text || ', date=' || v_candidate.lesson_date::text;
      end if;

      insert into public.lesson_rights (
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
        reserved_at
      )
      values (
        p_student_id,
        v_student_branch_id,
        v_semester_id,
        v_semester_id,
        v_slot_id,
        null,
        'regular_base'::public.lesson_right_origin,
        v_candidate.sequence_no,
        p_duration_minutes,
        'reserved'::public.lesson_right_status,
        0,
        v_actor_id,
        pg_catalog.now()
      )
      returning id into v_right_id;

      v_created_right_count := v_created_right_count + 1;

      begin
        insert into public.lessons (
          series_id,
          student_id,
          teacher_id,
          occurrence_at,
          starts_at,
          duration_minutes,
          lesson_type,
          status,
          lesson_right_id
        )
        values (
          v_series_id,
          p_student_id,
          p_teacher_id,
          v_candidate.starts_at,
          v_candidate.starts_at,
          p_duration_minutes,
          'regular'::public.lesson_type,
          'scheduled'::public.lesson_status,
          v_right_id
        );
      exception
        when exclusion_violation then
          raise exception using
            errcode = 'P0001',
            message = 'FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT',
            detail = 'schedule_slot_id=' || v_slot_id::text || ', starts_at=' || v_candidate.starts_at::text;
      end;

      v_created_lesson_count := v_created_lesson_count + 1;
    end loop;

    if v_created_right_count <> 4 or v_created_lesson_count <> 4 then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_REGULAR_MATERIALIZATION_COUNT_MISMATCH';
    end if;
  end if;

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
    p_student_id,
    v_student_branch_id,
    v_semester_id,
    'REGULAR_SCHEDULE_ADDED',
    p_effective_on,
    v_actor_id,
    jsonb_build_object(
      'scheduleSlotId', v_slot_id,
      'seriesId', v_series_id,
      'teacherId', p_teacher_id,
      'weekday', p_weekday,
      'startTime', p_start_time,
      'durationMinutes', p_duration_minutes,
      'planId', v_target_plan_id,
      'planStatus', v_target_plan_status,
      'materializedImmediately', v_target_plan_status = 'active'::public.student_semester_plan_status,
      'rightCount', v_created_right_count,
      'lessonCount', v_created_lesson_count
    )
  );

  return jsonb_build_object(
    'changed', true,
    'scheduleSlotId', v_slot_id,
    'seriesId', v_series_id,
    'semesterId', v_semester_id,
    'effectiveOn', p_effective_on,
    'teacherId', p_teacher_id,
    'weekday', p_weekday,
    'startTime', p_start_time,
    'durationMinutes', p_duration_minutes,
    'planStatus', v_target_plan_status,
    'materializedImmediately', v_target_plan_status = 'active'::public.student_semester_plan_status,
    'rightCount', v_created_right_count,
    'lessonCount', v_created_lesson_count
  );
end;
$function$;

revoke all on function public.add_regular_schedule(uuid, uuid, smallint, time without time zone, integer, date) from public, anon;
grant execute on function public.add_regular_schedule(uuid, uuid, smallint, time without time zone, integer, date) to authenticated, service_role;
