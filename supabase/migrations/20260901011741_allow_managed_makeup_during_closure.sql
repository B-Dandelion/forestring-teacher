create or replace function public.create_makeup_lesson(
  p_student_id uuid,
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_confirm_warnings boolean default false,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_student_branch_id uuid;
  v_student_withdrawal_date date;
  v_teacher_withdrawal_date date;
  v_local_start timestamp;
  v_local_end timestamp;
  v_local_date date;
  v_ends_at timestamptz;
  v_inside_work_hours boolean := false;
  v_semester_id uuid;
  v_warning_codes text[] := array[]::text[];
  v_reason text;
  v_lesson public.lessons%rowtype;
begin
  if v_actor_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role
  into v_actor_role
  from public.profiles p
  where p.id = v_actor_id
    and p.is_active = true;

  if not found or v_actor_role not in (
    'master'::public.user_role,
    'manager'::public.user_role
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_MANAGEMENT_REQUIRED';
  end if;

  if p_student_id is null or p_teacher_id is null or p_starts_at is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MAKEUP_INPUT_REQUIRED';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then
    raise exception using errcode = 'P0001', message = 'FORESTRING_INVALID_LESSON_DURATION';
  end if;

  if p_starts_at < pg_catalog.now() then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MAKEUP_START_IN_PAST';
  end if;

  v_ends_at := p_starts_at + pg_catalog.make_interval(mins => p_duration_minutes);
  v_local_start := p_starts_at at time zone 'Asia/Seoul';
  v_local_end := v_ends_at at time zone 'Asia/Seoul';
  v_local_date := v_local_start::date;
  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  if v_local_start::date <> v_local_end::date then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MAKEUP_CROSSES_DAY';
  end if;

  select p.branch_id, s.withdrawal_date
  into v_student_branch_id, v_student_withdrawal_date
  from public.profiles p
  join public.students s on s.id = p.id
  where p.id = p_student_id
    and p.role = 'student'::public.user_role
    and p.is_active = true
    and s.status = 'active'::public.student_status;

  if not found or v_student_branch_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_withdrawal_date is not null
     and v_local_date >= v_student_withdrawal_date then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_AFTER_STUDENT_WITHDRAWAL';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_student_branch_id) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select t.withdrawal_date
  into v_teacher_withdrawal_date
  from public.profiles p
  join public.teachers t on t.id = p.id
  where p.id = p_teacher_id
    and p.is_active = true
    and p.branch_id = v_student_branch_id
    and p.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    );

  if not found then
    raise exception using errcode = 'P0001', message = 'FORESTRING_ACTIVE_TEACHER_REQUIRED';
  end if;

  if v_teacher_withdrawal_date is not null
     and v_local_date >= v_teacher_withdrawal_date then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_AFTER_TEACHER_WITHDRAWAL';
  end if;

  select s.id
  into v_semester_id
  from public.semesters s
  left join public.branch_semester_overrides o
    on o.semester_id = s.id
   and o.branch_id = v_student_branch_id
  where v_local_date between coalesce(o.starts_on, s.starts_on)
                         and coalesce(o.ends_on, s.ends_on)
  order by coalesce(o.starts_on, s.starts_on)
  limit 1;

  if v_semester_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_SEMESTER_NOT_FOUND_FOR_DATE';
  end if;

  -- Intentional policy: managed makeup/additional lessons may be created
  -- during branch closure periods. Access is still restricted above to
  -- master and manager actors, and managers remain limited to their branch.

  if exists (
    select 1
    from public.blocked_periods bp
    where bp.teacher_id = p_teacher_id
      and tstzrange(bp.starts_at, bp.ends_at, '[)')
          && tstzrange(p_starts_at, v_ends_at, '[)')
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_BLOCKED_PERIOD_CONFLICT';
  end if;

  if exists (
    select 1
    from public.lessons l
    where l.teacher_id = p_teacher_id
      and l.status = 'scheduled'::public.lesson_status
      and tstzrange(l.starts_at, l.ends_at, '[)')
          && tstzrange(p_starts_at, v_ends_at, '[)')
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_TEACHER_LESSON_OVERLAP';
  end if;

  if exists (
    select 1
    from public.lessons l
    where l.student_id = p_student_id
      and l.status = 'scheduled'::public.lesson_status
      and tstzrange(l.starts_at, l.ends_at, '[)')
          && tstzrange(p_starts_at, v_ends_at, '[)')
  ) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_STUDENT_LESSON_OVERLAP';
  end if;

  select exists (
    select 1
    from private.teacher_work_hours_for_date(p_teacher_id, v_local_start::date) wh
    where wh.teacher_id = p_teacher_id
      and wh.weekday = extract(isodow from v_local_start)::smallint
      and wh.start_time <= v_local_start::time
      and wh.end_time >= v_local_end::time
  )
  into v_inside_work_hours;

  if not v_inside_work_hours then
    v_warning_codes := array_append(v_warning_codes, 'FORESTRING_OUTSIDE_WORK_HOURS');
  end if;

  if p_duration_minutes not in (15, 30, 60) then
    v_warning_codes := array_append(v_warning_codes, 'FORESTRING_NONSTANDARD_DURATION');
  end if;

  if cardinality(v_warning_codes) > 0
     and not coalesce(p_confirm_warnings, false) then
    return jsonb_build_object(
      'changed', false,
      'requiresConfirmation', true,
      'warningCodes', to_jsonb(v_warning_codes),
      'proposedStartsAt', p_starts_at,
      'proposedEndsAt', v_ends_at,
      'proposedDurationMinutes', p_duration_minutes
    );
  end if;

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
    ) values (
      null,
      p_student_id,
      p_teacher_id,
      null,
      p_starts_at,
      p_duration_minutes,
      'makeup'::public.lesson_type,
      'scheduled'::public.lesson_status,
      null
    )
    returning * into v_lesson;
  exception
    when exclusion_violation then
      raise exception using errcode = 'P0001', message = 'FORESTRING_LESSON_TIME_CONFLICT';
  end;

  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    p_student_id,
    v_student_branch_id,
    v_semester_id,
    'MAKEUP_LESSON_CREATED',
    v_local_date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'teacherId', p_teacher_id,
      'startsAt', v_lesson.starts_at,
      'endsAt', v_lesson.ends_at,
      'durationMinutes', v_lesson.duration_minutes,
      'warningsOverridden', cardinality(v_warning_codes) > 0,
      'warningCodes', to_jsonb(v_warning_codes),
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'lessonId', v_lesson.id,
    'changed', true,
    'requiresConfirmation', false,
    'warningCodes', to_jsonb(v_warning_codes),
    'startsAt', v_lesson.starts_at,
    'endsAt', v_lesson.ends_at,
    'durationMinutes', v_lesson.duration_minutes
  );
end;
$function$;
