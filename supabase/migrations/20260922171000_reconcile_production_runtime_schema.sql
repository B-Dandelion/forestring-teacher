-- Reconcile Local QA schema with the current Production runtime schema.
-- Captured read-only on 2026-09-22 after clean migration replay showed that
-- Production had runtime function/trigger changes not fully represented by the
-- committed migration chain. No Production row data is included here.

-- private.after_regular_schedule_changed_rematerialize_academy_rights()
CREATE OR REPLACE FUNCTION private.after_regular_schedule_changed_rematerialize_academy_rights()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.rematerialize_academy_canceled_regular_rights(new.id);
  return new;
end;
$function$;

-- private.is_semester_open_now(p_branch_id uuid, p_semester_id uuid)
CREATE OR REPLACE FUNCTION private.is_semester_open_now(p_branch_id uuid, p_semester_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from private.get_effective_semester_bounds(
      p_branch_id,
      p_semester_id
    ) bounds
    where (pg_catalog.now() at time zone 'Asia/Seoul')::date
      between bounds.starts_on and bounds.ends_on
  );
$function$;

-- public.activate_student_semester_plan(p_plan_id uuid)
CREATE OR REPLACE FUNCTION public.activate_student_semester_plan(p_plan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_is_system boolean;
  v_plan public.student_semester_plans%rowtype;
  v_student_branch_id uuid;
  v_student_profile_active boolean;
  v_student_status public.student_status;
  v_withdrawal_date date;
  v_semester_start date;
  v_semester_end date;
  v_has_four_teaching_weeks boolean;
  v_slot record;
  v_candidate record;
  v_slot_count integer := 0;
  v_candidate_count integer := 0;
  v_expected_right_count integer := 0;
  v_existing_right_count integer := 0;
  v_existing_lesson_count integer := 0;
  v_created_right_count integer := 0;
  v_created_lesson_count integer := 0;
  v_right_id uuid;
  v_flex_result jsonb;
  v_plan_was_activated boolean := false;
begin
  select a.actor_id, a.actor_role, a.is_system
  into v_actor_id, v_actor_role, v_is_system
  from private.require_semester_automation_actor() a;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.id = p_plan_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_PLAN_NOT_FOUND';
  end if;

  if v_plan.status = 'completed'::public.student_semester_plan_status then
    raise exception using errcode='P0001', message='FORESTRING_COMPLETED_PLAN_IMMUTABLE';
  end if;

  if v_actor_role = 'manager'::public.user_role
     and not private.manager_has_branch(v_plan.branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.branch_id, p.is_active, s.status, s.withdrawal_date
  into v_student_branch_id, v_student_profile_active, v_student_status, v_withdrawal_date
  from public.students s
  join public.profiles p on p.id = s.id
  where s.id = v_plan.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if not v_student_profile_active or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_branch_id is distinct from v_plan.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_PLAN_BRANCH_MISMATCH';
  end if;

  select e.starts_on, e.ends_on
  into v_semester_start, v_semester_end
  from private.get_effective_semester_bounds(v_plan.branch_id, v_plan.semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  select s.has_four_teaching_weeks
  into v_has_four_teaching_weeks
  from private.get_semester_week_summary(v_plan.branch_id, v_plan.semester_id) s;

  if not coalesce(v_has_four_teaching_weeks, false) then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUR_TEACHING_WEEKS';
  end if;

  if v_plan.student_type_snapshot = 'flex'::public.student_type then
    if v_plan.flex_base_right_count is null or v_plan.flex_duration_minutes is null then
      raise exception using errcode='P0001', message='FORESTRING_FLEX_PLAN_CONFIGURATION_REQUIRED';
    end if;

    if v_plan.status = 'planned'::public.student_semester_plan_status then
      update public.student_semester_plans
      set status='active'::public.student_semester_plan_status,
          updated_by=v_actor_id
      where id=v_plan.id;
      v_plan_was_activated := true;
    end if;

    v_flex_result := public.materialize_flex_base_rights(v_plan.id);

    if v_plan_was_activated then
      insert into public.audit_events (
        subject_profile_id, branch_id, semester_id, event_type,
        effective_on, actor_id, details
      ) values (
        v_plan.student_id, v_plan.branch_id, v_plan.semester_id,
        'SEMESTER_PLAN_ACTIVATED', v_semester_start, v_actor_id,
        jsonb_build_object(
          'planId', v_plan.id,
          'studentType', 'flex',
          'baseRightCount', v_plan.flex_base_right_count,
          'durationMinutes', v_plan.flex_duration_minutes,
          'executionSource', case when v_is_system then 'system_cron' else 'staff' end
        )
      );
    end if;

    return jsonb_build_object(
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'studentType', 'flex',
      'changed', v_plan_was_activated,
      'materialization', v_flex_result
    );
  end if;

  if v_plan.student_type_snapshot <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_UNKNOWN_STUDENT_TYPE';
  end if;

  if v_withdrawal_date is not null then
    v_semester_end := least(v_semester_end, v_withdrawal_date - 1);
  end if;

  if v_semester_end < v_semester_start then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE_IN_SEMESTER';
  end if;

  select count(*)::integer into v_slot_count
  from public.regular_schedule_slots rs
  where rs.student_id = v_plan.student_id
    and rs.branch_id = v_plan.branch_id
    and rs.starts_on <= v_semester_end
    and (rs.ends_on is null or rs.ends_on >= v_semester_start);

  if v_slot_count = 0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_PLAN_REQUIRES_SCHEDULE_SLOT';
  end if;

  -- Count the actual remaining teaching occurrences. A student's first
  -- semester may begin after the semester boundary, so a slot can validly
  -- have fewer than four occurrences while the semester itself still has
  -- four teaching weeks.
  with teaching_dates as (
    select d::date as lesson_date
    from generate_series(v_semester_start::timestamp, v_semester_end::timestamp, interval '1 day') d
    where not exists (
      select 1 from public.closure_periods cp
      where cp.branch_id=v_plan.branch_id
        and cp.semester_id=v_plan.semester_id
        and cp.closure_kind='instructional_break'::public.closure_kind
        and d::date between cp.starts_on and cp.ends_on
    )
  ), candidate_rows as (
    select rs.id as schedule_slot_id, td.lesson_date, ls.id as series_id
    from public.regular_schedule_slots rs
    join teaching_dates td
      on td.lesson_date >= rs.starts_on
     and (rs.ends_on is null or td.lesson_date <= rs.ends_on)
    join public.lesson_series ls
      on ls.schedule_slot_id=rs.id
     and ls.student_id=v_plan.student_id
     and ls.branch_id=v_plan.branch_id
     and td.lesson_date >= ls.effective_from
     and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
     and extract(isodow from td.lesson_date)::integer=ls.weekday
    where rs.student_id=v_plan.student_id
      and rs.branch_id=v_plan.branch_id
      and rs.starts_on <= v_semester_end
      and (rs.ends_on is null or rs.ends_on >= v_semester_start)
  )
  select count(*)::integer into v_expected_right_count
  from candidate_rows;

  if v_expected_right_count = 0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_PLAN_HAS_NO_OCCURRENCES';
  end if;

  if v_plan.status = 'active'::public.student_semester_plan_status then
    select count(*)::integer into v_existing_right_count
    from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    select count(*)::integer into v_existing_lesson_count
    from public.lesson_rights r
    join public.lessons l on l.lesson_right_id=r.id
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    if v_existing_right_count <> v_expected_right_count
       or v_existing_lesson_count <> v_expected_right_count then
      raise exception using errcode='P0001', message='FORESTRING_ACTIVE_PLAN_MATERIALIZATION_INCOMPLETE';
    end if;

    return jsonb_build_object(
      'planId', v_plan.id,
      'studentId', v_plan.student_id,
      'studentType', 'regular',
      'changed', false,
      'slotCount', v_slot_count,
      'rightCount', v_existing_right_count,
      'lessonCount', v_existing_lesson_count
    );
  end if;

  if exists (
    select 1 from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.source_semester_id=v_plan.semester_id
      and r.origin='regular_base'::public.lesson_right_origin
  ) then
    raise exception using errcode='P0001', message='FORESTRING_PLANNED_REGULAR_PLAN_ALREADY_HAS_RIGHTS';
  end if;

  for v_slot in
    select rs.id, rs.student_id, rs.branch_id, rs.starts_on, rs.ends_on
    from public.regular_schedule_slots rs
    where rs.student_id=v_plan.student_id
      and rs.branch_id=v_plan.branch_id
      and rs.starts_on <= v_semester_end
      and (rs.ends_on is null or rs.ends_on >= v_semester_start)
    order by rs.starts_on, rs.id
  loop
    select count(*)::integer into v_candidate_count
    from (
      with teaching_dates as (
        select d::date as lesson_date
        from generate_series(v_semester_start::timestamp, v_semester_end::timestamp, interval '1 day') d
        where not exists (
          select 1 from public.closure_periods cp
          where cp.branch_id=v_plan.branch_id
            and cp.semester_id=v_plan.semester_id
            and cp.closure_kind='instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      )
      select td.lesson_date, ls.id as series_id
      from teaching_dates td
      join public.lesson_series ls
        on ls.schedule_slot_id=v_slot.id
       and ls.student_id=v_plan.student_id
       and ls.branch_id=v_plan.branch_id
       and td.lesson_date >= ls.effective_from
       and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
       and extract(isodow from td.lesson_date)::integer=ls.weekday
      where td.lesson_date >= v_slot.starts_on
        and (v_slot.ends_on is null or td.lesson_date <= v_slot.ends_on)
    ) candidate_rows;

    if v_candidate_count = 0 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_NO_OCCURRENCES',
        detail='schedule_slot_id='||v_slot.id::text;
    end if;

    if v_candidate_count > 4 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES',
        detail='schedule_slot_id='||v_slot.id::text||', candidate_count='||v_candidate_count::text;
    end if;

    for v_candidate in
      with teaching_dates as (
        select d::date as lesson_date
        from generate_series(v_semester_start::timestamp, v_semester_end::timestamp, interval '1 day') d
        where not exists (
          select 1 from public.closure_periods cp
          where cp.branch_id=v_plan.branch_id
            and cp.semester_id=v_plan.semester_id
            and cp.closure_kind='instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      ), raw_candidates as (
        select td.lesson_date, ls.id as series_id, ls.teacher_id,
               ls.weekday, ls.start_time, ls.duration_minutes,
               (td.lesson_date + ls.start_time) at time zone 'Asia/Seoul' as starts_at
        from teaching_dates td
        join public.lesson_series ls
          on ls.schedule_slot_id=v_slot.id
         and ls.student_id=v_plan.student_id
         and ls.branch_id=v_plan.branch_id
         and td.lesson_date >= ls.effective_from
         and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
         and extract(isodow from td.lesson_date)::integer=ls.weekday
        where td.lesson_date >= v_slot.starts_on
          and (v_slot.ends_on is null or td.lesson_date <= v_slot.ends_on)
      )
      select row_number() over(order by rc.starts_at, rc.series_id)::integer as sequence_no,
             rc.lesson_date, rc.series_id, rc.teacher_id, rc.weekday,
             rc.start_time, rc.duration_minutes, rc.starts_at,
             rc.starts_at + pg_catalog.make_interval(mins=>rc.duration_minutes) as ends_at
      from raw_candidates rc
      order by rc.starts_at, rc.series_id
    loop
      if v_candidate.duration_minutes <= 0
         or mod(v_candidate.duration_minutes,15) <> 0 then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SERIES_INVALID_DURATION';
      end if;

      if not exists (
        select 1 from private.teacher_work_hours_for_date(v_candidate.teacher_id, v_candidate.lesson_date) wh
        where wh.teacher_id=v_candidate.teacher_id
          and wh.weekday=v_candidate.weekday
          and wh.start_time <= v_candidate.start_time
          and wh.end_time >= (v_candidate.ends_at at time zone 'Asia/Seoul')::time
      ) then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',
          detail='schedule_slot_id='||v_slot.id::text||', date='||v_candidate.lesson_date::text;
      end if;

      if exists (
        select 1 from public.blocked_periods bp
        where bp.teacher_id=v_candidate.teacher_id
          and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_candidate.starts_at,v_candidate.ends_at,'[)')
      ) then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_BLOCKED',
          detail='schedule_slot_id='||v_slot.id::text||', date='||v_candidate.lesson_date::text;
      end if;

      insert into public.lesson_rights (
        student_id, branch_id, source_semester_id, usable_semester_id,
        schedule_slot_id, source_right_id, origin, sequence_no,
        duration_minutes, status, carryover_count, created_by, reserved_at
      ) values (
        v_plan.student_id, v_plan.branch_id, v_plan.semester_id, v_plan.semester_id,
        v_slot.id, null, 'regular_base'::public.lesson_right_origin, v_candidate.sequence_no,
        v_candidate.duration_minutes, 'reserved'::public.lesson_right_status, 0, v_actor_id, pg_catalog.now()
      ) returning id into v_right_id;

      v_created_right_count := v_created_right_count + 1;

      begin
        insert into public.lessons (
          series_id, student_id, teacher_id, occurrence_at, starts_at,
          duration_minutes, lesson_type, status, lesson_right_id
        ) values (
          v_candidate.series_id, v_plan.student_id, v_candidate.teacher_id,
          v_candidate.starts_at, v_candidate.starts_at, v_candidate.duration_minutes,
          'regular'::public.lesson_type, 'scheduled'::public.lesson_status, v_right_id
        );
      exception when exclusion_violation then
        raise exception using
          errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT',
          detail='schedule_slot_id='||v_slot.id::text||', starts_at='||v_candidate.starts_at::text;
      end;

      v_created_lesson_count := v_created_lesson_count + 1;
    end loop;
  end loop;

  if v_created_right_count <> v_expected_right_count
     or v_created_lesson_count <> v_expected_right_count then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_COUNT_MISMATCH';
  end if;

  update public.student_semester_plans
  set status='active'::public.student_semester_plan_status,
      updated_by=v_actor_id
  where id=v_plan.id;

  insert into public.audit_events (
    subject_profile_id, branch_id, semester_id, event_type,
    effective_on, actor_id, details
  ) values (
    v_plan.student_id, v_plan.branch_id, v_plan.semester_id,
    'SEMESTER_PLAN_ACTIVATED', v_semester_start, v_actor_id,
    jsonb_build_object(
      'planId', v_plan.id,
      'studentType', 'regular',
      'slotCount', v_slot_count,
      'rightCount', v_created_right_count,
      'lessonCount', v_created_lesson_count,
      'executionSource', case when v_is_system then 'system_cron' else 'staff' end
    )
  );

  return jsonb_build_object(
    'planId', v_plan.id,
    'studentId', v_plan.student_id,
    'studentType', 'regular',
    'changed', true,
    'slotCount', v_slot_count,
    'rightCount', v_created_right_count,
    'lessonCount', v_created_lesson_count
  );
end;
$function$;

-- public.admin_create_review_account_data(p_profile_id uuid, p_display_name text, p_login_name_normalized text, p_pin_hash text, p_pin_fingerprint text)
CREATE OR REPLACE FUNCTION public.admin_create_review_account_data(p_profile_id uuid, p_display_name text, p_login_name_normalized text, p_pin_hash text, p_pin_fingerprint text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_profile_id is null then
    raise exception using errcode = 'P0001', message = 'FORESTRING_PROFILE_ID_REQUIRED';
  end if;

  if p_display_name is null
     or length(btrim(p_display_name)) = 0
     or length(p_display_name) > 100 then
    raise exception using errcode = 'P0001', message = 'FORESTRING_INVALID_DISPLAY_NAME';
  end if;

  if p_login_name_normalized is null
     or length(btrim(p_login_name_normalized)) = 0
     or p_login_name_normalized <> btrim(p_login_name_normalized) then
    raise exception using errcode = 'P0001', message = 'FORESTRING_INVALID_LOGIN_NAME';
  end if;

  insert into public.profiles (
    id,
    display_name,
    role,
    branch_id,
    is_active,
    is_review_account
  ) values (
    p_profile_id,
    btrim(p_display_name),
    'student'::public.user_role,
    null,
    true,
    true
  );

  perform public.auth_upsert_login_credential(
    p_profile_id,
    p_login_name_normalized,
    p_pin_hash,
    p_pin_fingerprint
  );

  return p_profile_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'FORESTRING_NAME_PIN_ALREADY_IN_USE';
end;
$function$;

-- public.assert_lesson_before_student_withdrawal()
CREATE OR REPLACE FUNCTION public.assert_lesson_before_student_withdrawal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_student_status public.student_status;
  v_withdrawal_date date;
  v_withdrawal_cutoff timestamptz;
  v_archive_import boolean := false;
begin
  if new.status <> 'scheduled'::public.lesson_status then
    return new;
  end if;

  select s.status, s.withdrawal_date
  into v_student_status, v_withdrawal_date
  from public.students s
  where s.id = new.student_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  v_archive_import :=
    session_user = 'postgres'
    and pg_catalog.current_setting('forestring.archive_import', true) = 'on';

  if v_student_status <> 'active'::public.student_status
     and not v_archive_import then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_ACTIVE';
  end if;

  if v_withdrawal_date is null then
    return new;
  end if;

  v_withdrawal_cutoff := (v_withdrawal_date::timestamp at time zone 'Asia/Seoul');

  if new.starts_at >= v_withdrawal_cutoff then
    raise exception using errcode='P0001', message='FORESTRING_LESSON_ON_OR_AFTER_WITHDRAWAL';
  end if;

  return new;
end;
$function$;

-- public.auth_lookup_login_credential(p_login_name_normalized text, p_pin_fingerprint text)
CREATE OR REPLACE FUNCTION public.auth_lookup_login_credential(p_login_name_normalized text, p_pin_fingerprint text)
 RETURNS TABLE(profile_id uuid, pin_hash text, role user_role, is_active boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    c.profile_id,
    c.pin_hash,
    p.role,
    case
      when p.is_review_account = true then p.is_active
      else private.profile_has_effective_access(c.profile_id)
    end as is_active
  from private.login_credentials c
  join public.profiles p
    on p.id = c.profile_id
  where c.login_name_normalized = p_login_name_normalized
    and c.pin_fingerprint = p_pin_fingerprint
  limit 1;
$function$;

-- public.book_lesson_right(p_right_id uuid, p_new_starts_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.book_lesson_right(p_right_id uuid, p_new_starts_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;

  v_actor_branch_id uuid;

  v_right public.lesson_rights%rowtype;

  v_selected_date date;

  v_teacher_id uuid;

  v_existing_lesson public.lessons%rowtype;

  v_lesson public.lessons%rowtype;

  v_series_schedule_slot_id uuid;

  v_reused_lesson boolean := false;

  v_is_regular_rebooking boolean := false;
begin

  -- ==========================================================
  -- 1. AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';
  end if;


  perform private.require_effective_actor(
    v_actor_id
  );


  select p.branch_id
  into v_actor_branch_id

  from public.profiles p

  join public.students s
    on s.id = p.id

  where p.id =
        v_actor_id

    and p.is_active = true

    and p.role =
        'student'::public.user_role

    and s.status =
        'active'::public.student_status;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;


  -- ==========================================================
  -- 2. LOCK RIGHT
  --
  -- Prevent two requests from using the same entitlement.
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        p_right_id

  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';
  end if;


  if v_right.student_id <>
     v_actor_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_FORBIDDEN';
  end if;


  if v_right.branch_id is distinct from
     v_actor_branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_BRANCH_MISMATCH';
  end if;


  if v_right.status <>
     'available'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE';
  end if;


  if v_right.origin not in (
    'regular_base'::public.lesson_right_origin,
    'flex_base'::public.lesson_right_origin,
    'carryover'::public.lesson_right_origin
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_UNSUPPORTED_LESSON_RIGHT_ORIGIN';
  end if;


  if not private.is_semester_open_now(
    v_right.branch_id,
    v_right.usable_semester_id
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_SEMESTER_NOT_OPEN';

  end if;


  -- ==========================================================
  -- 3. INPUT
  -- ==========================================================

  if p_new_starts_at is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_START_REQUIRED';

  end if;


  v_selected_date :=
    (
      p_new_starts_at
      at time zone 'Asia/Seoul'
    )::date;


  -- ==========================================================
  -- 4. RE-CHECK AUTHORITATIVE AVAILABILITY
  --
  -- Flutter may have displayed this slot earlier.
  -- The server checks it again at booking time.
  --
  -- Teacher and duration are never trusted from Flutter.
  -- ==========================================================

  select candidate.teacher_id
  into v_teacher_id

  from private.lesson_right_slot_candidates(
    v_right.id,
    v_selected_date,
    v_actor_id
  ) candidate

  where candidate.starts_at =
        p_new_starts_at

  limit 1;


  if v_teacher_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_SLOT_NOT_AVAILABLE';

  end if;


  -- ==========================================================
  -- 5. FIND EXISTING CANONICAL LESSON
  --
  -- lessons.lesson_right_id has a unique index, so there may
  -- be at most one lesson for this entitlement.
  -- ==========================================================

  select *
  into v_existing_lesson

  from public.lessons l

  where l.lesson_right_id =
        v_right.id

  for update;


  -- ==========================================================
  -- 6. REGULAR REBOOKING
  --
  -- A regular right was materialized together with its
  -- canonical regular lesson.
  --
  -- Therefore:
  --   existing lesson is REQUIRED
  --   existing lesson must be CANCELED
  --
  -- We never create a second regular lesson here.
  -- ==========================================================

  if v_right.origin =
     'regular_base'::public.lesson_right_origin then

    if not found then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_LESSON_REQUIRED';

    end if;


    if v_existing_lesson.status <>
       'canceled'::public.lesson_status then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_RIGHT_LINK_STATE_INVALID';

    end if;


    if v_existing_lesson.lesson_type <>
       'regular'::public.lesson_type then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_RIGHT_LESSON_TYPE_MISMATCH';

    end if;


    if v_existing_lesson.series_id is null
       or
       v_existing_lesson.occurrence_at is null then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_LESSON_IDENTITY_INVALID';

    end if;


    -- Extra defensive integrity:
    -- the historical series must belong to the same logical
    -- regular schedule slot as the entitlement.
    select ls.schedule_slot_id
    into v_series_schedule_slot_id

    from public.lesson_series ls

    where ls.id =
          v_existing_lesson.series_id;


    if not found then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_SERIES_NOT_FOUND';

    end if;


    if v_series_schedule_slot_id is distinct from
       v_right.schedule_slot_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_REGULAR_SERIES_SLOT_MISMATCH';

    end if;


    v_reused_lesson :=
      true;

    v_is_regular_rebooking :=
      true;


    begin

      update public.lessons
      set
        -- Actual teacher comes from the assignment effective
        -- on the SELECTED booking date.
        teacher_id =
          v_teacher_id,

        -- Actual appointment moves.
        starts_at =
          p_new_starts_at,

        -- Cancellation restores entitlement duration.
        --
        -- Example:
        -- right = 30
        -- privileged one-off edit made actual lesson = 60
        -- cancel
        -- rebook
        -- actual lesson returns to 30.
        duration_minutes =
          v_right.duration_minutes,

        status =
          'scheduled'::public.lesson_status,

        rescheduled_by =
          v_actor_id,

        canceled_by =
          null,

        canceled_at =
          null,

        cancellation_reason =
          null

      where id =
            v_existing_lesson.id

      returning *
      into v_lesson;


    exception
      when exclusion_violation then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_BOOKING_SLOT_TAKEN';

    end;


  -- ==========================================================
  -- 7. FLEX / CARRYOVER
  -- ==========================================================

  else

    if found then

      if v_existing_lesson.status <>
         'canceled'::public.lesson_status then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_LESSON_RIGHT_LINK_STATE_INVALID';

      end if;


      if v_existing_lesson.lesson_type <>
         'flex'::public.lesson_type then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_LESSON_RIGHT_LINK_TYPE_INVALID';

      end if;


      v_reused_lesson :=
        true;


      begin

        update public.lessons
        set
          teacher_id =
            v_teacher_id,

          starts_at =
            p_new_starts_at,

          duration_minutes =
            v_right.duration_minutes,

          status =
            'scheduled'::public.lesson_status,

          rescheduled_by =
            v_actor_id,

          canceled_by =
            null,

          canceled_at =
            null,

          cancellation_reason =
            null

        where id =
              v_existing_lesson.id

        returning *
        into v_lesson;


      exception
        when exclusion_violation then

          raise exception using
            errcode = 'P0001',
            message =
              'FORESTRING_BOOKING_SLOT_TAKEN';

      end;


    else

      -- Initial flex/carryover booking.
      begin

        insert into public.lessons (
          student_id,
          teacher_id,
          starts_at,
          duration_minutes,
          lesson_type,
          status,
          lesson_right_id
        )
        values (
          v_right.student_id,
          v_teacher_id,
          p_new_starts_at,
          v_right.duration_minutes,
          'flex'::public.lesson_type,
          'scheduled'::public.lesson_status,
          v_right.id
        )

        returning *
        into v_lesson;


      exception
        when exclusion_violation then

          raise exception using
            errcode = 'P0001',
            message =
              'FORESTRING_BOOKING_SLOT_TAKEN';

      end;

    end if;

  end if;


  -- ==========================================================
  -- 8. RESERVE SAME RIGHT
  -- ==========================================================

  update public.lesson_rights
  set
    status =
      'reserved'::public.lesson_right_status,

    reserved_at =
      pg_catalog.now()

  where id =
        v_right.id;


  -- ==========================================================
  -- 9. AUDIT
  -- ==========================================================

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
    v_right.student_id,
    v_right.branch_id,
    v_right.usable_semester_id,
    'LESSON_RIGHT_BOOKED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'rightId',
        v_right.id,

      'lessonId',
        v_lesson.id,

      'rightOrigin',
        v_right.origin,

      'lessonType',
        v_lesson.lesson_type,

      'teacherId',
        v_teacher_id,

      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_right.duration_minutes,

      'reusedLesson',
        v_reused_lesson,

      'regularRebooking',
        v_is_regular_rebooking,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at
    )
  );


  -- ==========================================================
  -- 10. RESULT
  -- ==========================================================

  return jsonb_build_object(
    'rightId',
      v_right.id,

    'lessonId',
      v_lesson.id,

    'teacherId',
      v_teacher_id,

    'startsAt',
      v_lesson.starts_at,

    'endsAt',
      v_lesson.ends_at,

    'durationMinutes',
      v_lesson.duration_minutes,

    'lessonType',
      v_lesson.lesson_type,

    'reusedLesson',
      v_reused_lesson,

    'regularRebooking',
      v_is_regular_rebooking,

    'seriesId',
      v_lesson.series_id,

    'occurrenceAt',
      v_lesson.occurrence_at,

    'rightStatus',
      'reserved'
  );

end;
$function$;

-- public.cancel_lesson(p_lesson_id uuid, p_reason text)
CREATE OR REPLACE FUNCTION public.cancel_lesson(p_lesson_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_actor_branch_id uuid;

  v_lesson public.lessons%rowtype;
  v_right public.lesson_rights%rowtype;

  v_origin public.lesson_cancellation_origin;

  v_reason text;

  v_counts_toward_limit boolean := false;

  v_cancellation_limit integer;
  v_count_before integer := 0;
  v_count_after integer := 0;
  v_remaining integer;

  v_flex_base_count integer;

  v_event_id uuid;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';

  end if;


  perform private.require_effective_actor(
    v_actor_id
  );


  select
    p.role,
    p.branch_id

  into
    v_actor_role,
    v_actor_branch_id

  from public.profiles p

  where p.id =
        v_actor_id

    and p.is_active = true;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_USER_REQUIRED';

  end if;


  v_reason :=
    nullif(
      btrim(
        coalesce(
          p_reason,
          ''
        )
      ),
      ''
    );


  -- ==========================================================
  -- LOCK LESSON
  -- ==========================================================

  select *
  into v_lesson

  from public.lessons l

  where l.id =
        p_lesson_id

  for update;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_NOT_FOUND';

  end if;


  if v_lesson.status <>
     'scheduled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_NOT_SCHEDULED';

  end if;


  -- Production rights-based cancellation applies only to
  -- canonical entitled lessons.
  if v_lesson.lesson_right_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_REQUIRED';

  end if;


  -- ==========================================================
  -- LOCK RIGHT
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        v_lesson.lesson_right_id

  for update;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';

  end if;


  if v_right.student_id <>
       v_lesson.student_id
     or
     v_right.branch_id <>
       v_lesson.branch_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_IDENTITY_MISMATCH';

  end if;


  if v_right.status <>
     'reserved'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_RESERVED';

  end if;


  -- ==========================================================
  -- ACTOR / ORIGIN
  -- ==========================================================

  if v_actor_role =
     'student'::public.user_role then

    if v_lesson.student_id <>
       v_actor_id then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_FORBIDDEN';

    end if;


    if not private.is_semester_open_now(
      v_right.branch_id,
      v_right.usable_semester_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_STUDENT_SEMESTER_NOT_OPEN';

    end if;


    -- Student self-service cancellation cutoff.
    if v_lesson.starts_at <
       pg_catalog.now()
       + interval '5 hours' then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_CANCELLATION_TOO_LATE';

    end if;


    v_origin :=
      'student'::public.lesson_cancellation_origin;


  elsif v_actor_role =
        'master'::public.user_role then

    v_origin :=
      'academy'::public.lesson_cancellation_origin;


  elsif v_actor_role =
        'manager'::public.user_role then

    if not private.manager_has_branch(
      v_lesson.branch_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;


    v_origin :=
      'academy'::public.lesson_cancellation_origin;


  elsif v_actor_role =
        'teacher'::public.user_role then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_FORBIDDEN';


  else

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_CANCELLATION_FORBIDDEN';

  end if;


  -- ==========================================================
  -- STUDENT CANCELLATION QUOTA
  -- ==========================================================

  if v_origin =
     'student'::public.lesson_cancellation_origin then

    -- --------------------------------------------------------
    -- CARRYOVER
    --
    -- Canceling/rebooking an already-carried extra entitlement
    -- does not create another entitlement and consumes no new
    -- cancellation quota.
    -- --------------------------------------------------------

    if v_right.origin =
       'carryover'::public.lesson_right_origin then

      v_counts_toward_limit :=
        false;


    -- --------------------------------------------------------
    -- REGULAR
    --
    -- Limit = 2 counting cancellations
    -- per logical regular slot / source semester.
    --
    -- Lock the logical slot to serialize concurrent cancels
    -- of different rights belonging to the same quota bucket.
    -- --------------------------------------------------------

    elsif v_right.origin =
          'regular_base'::public.lesson_right_origin then

      perform 1
      from public.regular_schedule_slots rs

      where rs.id =
            v_right.schedule_slot_id

      for update;


      if not found then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';

      end if;


      v_cancellation_limit :=
        2;


      select count(*)::integer
      into v_count_before

      from public.lesson_cancellation_events e

      join public.lesson_rights counted_right
        on counted_right.id =
           e.lesson_right_id

      where e.student_id =
            v_right.student_id

        and e.origin =
            'student'::public.lesson_cancellation_origin

        and e.counts_toward_limit = true

        and counted_right.origin =
            'regular_base'::public.lesson_right_origin

        and counted_right.source_semester_id =
            v_right.source_semester_id

        and counted_right.schedule_slot_id =
            v_right.schedule_slot_id;


      if v_count_before >=
         v_cancellation_limit then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_CANCELLATION_LIMIT_REACHED';

      end if;


      v_counts_toward_limit :=
        true;


    -- --------------------------------------------------------
    -- FLEX
    --
    -- Limit = floor(base right count / 4) * 2
    -- per student / source semester.
    --
    -- Lock the semester plan to serialize quota calculations.
    -- --------------------------------------------------------

    elsif v_right.origin =
          'flex_base'::public.lesson_right_origin then

      select
        sp.flex_base_right_count

      into
        v_flex_base_count

      from public.student_semester_plans sp

      where sp.student_id =
            v_right.student_id

        and sp.semester_id =
            v_right.source_semester_id

        and sp.student_type_snapshot =
            'flex'::public.student_type

      for update;


      if not found
         or v_flex_base_count is null then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_FLEX_SEMESTER_PLAN_REQUIRED';

      end if;


      v_cancellation_limit :=
        floor(
          v_flex_base_count::numeric / 4
        )::integer * 2;


      select count(*)::integer
      into v_count_before

      from public.lesson_cancellation_events e

      join public.lesson_rights counted_right
        on counted_right.id =
           e.lesson_right_id

      where e.student_id =
            v_right.student_id

        and e.origin =
            'student'::public.lesson_cancellation_origin

        and e.counts_toward_limit = true

        and counted_right.origin =
            'flex_base'::public.lesson_right_origin

        and counted_right.source_semester_id =
            v_right.source_semester_id;


      if v_count_before >=
         v_cancellation_limit then

        raise exception using
          errcode = 'P0001',
          message =
            'FORESTRING_CANCELLATION_LIMIT_REACHED';

      end if;


      v_counts_toward_limit :=
        true;


    else

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_UNSUPPORTED_LESSON_RIGHT_ORIGIN';

    end if;

  end if;


  -- ==========================================================
  -- CANCEL CANONICAL LESSON
  -- ==========================================================

  update public.lessons
  set
    status =
      'canceled'::public.lesson_status,

    canceled_by =
      v_actor_id,

    canceled_at =
      pg_catalog.now(),

    cancellation_reason =
      case
        when v_reason is not null
          then v_reason

        when v_origin =
             'student'::public.lesson_cancellation_origin
          then 'student_cancellation'

        else
          'academy_cancellation'
      end

  where id =
        v_lesson.id;


  -- ==========================================================
  -- RESTORE THE SAME RIGHT
  --
  -- Important:
  -- lesson.duration_minutes may have been manually edited.
  --
  -- right.duration_minutes is NOT changed.
  -- ==========================================================

  update public.lesson_rights
  set
    status =
      'available'::public.lesson_right_status,

    reserved_at =
      null

  where id =
        v_right.id;


  -- ==========================================================
  -- IMMUTABLE CANCELLATION EVENT
  -- ==========================================================

  insert into public.lesson_cancellation_events (
    lesson_id,
    lesson_right_id,
    student_id,
    branch_id,
    origin,
    actor_id,
    counts_toward_limit,
    reason,
    lesson_starts_at,
    lesson_duration_minutes
  )
  values (
    v_lesson.id,
    v_right.id,
    v_right.student_id,
    v_right.branch_id,
    v_origin,
    v_actor_id,
    v_counts_toward_limit,
    v_reason,
    v_lesson.starts_at,
    v_lesson.duration_minutes
  )
  returning id
  into v_event_id;


  -- ==========================================================
  -- QUOTA RESULT
  -- ==========================================================

  if v_origin =
       'student'::public.lesson_cancellation_origin
     and v_cancellation_limit is not null then

    if v_counts_toward_limit then
      v_count_after :=
        v_count_before + 1;
    else
      v_count_after :=
        v_count_before;
    end if;


    v_remaining :=
      greatest(
        v_cancellation_limit
        - v_count_after,
        0
      );

  else

    v_cancellation_limit :=
      null;

    v_count_after :=
      0;

    v_remaining :=
      null;

  end if;


  -- ==========================================================
  -- GENERAL AUDIT
  -- ==========================================================

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
    v_right.student_id,
    v_right.branch_id,
    v_right.usable_semester_id,
    'LESSON_CANCELED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'rightId',
        v_right.id,

      'rightOrigin',
        v_right.origin,

      'cancellationOrigin',
        v_origin,

      'countsTowardLimit',
        v_counts_toward_limit,

      'cancellationLimit',
        v_cancellation_limit,

      'countedCancellationCount',
        case
          when v_cancellation_limit is null
            then null
          else v_count_after
        end,

      'remainingCancellations',
        v_remaining,

      'entitlementDurationMinutes',
        v_right.duration_minutes,

      'actualLessonDurationMinutes',
        v_lesson.duration_minutes,

      'reason',
        v_reason,

      'cancellationEventId',
        v_event_id
    )
  );


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'lessonId',
      v_lesson.id,

    'rightId',
      v_right.id,

    'cancellationEventId',
      v_event_id,

    'origin',
      v_origin,

    'rightStatus',
      'available',

    'countsTowardLimit',
      v_counts_toward_limit,

    'cancellationLimit',
      v_cancellation_limit,

    'countedCancellationCount',
      case
        when v_cancellation_limit is null
          then null
        else v_count_after
      end,

    'remainingCancellations',
      v_remaining
  );

end;
$function$;

-- public.get_lesson_right_booking_options(p_right_id uuid, p_selected_date date)
CREATE OR REPLACE FUNCTION public.get_lesson_right_booking_options(p_right_id uuid, p_selected_date date)
 RETURNS TABLE(starts_at timestamp with time zone, ends_at timestamp with time zone, teacher_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;

  v_right public.lesson_rights%rowtype;

  v_semester_start date;
  v_semester_end date;

  v_assignment_teacher_id uuid;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id :=
    auth.uid();


  if v_actor_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_AUTH_REQUIRED';

  end if;


  -- Canonical current-access gate.
  perform private.require_effective_actor(
    v_actor_id
  );


  if not exists (
    select 1

    from public.profiles p

    join public.students s
      on s.id = p.id

    where p.id =
          v_actor_id

      and p.is_active = true

      and p.role =
          'student'::public.user_role

      and s.status =
          'active'::public.student_status
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ACTIVE_STUDENT_REQUIRED';

  end if;


  -- ==========================================================
  -- RIGHT
  -- ==========================================================

  select *
  into v_right

  from public.lesson_rights r

  where r.id =
        p_right_id;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_FOUND';

  end if;


  if v_right.student_id <>
     v_actor_id then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_FORBIDDEN';

  end if;


  if v_right.status <>
     'available'::public.lesson_right_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_RIGHT_NOT_AVAILABLE';

  end if;


  -- ==========================================================
  -- EFFECTIVE USABLE SEMESTER
  -- ==========================================================

  select
    bounds.starts_on,
    bounds.ends_on

  into
    v_semester_start,
    v_semester_end

  from private.get_effective_semester_bounds(
    v_right.branch_id,
    v_right.usable_semester_id
  ) bounds;


  if not found then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_SEMESTER_NOT_FOUND';

  end if;


  if (pg_catalog.now() at time zone 'Asia/Seoul')::date
     not between
       v_semester_start
       and v_semester_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_SEMESTER_NOT_OPEN';

  end if;


  if p_selected_date
     not between
       v_semester_start
       and v_semester_end then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_BOOKING_DATE_OUTSIDE_USABLE_SEMESTER';

  end if;


  -- ==========================================================
  -- ASSIGNMENT ON SELECTED DATE
  -- ==========================================================

  select a.teacher_id
  into v_assignment_teacher_id

  from public.teacher_student_assignments a

  join public.profiles teacher_profile
    on teacher_profile.id =
       a.teacher_id

  where a.student_id =
        v_right.student_id

    and a.branch_id =
        v_right.branch_id

    and a.starts_on <=
        p_selected_date

    and (
      a.ends_on is null
      or a.ends_on >=
         p_selected_date
    )

    and teacher_profile.is_active = true

    and teacher_profile.branch_id =
        v_right.branch_id

    and teacher_profile.role in (
      'teacher'::public.user_role,
      'manager'::public.user_role
    )

  limit 1;


  if v_assignment_teacher_id is null then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_ASSIGNMENT_REQUIRED';

  end if;


  -- ==========================================================
  -- SERVER-CALCULATED CANDIDATES
  -- ==========================================================

  return query

  select
    candidate.starts_at,
    candidate.ends_at,
    candidate.teacher_id

  from private.lesson_right_slot_candidates(
    p_right_id,
    p_selected_date,
    v_actor_id
  ) candidate;

end;
$function$;

-- public.replace_teacher_work_hours_effective(p_teacher_id uuid, p_effective_on date, p_segments jsonb)
CREATE OR REPLACE FUNCTION public.replace_teacher_work_hours_effective(p_teacher_id uuid, p_effective_on date, p_segments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_role public.user_role;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_before jsonb;
  v_after jsonb;
  v_version private.teacher_work_hour_versions%rowtype;
  v_previous private.teacher_work_hour_versions%rowtype;
  v_next_start date;
  v_version_id uuid;
  v_segment_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;
  perform private.require_effective_actor(v_actor_id);

  select p.role into v_actor_role
  from public.profiles p
  where p.id=v_actor_id and p.is_active=true;
  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_STAFF_REQUIRED';
  end if;

  perform 1 from public.teachers t where t.id=p_teacher_id for update;
  if not found then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;

  select p.branch_id,p.is_active,p.role
  into v_teacher_branch_id,v_teacher_active,v_teacher_role
  from public.profiles p where p.id=p_teacher_id;

  if v_teacher_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_BRANCH_REQUIRED';
  end if;
  if not v_teacher_active or v_teacher_role not in ('teacher'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_TEACHER_REQUIRED';
  end if;
  if v_actor_role='manager'::public.user_role and not private.manager_has_branch(v_teacher_branch_id) then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  if p_effective_on is null then
    raise exception using errcode='P0001', message='FORESTRING_WORK_HOURS_EFFECTIVE_DATE_REQUIRED';
  end if;
  if p_effective_on < v_today then
    raise exception using errcode='P0001', message='FORESTRING_BACKDATED_WORK_HOURS_CHANGE_FORBIDDEN';
  end if;
  if p_segments is null or jsonb_typeof(p_segments)<>'array' then
    raise exception using errcode='P0001', message='FORESTRING_WORK_HOURS_ARRAY_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_segments) as x(weekday integer,"startTime" text,"endTime" text)
    where x.weekday is null or x.weekday not between 1 and 7
       or x."startTime" is null or x."endTime" is null
       or x."startTime" !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or x."endTime" !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  ) then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_WORK_HOURS_FORMAT';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_segments) as x(weekday integer,"startTime" text,"endTime" text)
    where extract(minute from x."startTime"::time)::integer % 15 <> 0
       or extract(minute from x."endTime"::time)::integer % 15 <> 0
       or x."startTime"::time >= x."endTime"::time
  ) then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_WORK_HOURS_RANGE';
  end if;

  if exists (
    with segments as (
      select row_number() over() rn,x.weekday,
             x."startTime"::time start_time,x."endTime"::time end_time
      from jsonb_to_recordset(p_segments) as x(weekday integer,"startTime" text,"endTime" text)
    )
    select 1 from segments a join segments b
      on a.rn<b.rn and a.weekday=b.weekday
     and int4range(extract(hour from a.start_time)::integer*60+extract(minute from a.start_time)::integer,
                   extract(hour from a.end_time)::integer*60+extract(minute from a.end_time)::integer,'[)')
         && int4range(extract(hour from b.start_time)::integer*60+extract(minute from b.start_time)::integer,
                      extract(hour from b.end_time)::integer*60+extract(minute from b.end_time)::integer,'[)')
  ) then
    raise exception using errcode='P0001', message='FORESTRING_WORK_HOURS_OVERLAP';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'weekday',wh.weekday,'startTime',to_char(wh.start_time,'HH24:MI'),'endTime',to_char(wh.end_time,'HH24:MI'))
      order by wh.weekday,wh.start_time,wh.end_time),'[]'::jsonb)
  into v_before
  from private.teacher_work_hours_for_date(p_teacher_id,p_effective_on) wh;

  select coalesce(jsonb_agg(jsonb_build_object(
      'weekday',q.weekday,'startTime',q.start_time,'endTime',q.end_time)
      order by q.weekday,q.start_time::time,q.end_time::time),'[]'::jsonb)
  into v_after
  from (
    select x.weekday,to_char(x."startTime"::time,'HH24:MI') start_time,
           to_char(x."endTime"::time,'HH24:MI') end_time
    from jsonb_to_recordset(p_segments) as x(weekday integer,"startTime" text,"endTime" text)
  ) q;

  if v_before=v_after then
    return jsonb_build_object('teacherId',p_teacher_id,'branchId',v_teacher_branch_id,
      'effectiveOn',p_effective_on,'changed',false,'segmentCount',jsonb_array_length(v_after));
  end if;

  select * into v_version
  from private.teacher_work_hour_versions v
  where v.teacher_id=p_teacher_id and v.effective_from=p_effective_on
  for update;

  if found then
    v_version_id := v_version.id;
    delete from private.teacher_work_hour_entries e where e.version_id=v_version_id;
  else
    select * into v_previous
    from private.teacher_work_hour_versions v
    where v.teacher_id=p_teacher_id and v.effective_from<p_effective_on
    order by v.effective_from desc limit 1 for update;

    select min(v.effective_from) into v_next_start
    from private.teacher_work_hour_versions v
    where v.teacher_id=p_teacher_id and v.effective_from>p_effective_on;

    if v_previous.id is null and p_effective_on>v_today then
      insert into private.teacher_work_hour_versions(
        teacher_id,effective_from,effective_until,created_by
      ) values (p_teacher_id,v_today,p_effective_on-1,v_actor_id)
      returning id into v_previous.id;

      insert into private.teacher_work_hour_entries(version_id,weekday,start_time,end_time)
      select v_previous.id,wh.weekday,wh.start_time,wh.end_time
      from public.teacher_work_hours wh where wh.teacher_id=p_teacher_id;
    elsif v_previous.id is not null then
      update private.teacher_work_hour_versions
      set effective_until=p_effective_on-1,updated_at=pg_catalog.now()
      where id=v_previous.id;
    end if;

    insert into private.teacher_work_hour_versions(
      teacher_id,effective_from,effective_until,created_by
    ) values (
      p_teacher_id,p_effective_on,
      case when v_next_start is null then null else v_next_start-1 end,
      v_actor_id
    ) returning id into v_version_id;
  end if;

  insert into private.teacher_work_hour_entries(version_id,weekday,start_time,end_time)
  select v_version_id,x.weekday::smallint,x."startTime"::time,x."endTime"::time
  from jsonb_to_recordset(p_segments) as x(weekday integer,"startTime" text,"endTime" text);
  get diagnostics v_segment_count=row_count;

  update private.teacher_work_hour_versions
  set updated_at=pg_catalog.now()
  where id=v_version_id;

  if p_effective_on=v_today then
    delete from public.teacher_work_hours where teacher_id=p_teacher_id;
    insert into public.teacher_work_hours(teacher_id,weekday,start_time,end_time)
    select p_teacher_id,e.weekday,e.start_time,e.end_time
    from private.teacher_work_hour_entries e
    where e.version_id=v_version_id;
  end if;

  insert into public.audit_events(
    subject_profile_id,branch_id,event_type,effective_on,actor_id,details
  ) values (
    p_teacher_id,v_teacher_branch_id,'TEACHER_WORK_HOURS_CHANGED',p_effective_on,v_actor_id,
    jsonb_build_object('before',v_before,'after',v_after,'effectiveOn',p_effective_on,'versionId',v_version_id)
  );

  return jsonb_build_object('teacherId',p_teacher_id,'branchId',v_teacher_branch_id,
    'effectiveOn',p_effective_on,'changed',true,'segmentCount',v_segment_count,'versionId',v_version_id);
end;
$function$;

-- public.update_lesson_once(p_lesson_id uuid, p_starts_at timestamp with time zone, p_duration_minutes integer, p_confirm_warnings boolean, p_reason text)
CREATE OR REPLACE FUNCTION public.update_lesson_once(p_lesson_id uuid, p_starts_at timestamp with time zone, p_duration_minutes integer, p_confirm_warnings boolean DEFAULT false, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;

  v_lesson public.lessons%rowtype;

  v_new_ends_at timestamptz;

  v_local_start timestamp;
  v_local_end timestamp;

  v_inside_work_hours boolean;
  v_overlaps_blocked boolean;

  v_warning_codes text[] :=
    array[]::text[];

  v_before jsonb;
  v_after jsonb;

  v_reason text;
begin

  -- ==========================================================
  -- AUTH
  -- ==========================================================

  v_actor_id := auth.uid();


  if v_actor_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_AUTH_REQUIRED';
  end if;


  perform private.require_effective_actor(
    v_actor_id
  );


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


  -- ==========================================================
  -- LOCK LESSON
  -- ==========================================================

  select *
  into v_lesson
  from public.lessons l
  where l.id = p_lesson_id
  for update;


  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_NOT_FOUND';
  end if;


  if v_lesson.branch_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'FORESTRING_LESSON_BRANCH_REQUIRED';
  end if;


  -- ==========================================================
  -- PERMISSION
  -- ==========================================================

  if v_actor_role =
     'master'::public.user_role then

    null;


  elsif v_actor_role =
        'manager'::public.user_role then

    if not private.manager_has_branch(
      v_lesson.branch_id
    ) then

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_MANAGER_BRANCH_FORBIDDEN';

    end if;


  elsif v_actor_role =
        'teacher'::public.user_role then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_UPDATE_FORBIDDEN';


  else

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_UPDATE_FORBIDDEN';

  end if;


  -- ==========================================================
  -- CURRENT LESSON STATE
  -- ==========================================================

  if v_lesson.status <>
     'scheduled'::public.lesson_status then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_ONLY_SCHEDULED_LESSON_EDITABLE';

  end if;


  -- ==========================================================
  -- INPUT
  -- ==========================================================

  if p_starts_at is null then
    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_LESSON_START_REQUIRED';
  end if;


  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes, 15) <> 0 then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_INVALID_LESSON_DURATION';

  end if;


  v_new_ends_at :=
    p_starts_at
    +
    pg_catalog.make_interval(
      mins => p_duration_minutes
    );


  v_reason :=
    nullif(
      btrim(
        coalesce(p_reason, '')
      ),
      ''
    );


  -- ==========================================================
  -- NO-OP
  --
  -- Do this before warning checks.
  --
  -- Saving an unchanged lesson must not suddenly produce
  -- warnings simply because the current lesson happens to be
  -- outside today's work-hour defaults.
  -- ==========================================================

  if v_lesson.starts_at = p_starts_at
     and
     v_lesson.duration_minutes =
       p_duration_minutes then

    return jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'changed',
        false,

      'requiresConfirmation',
        false,

      'warningCodes',
        '[]'::jsonb,

      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes
    );

  end if;


  -- ==========================================================
  -- HARD ACTUAL COLLISION:
  -- TEACHER
  -- ==========================================================

  if exists (
    select 1
    from public.lessons other
    where other.id <> v_lesson.id

      and other.teacher_id =
          v_lesson.teacher_id

      and other.status =
          'scheduled'::public.lesson_status

      and tstzrange(
            other.starts_at,
            other.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_TEACHER_LESSON_OVERLAP';

  end if;


  -- ==========================================================
  -- HARD ACTUAL COLLISION:
  -- STUDENT
  -- ==========================================================

  if exists (
    select 1
    from public.lessons other
    where other.id <> v_lesson.id

      and other.student_id =
          v_lesson.student_id

      and other.status =
          'scheduled'::public.lesson_status

      and tstzrange(
            other.starts_at,
            other.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  ) then

    raise exception using
      errcode = 'P0001',
      message =
        'FORESTRING_STUDENT_LESSON_OVERLAP';

  end if;


  -- ==========================================================
  -- KST LOCAL VALUES
  -- ==========================================================

  v_local_start :=
    p_starts_at
    at time zone 'Asia/Seoul';


  v_local_end :=
    v_new_ends_at
    at time zone 'Asia/Seoul';


  -- ==========================================================
  -- SOFT WARNING:
  -- OUTSIDE WORK HOURS
  --
  -- The full lesson must fit inside ONE work-hour segment.
  --
  -- No configured work hours also means:
  -- outside normal work hours.
  -- ==========================================================

  select exists (
    select 1
    from private.teacher_work_hours_for_date(v_lesson.teacher_id, v_local_start::date) wh

    where wh.teacher_id =
          v_lesson.teacher_id

      and wh.weekday =
          extract(
            isodow
            from v_local_start
          )::integer

      and v_local_start::date =
          v_local_end::date

      and wh.start_time <=
          v_local_start::time

      and wh.end_time >=
          v_local_end::time
  )
  into v_inside_work_hours;


  if not v_inside_work_hours then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_OUTSIDE_WORK_HOURS'
      );

  end if;


  -- ==========================================================
  -- SOFT WARNING:
  -- BLOCKED PERIOD
  -- ==========================================================

  select exists (
    select 1
    from public.blocked_periods bp

    where bp.teacher_id =
          v_lesson.teacher_id

      and tstzrange(
            bp.starts_at,
            bp.ends_at,
            '[)'
          )
          &&
          tstzrange(
            p_starts_at,
            v_new_ends_at,
            '[)'
          )
  )
  into v_overlaps_blocked;


  if v_overlaps_blocked then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_OVERLAPS_BLOCKED_PERIOD'
      );

  end if;


  -- ==========================================================
  -- SOFT WARNING:
  -- NON-STANDARD DURATION
  --
  -- Recommended presets:
  --   15 / 30 / 60
  --
  -- Privileged staff may still use:
  --   45 / 75 / 90 / ...
  -- after explicit confirmation.
  -- ==========================================================

  if p_duration_minutes not in (
    15,
    30,
    60
  ) then

    v_warning_codes :=
      array_append(
        v_warning_codes,
        'FORESTRING_NONSTANDARD_DURATION'
      );

  end if;


  -- ==========================================================
  -- WARNING RESPONSE WITHOUT MUTATION
  -- ==========================================================

  if cardinality(v_warning_codes) > 0
     and not coalesce(
       p_confirm_warnings,
       false
     ) then

    return jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'changed',
        false,

      'requiresConfirmation',
        true,

      'warningCodes',
        to_jsonb(v_warning_codes),

      'proposedStartsAt',
        p_starts_at,

      'proposedEndsAt',
        v_new_ends_at,

      'proposedDurationMinutes',
        p_duration_minutes
    );

  end if;


  -- ==========================================================
  -- AUDIT BEFORE
  -- ==========================================================

  v_before :=
    jsonb_build_object(
      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at,

      'lessonRightId',
        v_lesson.lesson_right_id
    );


  -- ==========================================================
  -- UPDATE ONLY THE ACTUAL LESSON
  --
  -- ends_at is recalculated by existing DB trigger.
  --
  -- occurrence_at stays unchanged.
  -- lesson_right_id stays unchanged.
  -- series_id stays unchanged.
  -- ==========================================================

  begin

    update public.lessons
    set
      starts_at =
        p_starts_at,

      duration_minutes =
        p_duration_minutes,

      rescheduled_by =
        case
          when starts_at <>
               p_starts_at
            then v_actor_id
          else rescheduled_by
        end

    where id =
          v_lesson.id

    returning *
    into v_lesson;


  exception
    when exclusion_violation then

      -- A concurrent transaction may have inserted/moved
      -- another lesson after our explicit pre-check.

      raise exception using
        errcode = 'P0001',
        message =
          'FORESTRING_LESSON_TIME_CONFLICT';

  end;


  -- ==========================================================
  -- AUDIT AFTER
  -- ==========================================================

  v_after :=
    jsonb_build_object(
      'startsAt',
        v_lesson.starts_at,

      'endsAt',
        v_lesson.ends_at,

      'durationMinutes',
        v_lesson.duration_minutes,

      'seriesId',
        v_lesson.series_id,

      'occurrenceAt',
        v_lesson.occurrence_at,

      'lessonRightId',
        v_lesson.lesson_right_id
    );


  insert into public.audit_events (
    subject_profile_id,
    branch_id,
    event_type,
    effective_on,
    actor_id,
    details
  )
  values (
    v_lesson.student_id,

    v_lesson.branch_id,

    'LESSON_MANUALLY_UPDATED',

    (
      v_lesson.starts_at
      at time zone 'Asia/Seoul'
    )::date,

    v_actor_id,

    jsonb_build_object(
      'lessonId',
        v_lesson.id,

      'teacherId',
        v_lesson.teacher_id,

      'before',
        v_before,

      'after',
        v_after,

      'warningCodes',
        to_jsonb(v_warning_codes),

      'warningsOverridden',
        cardinality(v_warning_codes) > 0,

      'reason',
        v_reason
    )
  );


  -- ==========================================================
  -- RESULT
  -- ==========================================================

  return jsonb_build_object(
    'lessonId',
      v_lesson.id,

    'changed',
      true,

    'requiresConfirmation',
      false,

    'warningCodes',
      to_jsonb(v_warning_codes),

    'startsAt',
      v_lesson.starts_at,

    'endsAt',
      v_lesson.ends_at,

    'durationMinutes',
      v_lesson.duration_minutes
  );

end;
$function$;

-- Reconstructed private helpers must not be callable by application roles.
revoke all on function private.after_regular_schedule_changed_rematerialize_academy_rights()
from public, anon, authenticated, service_role;

revoke all on function private.is_semester_open_now(uuid, uuid)
from public, anon, authenticated, service_role;

-- Review-account bootstrap is service-role only in Production.
revoke all on function public.admin_create_review_account_data(uuid, text, text, text, text)
from public, anon, authenticated;
grant execute on function public.admin_create_review_account_data(uuid, text, text, text, text)
to service_role;

drop trigger if exists audit_events_after_regular_schedule_changed_rematerialize_acade
on public.audit_events;

CREATE TRIGGER audit_events_after_regular_schedule_changed_rematerialize_acade AFTER INSERT ON audit_events FOR EACH ROW WHEN (new.event_type = 'REGULAR_SCHEDULE_CHANGED'::text) EXECUTE FUNCTION private.after_regular_schedule_changed_rematerialize_academy_rights();
