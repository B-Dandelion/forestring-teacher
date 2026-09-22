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
  v_student_withdrawal_date date;

  v_teacher_branch_id uuid;
  v_teacher_active boolean;
  v_teacher_withdrawal_date date;

  v_semester_id uuid;
  v_semester_start date;
  v_semester_end date;
  v_target_plan_id uuid;
  v_target_plan_type public.student_type;
  v_target_plan_status public.student_semester_plan_status;

  v_end_time time;
  v_slot_id uuid;
  v_series_id uuid;

  v_plan record;
  v_candidate record;
  v_right_id uuid;
  v_plan_candidate_count integer;
  v_created_right_count integer := 0;
  v_created_lesson_count integer := 0;
  v_materialized_semester_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role, p.branch_id
  into v_actor_role, v_actor_branch_id
  from public.profiles p
  where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using errcode='P0001', message='FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_weekday not between 1 and 7 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_WEEKDAY';
  end if;

  if p_start_time is null
     or extract(second from p_start_time) <> 0
     or mod(extract(minute from p_start_time)::integer,15) <> 0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';
  end if;

  if p_duration_minutes is null
     or p_duration_minutes <= 0
     or p_duration_minutes > 720
     or mod(p_duration_minutes,15) <> 0 then
    raise exception using errcode='P0001', message='FORESTRING_INVALID_REGULAR_DURATION';
  end if;

  if extract(hour from p_start_time)::integer * 60
       + extract(minute from p_start_time)::integer
       + p_duration_minutes > 1440 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_LESSON_CROSSES_MIDNIGHT';
  end if;

  v_end_time := (p_start_time + pg_catalog.make_interval(mins=>p_duration_minutes))::time;

  select p.branch_id, p.is_active, s.status, s.student_type, s.withdrawal_date
  into v_student_branch_id, v_student_active, v_student_status, v_student_type, v_student_withdrawal_date
  from public.students s
  join public.profiles p on p.id=s.id
  where s.id=p_student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_student_type <> 'regular'::public.student_type then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_STUDENT_REQUIRED';
  end if;

  if v_student_withdrawal_date is not null and p_effective_on >= v_student_withdrawal_date then
    raise exception using errcode='P0001', message='FORESTRING_SCHEDULE_AFTER_STUDENT_WITHDRAWAL';
  end if;

  if v_actor_role='manager'::public.user_role
     and v_actor_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.branch_id, p.is_active, t.withdrawal_date
  into v_teacher_branch_id, v_teacher_active, v_teacher_withdrawal_date
  from public.teachers t
  join public.profiles p on p.id=t.id
  where t.id=p_teacher_id;

  if not found or v_teacher_active <> true then
    raise exception using errcode='P0001', message='FORESTRING_TEACHER_NOT_FOUND';
  end if;

  if v_teacher_branch_id is distinct from v_student_branch_id then
    raise exception using errcode='P0001', message='FORESTRING_BRANCH_MISMATCH';
  end if;

  select s.id, bounds.starts_on, bounds.ends_on
  into v_semester_id, v_semester_start, v_semester_end
  from public.semesters s
  cross join lateral private.get_effective_semester_bounds(v_student_branch_id,s.id) bounds
  where p_effective_on between bounds.starts_on and bounds.ends_on
  order by bounds.starts_on desc
  limit 1;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND_FOR_DATE';
  end if;

  select sp.id, sp.student_type_snapshot, sp.status
  into v_target_plan_id, v_target_plan_type, v_target_plan_status
  from public.student_semester_plans sp
  where sp.student_id=p_student_id and sp.semester_id=v_semester_id
  for update;

  if found then
    if v_target_plan_type <> 'regular'::public.student_type then
      raise exception using errcode='P0001', message='FORESTRING_TARGET_SEMESTER_NOT_REGULAR';
    end if;
    if v_target_plan_status='completed'::public.student_semester_plan_status then
      raise exception using errcode='P0001', message='FORESTRING_COMPLETED_PLAN_IMMUTABLE';
    end if;
  end if;

  -- A mid-semester addition is safe only when that semester is already
  -- materialized. Planned/uncreated semesters still use the four-week
  -- activation path and therefore must begin at the semester boundary.
  if coalesce(v_target_plan_status <> 'active'::public.student_semester_plan_status,true)
     and p_effective_on <> v_semester_start then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_ADD_REQUIRES_SEMESTER_START';
  end if;

  if v_teacher_withdrawal_date is not null and v_teacher_withdrawal_date <= v_semester_end then
    raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
  end if;

  if not exists (
    select 1
    from public.teacher_student_assignments a
    where a.student_id=p_student_id
      and a.teacher_id=p_teacher_id
      and a.branch_id=v_student_branch_id
      and a.starts_on <= p_effective_on
      and (a.ends_on is null or a.ends_on >= least(v_semester_end,coalesce(v_student_withdrawal_date-1,v_semester_end)))
  ) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH';
  end if;

  if not exists (
    select 1 from public.teacher_work_hours wh
    where wh.teacher_id=p_teacher_id
      and wh.weekday=p_weekday
      and wh.start_time <= p_start_time
      and wh.end_time >= v_end_time
  ) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS';
  end if;

  insert into public.regular_schedule_slots(student_id,branch_id,starts_on,ends_on,created_by)
  values(p_student_id,v_student_branch_id,p_effective_on,null,v_actor_id)
  returning id into v_slot_id;

  begin
    insert into public.lesson_series(
      student_id,teacher_id,weekday,start_time,duration_minutes,
      effective_from,effective_until,branch_id,schedule_slot_id
    ) values (
      p_student_id,p_teacher_id,p_weekday,p_start_time,p_duration_minutes,
      p_effective_on,null,v_student_branch_id,v_slot_id
    ) returning id into v_series_id;
  exception when exclusion_violation then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SERIES_TIME_CONFLICT';
  end;

  -- Materialize this newly-added recurring slot into every already-active
  -- regular semester plan from the effective date forward.  This is the
  -- crucial distinction: active means materialized, not necessarily current.
  for v_plan in
    select sp.id as plan_id, sp.semester_id, bounds.starts_on, bounds.ends_on
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
    where sp.student_id=p_student_id
      and sp.branch_id=v_student_branch_id
      and sp.student_type_snapshot='regular'::public.student_type
      and sp.status='active'::public.student_semester_plan_status
      and bounds.ends_on >= p_effective_on
    order by bounds.starts_on, sp.id
    for update of sp
  loop
    v_plan_candidate_count := 0;
    v_materialized_semester_count := v_materialized_semester_count + 1;

    for v_candidate in
      with candidate_dates as (
        select d::date as lesson_date
        from pg_catalog.generate_series(
          greatest(v_plan.starts_on,p_effective_on)::timestamp,
          v_plan.ends_on::timestamp,
          interval '1 day'
        ) d
        where extract(isodow from d)::integer=p_weekday
          and not exists (
            select 1 from public.closure_periods cp
            where cp.branch_id=v_student_branch_id
              and cp.semester_id=v_plan.semester_id
              and cp.closure_kind='instructional_break'::public.closure_kind
              and d::date between cp.starts_on and cp.ends_on
          )
      )
      select row_number() over(order by cd.lesson_date)::integer as sequence_no,
             cd.lesson_date,
             (cd.lesson_date+p_start_time) at time zone 'Asia/Seoul' as starts_at,
             ((cd.lesson_date+p_start_time) at time zone 'Asia/Seoul')
               + pg_catalog.make_interval(mins=>p_duration_minutes) as ends_at
      from candidate_dates cd
      order by cd.lesson_date
    loop
      v_plan_candidate_count := v_plan_candidate_count + 1;

      if v_plan_candidate_count > 4 then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES';
      end if;

      if v_student_withdrawal_date is not null and v_candidate.lesson_date >= v_student_withdrawal_date then
        raise exception using errcode='P0001', message='FORESTRING_SCHEDULE_AFTER_STUDENT_WITHDRAWAL';
      end if;

      if v_teacher_withdrawal_date is not null and v_candidate.lesson_date >= v_teacher_withdrawal_date then
        raise exception using errcode='P0001', message='FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
      end if;

      if not exists (
        select 1 from public.teacher_student_assignments a
        where a.student_id=p_student_id
          and a.teacher_id=p_teacher_id
          and a.branch_id=v_student_branch_id
          and a.starts_on <= v_candidate.lesson_date
          and (a.ends_on is null or a.ends_on >= v_candidate.lesson_date)
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_TEACHER_ASSIGNMENT_MISMATCH',
          detail='date='||v_candidate.lesson_date::text;
      end if;

      if exists (
        select 1 from public.closure_periods cp
        where cp.branch_id=v_student_branch_id
          and cp.semester_id=v_plan.semester_id
          and cp.closure_kind='ordinary'::public.closure_kind
          and v_candidate.lesson_date between cp.starts_on and cp.ends_on
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_ON_ORDINARY_CLOSURE',
          detail='date='||v_candidate.lesson_date::text;
      end if;

      if exists (
        select 1 from public.blocked_periods bp
        where bp.teacher_id=p_teacher_id
          and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_candidate.starts_at,v_candidate.ends_at,'[)')
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_OCCURRENCE_BLOCKED',
          detail='date='||v_candidate.lesson_date::text;
      end if;

      insert into public.lesson_rights(
        student_id,branch_id,source_semester_id,usable_semester_id,
        schedule_slot_id,source_right_id,origin,sequence_no,duration_minutes,
        status,carryover_count,created_by,reserved_at
      ) values (
        p_student_id,v_student_branch_id,v_plan.semester_id,v_plan.semester_id,
        v_slot_id,null,'regular_base'::public.lesson_right_origin,v_candidate.sequence_no,
        p_duration_minutes,'reserved'::public.lesson_right_status,0,v_actor_id,pg_catalog.now()
      ) returning id into v_right_id;

      v_created_right_count := v_created_right_count + 1;

      begin
        insert into public.lessons(
          series_id,student_id,teacher_id,occurrence_at,starts_at,
          duration_minutes,lesson_type,status,lesson_right_id
        ) values (
          v_series_id,p_student_id,p_teacher_id,v_candidate.starts_at,v_candidate.starts_at,
          p_duration_minutes,'regular'::public.lesson_type,'scheduled'::public.lesson_status,v_right_id
        );
      exception when exclusion_violation then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_TIME_CONFLICT',
          detail='schedule_slot_id='||v_slot_id::text||', starts_at='||v_candidate.starts_at::text;
      end;

      v_created_lesson_count := v_created_lesson_count + 1;
    end loop;
  end loop;

  if v_created_right_count <> v_created_lesson_count then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_MATERIALIZATION_COUNT_MISMATCH';
  end if;

  insert into public.audit_events(
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    p_student_id,v_student_branch_id,v_semester_id,'REGULAR_SCHEDULE_ADDED',p_effective_on,v_actor_id,
    jsonb_build_object(
      'scheduleSlotId',v_slot_id,'seriesId',v_series_id,'teacherId',p_teacher_id,
      'weekday',p_weekday,'startTime',p_start_time,'durationMinutes',p_duration_minutes,
      'planId',v_target_plan_id,'planStatus',v_target_plan_status,
      'materializedImmediately',v_created_lesson_count>0,
      'materializedSemesterCount',v_materialized_semester_count,
      'rightCount',v_created_right_count,'lessonCount',v_created_lesson_count
    )
  );

  return jsonb_build_object(
    'changed',true,'scheduleSlotId',v_slot_id,'seriesId',v_series_id,
    'semesterId',v_semester_id,'effectiveOn',p_effective_on,'teacherId',p_teacher_id,
    'weekday',p_weekday,'startTime',p_start_time,'durationMinutes',p_duration_minutes,
    'planStatus',v_target_plan_status,'materializedImmediately',v_created_lesson_count>0,
    'materializedSemesterCount',v_materialized_semester_count,
    'rightCount',v_created_right_count,'lessonCount',v_created_lesson_count
  );
end;
$function$;

create or replace function public.end_regular_schedule(
  p_schedule_slot_id uuid,
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

  v_slot public.regular_schedule_slots%rowtype;
  v_student_active boolean;
  v_student_status public.student_status;
  v_lesson record;

  v_end_on date;
  v_canceled_lesson_count integer := 0;
  v_revoked_right_count integer := 0;
  v_deleted_lesson_count integer := 0;
  v_deleted_right_count integer := 0;
  v_hard_deleted boolean := false;
  v_linked_right_count integer := 0;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001', message='FORESTRING_AUTH_REQUIRED';
  end if;

  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p where p.id=v_actor_id and p.is_active=true;

  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  if p_effective_on is null or p_effective_on < v_today then
    raise exception using errcode='P0001', message='FORESTRING_BACKDATED_REGULAR_SCHEDULE_CHANGE_FORBIDDEN';
  end if;

  select rs.* into v_slot
  from public.regular_schedule_slots rs
  where rs.id=p_schedule_slot_id
  for update;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_SLOT_NOT_FOUND';
  end if;

  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_slot.branch_id then
    raise exception using errcode='P0001', message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select p.is_active,s.status into v_student_active,v_student_status
  from public.students s join public.profiles p on p.id=s.id
  where s.id=v_slot.student_id;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_NOT_FOUND';
  end if;

  if v_student_active <> true or v_student_status <> 'active'::public.student_status then
    raise exception using errcode='P0001', message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;

  if v_slot.ends_on is not null and v_slot.ends_on < p_effective_on then
    return jsonb_build_object(
      'changed',false,'scheduleSlotId',v_slot.id,'effectiveOn',v_slot.ends_on+1,
      'canceledLessonCount',0,'revokedRightCount',0,'hardDeleted',false
    );
  end if;

  if p_effective_on <= v_slot.starts_on then
    select count(*)::integer into v_linked_right_count
    from public.lesson_rights r
    where r.schedule_slot_id=v_slot.id;

    if v_linked_right_count=0 then
      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    else
      -- A just-created materialized schedule can still be undone safely,
      -- but only while every generated entitlement/lesson is pristine and future.
      if exists (
        select 1
        from public.lesson_rights r
        left join public.lessons l on l.lesson_right_id=r.id
        where r.schedule_slot_id=v_slot.id
          and (
            r.origin <> 'regular_base'::public.lesson_right_origin
            or r.status <> 'reserved'::public.lesson_right_status
            or l.id is null
            or l.status <> 'scheduled'::public.lesson_status
            or l.rescheduled_by is not null
            or l.canceled_at is not null
            or l.starts_at <= pg_catalog.now()
          )
      ) or exists (
        select 1 from public.lesson_cancellation_events e
        join public.lesson_rights r on r.id=e.lesson_right_id
        where r.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lesson_rights child
        join public.lesson_rights source on source.id=child.source_right_id
        where source.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lessons m
        join public.lesson_rights r on r.id=m.manual_makeup_right_id
        where r.schedule_slot_id=v_slot.id
      ) or exists (
        select 1 from public.lesson_rebooking_credits c
        join public.lessons l on l.id=c.source_lesson_id
        join public.lesson_rights r on r.id=l.lesson_right_id
        where r.schedule_slot_id=v_slot.id
      ) then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_MATERIALIZED_UNDO_UNSAFE';
      end if;

      delete from public.lessons l
      using public.lesson_rights r
      where l.lesson_right_id=r.id and r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_lesson_count=row_count;

      delete from public.lesson_rights r where r.schedule_slot_id=v_slot.id;
      get diagnostics v_deleted_right_count=row_count;

      if v_deleted_right_count <> v_linked_right_count then
        raise exception using errcode='P0001', message='FORESTRING_REGULAR_SCHEDULE_UNDO_COUNT_MISMATCH';
      end if;

      delete from public.lesson_series ls where ls.schedule_slot_id=v_slot.id;
      delete from public.regular_schedule_slots rs where rs.id=v_slot.id;
      v_hard_deleted := true;
    end if;
  else
    v_end_on := p_effective_on-1;

    update public.lesson_series ls
    set effective_until=v_end_on
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from < p_effective_on
      and (ls.effective_until is null or ls.effective_until >= p_effective_on);

    delete from public.lesson_series ls
    where ls.schedule_slot_id=v_slot.id
      and ls.effective_from >= p_effective_on
      and not exists (select 1 from public.lessons l where l.series_id=ls.id);

    update public.regular_schedule_slots rs set ends_on=v_end_on where rs.id=v_slot.id;

    for v_lesson in
      select l.id as lesson_id,r.id as right_id
      from public.lesson_rights r
      join public.lessons l on l.lesson_right_id=r.id
      where r.schedule_slot_id=v_slot.id
        and r.origin='regular_base'::public.lesson_right_origin
        and r.status='reserved'::public.lesson_right_status
        and l.lesson_type='regular'::public.lesson_type
        and l.status='scheduled'::public.lesson_status
        and l.rescheduled_by is null
        and l.occurrence_at is not null
        and (l.occurrence_at at time zone 'Asia/Seoul')::date >= p_effective_on
        and l.starts_at > pg_catalog.now()
        and not exists (select 1 from public.lesson_cancellation_events e where e.lesson_right_id=r.id)
      order by l.starts_at,l.id
      for update of l,r
    loop
      perform public.cancel_lesson(v_lesson.lesson_id,'regular_schedule_ended');

      update public.lesson_rights r
      set status='revoked'::public.lesson_right_status,
          revoked_at=coalesce(r.revoked_at,pg_catalog.now())
      where r.id=v_lesson.right_id and r.status='available'::public.lesson_right_status;

      if found then v_revoked_right_count := v_revoked_right_count+1; end if;
      v_canceled_lesson_count := v_canceled_lesson_count+1;
    end loop;
  end if;

  insert into public.audit_events(
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    v_slot.student_id,v_slot.branch_id,null,'REGULAR_SCHEDULE_ENDED',p_effective_on,v_actor_id,
    jsonb_build_object(
      'scheduleSlotId',v_slot.id,'previousStartsOn',v_slot.starts_on,'previousEndsOn',v_slot.ends_on,
      'hardDeleted',v_hard_deleted,'canceledLessonCount',v_canceled_lesson_count,
      'revokedRightCount',v_revoked_right_count,'deletedLessonCount',v_deleted_lesson_count,
      'deletedRightCount',v_deleted_right_count
    )
  );

  return jsonb_build_object(
    'changed',true,'scheduleSlotId',v_slot.id,'effectiveOn',p_effective_on,
    'canceledLessonCount',v_canceled_lesson_count,'revokedRightCount',v_revoked_right_count,
    'deletedLessonCount',v_deleted_lesson_count,'deletedRightCount',v_deleted_right_count,
    'hardDeleted',v_hard_deleted
  );
end;
$function$;
