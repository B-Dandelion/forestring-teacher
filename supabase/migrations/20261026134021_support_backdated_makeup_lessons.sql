-- Keep the existing management RPC contracts and student booking rules.
-- Only management-created standalone makeup lessons gain past-date support.
-- Existing lessons, cancellations and settled rights are never rebuilt here.
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
    and s.status = 'active'::public.student_status
  for update of s;

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

  -- Backdated records must belong to an actual enrollment period in the
  -- student's current branch. The student lock above serializes this check
  -- with withdrawal/reactivation and their enrollment-history trigger.
  if p_starts_at < pg_catalog.now()
     and not exists (
       select 1
       from public.student_enrollment_periods ep
       where ep.student_id = p_student_id
         and ep.branch_id = v_student_branch_id
         and ep.starts_on <= v_local_date
         and (ep.ends_on is null or ep.ends_on >= v_local_date)
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MAKEUP_OUTSIDE_ENROLLMENT';
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

  if p_duration_minutes not in (15, 30, 45, 60) then
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

revoke all on function public.create_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text
) from public, anon;
grant execute on function public.create_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text
) to authenticated;
create or replace function public.create_managed_makeup_lesson(
  p_student_id uuid,
  p_teacher_id uuid,
  p_starts_at timestamptz,
  p_duration_minutes integer,
  p_confirm_warnings boolean default false,
  p_reason text default null,
  p_deduct_lesson_right boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_result jsonb;
  v_lesson public.lessons%rowtype;
  v_semester_id uuid;
  v_right public.lesson_rights%rowtype;
  v_local_date date;
  v_plan_status public.student_semester_plan_status;
begin
  v_result := public.create_makeup_lesson(
    p_student_id,
    p_teacher_id,
    p_starts_at,
    p_duration_minutes,
    p_confirm_warnings,
    p_reason
  );

  if not coalesce(p_deduct_lesson_right, false)
     or coalesce((v_result ->> 'changed')::boolean, false) = false then
    return v_result || jsonb_build_object(
      'lessonRightDeducted', false,
      'lessonRightId', null
    );
  end if;

  select *
  into v_lesson
  from public.lessons l
  where l.id = (v_result ->> 'lessonId')::uuid
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_MAKEUP_LESSON_NOT_FOUND_AFTER_CREATE';
  end if;

  v_local_date := (v_lesson.starts_at at time zone 'Asia/Seoul')::date;

  select s.id
  into v_semester_id
  from public.semesters s
  left join public.branch_semester_overrides o
    on o.semester_id = s.id
   and o.branch_id = v_lesson.branch_id
  where v_local_date between coalesce(o.starts_on, s.starts_on)
                         and coalesce(o.ends_on, s.ends_on)
  order by coalesce(o.starts_on, s.starts_on)
  limit 1;

  if v_semester_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_SEMESTER_NOT_FOUND_FOR_DATE';
  end if;

  -- A historical record may be added without reopening a settled ledger.
  -- Lock the same plan row used by finalization before choosing a right.
  -- Transitions take that lock before the student lock held by lesson creation,
  -- so fail promptly instead of waiting in the reverse order and deadlocking.
  if v_lesson.starts_at < pg_catalog.now() then
    begin
      select sp.status
      into v_plan_status
      from public.student_semester_plans sp
      where sp.student_id = p_student_id
        and sp.semester_id = v_semester_id
        and sp.branch_id = v_lesson.branch_id
      for update nowait;
    exception when lock_not_available then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_STUDENT_SETTLEMENT_BUSY';
    end;

    if not found or v_plan_status not in (
      'planned'::public.student_semester_plan_status,
      'active'::public.student_semester_plan_status
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'FORESTRING_MAKEUP_DEDUCTION_PLAN_NOT_OPEN';
    end if;
  end if;

  select r.*
  into v_right
  from public.lesson_rights r
  where r.student_id = p_student_id
    and r.branch_id = v_lesson.branch_id
    and r.usable_semester_id = v_semester_id
    and r.status = 'available'::public.lesson_right_status
    and r.duration_minutes = p_duration_minutes
  order by
    case when r.origin = 'carryover'::public.lesson_right_origin then 0 else 1 end,
    case when exists (
      select 1
      from public.lesson_cancellation_events e
      where e.lesson_right_id = r.id
    ) then 0 else 1 end,
    (
      select min(e.canceled_at)
      from public.lesson_cancellation_events e
      where e.lesson_right_id = r.id
    ) asc nulls last,
    r.sequence_no,
    r.id
  limit 1
  for update;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_NO_MATCHING_AVAILABLE_LESSON_RIGHT';
  end if;

  update public.lessons
  set manual_makeup_right_id = v_right.id
  where id = v_lesson.id;

  update public.lesson_rights
  set
    status = 'consumed'::public.lesson_right_status,
    consumed_at = pg_catalog.now(),
    reserved_at = null
  where id = v_right.id;

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
    v_lesson.branch_id,
    v_semester_id,
    'MAKEUP_LESSON_RIGHT_DEDUCTED',
    v_local_date,
    v_actor_id,
    jsonb_build_object(
      'lessonId', v_lesson.id,
      'rightId', v_right.id,
      'rightOrigin', v_right.origin,
      'durationMinutes', v_right.duration_minutes
    )
  );

  return v_result || jsonb_build_object(
    'lessonRightDeducted', true,
    'lessonRightId', v_right.id
  );
end;
$$;

revoke all on function public.create_managed_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text, boolean
) from public, anon;
grant execute on function public.create_managed_makeup_lesson(
  uuid, uuid, timestamptz, integer, boolean, text, boolean
) to authenticated;

