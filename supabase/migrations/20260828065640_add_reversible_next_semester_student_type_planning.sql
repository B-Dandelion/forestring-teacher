create or replace function private.clear_future_student_type_materialization(
  p_student_id uuid,
  p_from_semester_start date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
  v_auto_cancellation_event_count integer := 0;
  v_deleted_lesson_count integer := 0;
  v_deleted_right_count integer := 0;
  v_deleted_later_plan_count integer := 0;
begin
  if p_student_id is null or p_from_semester_start is null then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_ARGUMENT_REQUIRED';
  end if;

  select p.branch_id into v_branch_id
  from public.profiles p
  join public.students s on s.id=p.id
  where p.id=p_student_id;

  if not found or v_branch_id is null then
    raise exception using errcode='P0001', message='FORESTRING_STUDENT_BRANCH_REQUIRED';
  end if;

  perform 1
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
  where sp.student_id=p_student_id
    and bounds.starts_on>=p_from_semester_start
  for update of sp;

  if exists (
    select 1
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
    where sp.student_id=p_student_id
      and bounds.starts_on>=p_from_semester_start
      and sp.branch_id is distinct from v_branch_id
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_BRANCH_TRANSFER_UNSAFE';
  end if;

  if exists (
    select 1
    from public.student_semester_plans sp
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
    where sp.student_id=p_student_id
      and bounds.starts_on>=p_from_semester_start
      and sp.status='completed'::public.student_semester_plan_status
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_COMPLETED_PLAN_UNSAFE';
  end if;

  perform 1
  from public.lesson_rights r
  where r.student_id=p_student_id
    and exists (
      select 1
      from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where sp.student_id=p_student_id
        and sp.semester_id=r.source_semester_id
        and bounds.starts_on>=p_from_semester_start
    )
  for update;

  perform 1
  from public.lessons l
  join public.lesson_rights r on r.id=l.lesson_right_id
  where r.student_id=p_student_id
    and exists (
      select 1
      from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where sp.student_id=p_student_id
        and sp.semester_id=r.source_semester_id
        and bounds.starts_on>=p_from_semester_start
    )
  for update of l;

  if exists (
    select 1
    from public.lesson_rights r
    where r.student_id=p_student_id
      and r.origin='carryover'::public.lesson_right_origin
      and (
        exists (
          select 1 from public.student_semester_plans sp
          cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
          where sp.student_id=p_student_id
            and sp.semester_id=r.source_semester_id
            and bounds.starts_on>=p_from_semester_start
        )
        or exists (
          select 1 from public.student_semester_plans sp
          cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
          where sp.student_id=p_student_id
            and sp.semester_id=r.usable_semester_id
            and bounds.starts_on>=p_from_semester_start
        )
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_CARRYOVER_UNSAFE';
  end if;

  if exists (
    select 1
    from public.lesson_rights child
    join public.lesson_rights source on source.id=child.source_right_id
    where source.student_id=p_student_id
      and source.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
      and exists (
        select 1 from public.student_semester_plans sp
        cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
        where sp.student_id=p_student_id
          and sp.semester_id=source.source_semester_id
          and bounds.starts_on>=p_from_semester_start
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_DERIVED_RIGHT_UNSAFE';
  end if;

  if exists (
    select 1
    from public.lessons m
    join public.lesson_rights r on r.id=m.manual_makeup_right_id
    where r.student_id=p_student_id
      and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
      and exists (
        select 1 from public.student_semester_plans sp
        cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
        where sp.student_id=p_student_id
          and sp.semester_id=r.source_semester_id
          and bounds.starts_on>=p_from_semester_start
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_MAKEUP_RIGHT_UNSAFE';
  end if;

  if exists (
    select 1
    from public.lesson_rebooking_credits c
    join public.lessons l on l.id=c.source_lesson_id
    join public.lesson_rights r on r.id=l.lesson_right_id
    where r.student_id=p_student_id
      and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
      and exists (
        select 1 from public.student_semester_plans sp
        cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
        where sp.student_id=p_student_id
          and sp.semester_id=r.source_semester_id
          and bounds.starts_on>=p_from_semester_start
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_LEGACY_CREDIT_UNSAFE';
  end if;

  if exists (
    select 1
    from public.lesson_rights r
    join public.student_semester_plans sp
      on sp.student_id=r.student_id and sp.semester_id=r.source_semester_id
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
    where r.student_id=p_student_id
      and bounds.starts_on>=p_from_semester_start
      and r.origin='flex_base'::public.lesson_right_origin
      and (
        sp.student_type_snapshot<>'flex'::public.student_type
        or r.branch_id is distinct from sp.branch_id
        or r.usable_semester_id is distinct from r.source_semester_id
        or r.schedule_slot_id is not null
        or r.source_right_id is not null
        or r.status<>'available'::public.lesson_right_status
        or exists (select 1 from public.lessons l where l.lesson_right_id=r.id)
        or exists (select 1 from public.lesson_cancellation_events e where e.lesson_right_id=r.id)
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_FLEX_MATERIALIZATION_UNSAFE';
  end if;

  if exists (
    select 1
    from public.lesson_rights r
    join public.student_semester_plans sp
      on sp.student_id=r.student_id and sp.semester_id=r.source_semester_id
    cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
    where r.student_id=p_student_id
      and bounds.starts_on>=p_from_semester_start
      and r.origin='regular_base'::public.lesson_right_origin
      and not (
        sp.student_type_snapshot='regular'::public.student_type
        and r.branch_id is not distinct from sp.branch_id
        and r.usable_semester_id is not distinct from r.source_semester_id
        and r.schedule_slot_id is not null
        and r.source_right_id is null
        and (
          (
            r.status='reserved'::public.lesson_right_status
            and (select count(*) from public.lessons l where l.lesson_right_id=r.id)=1
            and exists (
              select 1 from public.lessons l
              where l.lesson_right_id=r.id
                and l.lesson_type='regular'::public.lesson_type
                and l.status='scheduled'::public.lesson_status
                and l.rescheduled_by is null
                and l.canceled_at is null
                and l.cancellation_reason is null
            )
            and not exists (select 1 from public.lesson_cancellation_events e where e.lesson_right_id=r.id)
          )
          or
          (
            r.status='available'::public.lesson_right_status
            and (select count(*) from public.lessons l where l.lesson_right_id=r.id)=1
            and exists (
              select 1 from public.lessons l
              where l.lesson_right_id=r.id
                and l.lesson_type='regular'::public.lesson_type
                and l.status='canceled'::public.lesson_status
                and l.rescheduled_by is null
                and l.canceled_at is not null
                and l.cancellation_reason like 'AUTO_CLOSURE:%'
            )
            and (select count(*) from public.lesson_cancellation_events e where e.lesson_right_id=r.id)=1
            and exists (
              select 1
              from public.lesson_cancellation_events e
              join public.lessons l on l.lesson_right_id=e.lesson_right_id
              where e.lesson_right_id=r.id
                and e.origin='academy'::public.lesson_cancellation_origin
                and e.counts_toward_limit=false
                and e.reason=l.cancellation_reason
            )
          )
        )
      )
  ) then
    raise exception using errcode='P0001', message='FORESTRING_NEXT_TYPE_CHANGE_REGULAR_MATERIALIZATION_UNSAFE';
  end if;

  delete from public.lesson_cancellation_events e
  using public.lesson_rights r
  where e.lesson_right_id=r.id
    and r.student_id=p_student_id
    and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
    and exists (
      select 1 from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where sp.student_id=p_student_id
        and sp.semester_id=r.source_semester_id
        and bounds.starts_on>=p_from_semester_start
    );
  get diagnostics v_auto_cancellation_event_count=row_count;

  delete from public.lessons l
  using public.lesson_rights r
  where l.lesson_right_id=r.id
    and r.student_id=p_student_id
    and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
    and exists (
      select 1 from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where sp.student_id=p_student_id
        and sp.semester_id=r.source_semester_id
        and bounds.starts_on>=p_from_semester_start
    );
  get diagnostics v_deleted_lesson_count=row_count;

  delete from public.lesson_rights r
  where r.student_id=p_student_id
    and r.origin in ('regular_base'::public.lesson_right_origin,'flex_base'::public.lesson_right_origin)
    and exists (
      select 1 from public.student_semester_plans sp
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where sp.student_id=p_student_id
        and sp.semester_id=r.source_semester_id
        and bounds.starts_on>=p_from_semester_start
    );
  get diagnostics v_deleted_right_count=row_count;

  delete from public.student_semester_plans sp
  where sp.student_id=p_student_id
    and exists (
      select 1
      from private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where bounds.starts_on>p_from_semester_start
    );
  get diagnostics v_deleted_later_plan_count=row_count;

  return jsonb_build_object(
    'deletedLessonCount',v_deleted_lesson_count,
    'deletedRightCount',v_deleted_right_count,
    'deletedLaterPlanCount',v_deleted_later_plan_count,
    'removedProvisionalCancellationEventCount',v_auto_cancellation_event_count
  );
end;
$$;

revoke execute on function private.clear_future_student_type_materialization(uuid,date) from public, anon, authenticated;

create or replace function public.get_next_semester_student_type_plan(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_branch_id uuid;
  v_student_type public.student_type;
  v_status public.student_status;
  v_profile_active boolean;
  v_withdrawal_date date;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_current_semester_id uuid;
  v_current_code text;
  v_current_start date;
  v_current_end date;
  v_next_semester_id uuid;
  v_next_code text;
  v_next_start date;
  v_next_end date;
  v_plan public.student_semester_plans%rowtype;
  v_planned_type public.student_type;
  v_flex_count integer;
  v_flex_duration integer;
  v_default_flex_count integer;
  v_default_flex_duration integer;
  v_regular_schedule_count integer := 0;
  v_teacher_id uuid;
  v_teacher_name text;
  v_teacher_assignment_covers_semester boolean := false;
begin
  if v_actor_id is null then
    raise exception using errcode='P0001',message='FORESTRING_AUTH_REQUIRED';
  end if;
  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p where p.id=v_actor_id and p.is_active=true;
  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001',message='FORESTRING_STAFF_REQUIRED';
  end if;

  select p.branch_id,s.student_type,s.status,p.is_active,s.withdrawal_date
  into v_branch_id,v_student_type,v_status,v_profile_active,v_withdrawal_date
  from public.students s join public.profiles p on p.id=s.id
  where s.id=p_student_id;
  if not found then raise exception using errcode='P0001',message='FORESTRING_STUDENT_NOT_FOUND'; end if;
  if not v_profile_active or v_status<>'active'::public.student_status then
    raise exception using errcode='P0001',message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;
  if v_branch_id is null then raise exception using errcode='P0001',message='FORESTRING_STUDENT_BRANCH_REQUIRED'; end if;
  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_branch_id then
    raise exception using errcode='P0001',message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select sem.id,sem.code,bounds.starts_on,bounds.ends_on
  into v_current_semester_id,v_current_code,v_current_start,v_current_end
  from public.semesters sem
  cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) bounds
  where v_today between bounds.starts_on and bounds.ends_on
  order by bounds.starts_on desc limit 1;
  if v_current_semester_id is null then
    raise exception using errcode='P0001',message='FORESTRING_CURRENT_SEMESTER_NOT_FOUND';
  end if;

  select sem.id,sem.code,bounds.starts_on,bounds.ends_on
  into v_next_semester_id,v_next_code,v_next_start,v_next_end
  from public.semesters sem
  cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) bounds
  where bounds.starts_on=v_current_end+1
  order by bounds.starts_on limit 1;
  if v_next_semester_id is null then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_SEMESTER_NOT_FOUND';
  end if;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.student_id=p_student_id and sp.semester_id=v_next_semester_id;

  if found then
    v_planned_type:=v_plan.student_type_snapshot;
    v_flex_count:=v_plan.flex_base_right_count;
    v_flex_duration:=v_plan.flex_duration_minutes;
  else
    v_planned_type:=v_student_type;
  end if;

  select sp.flex_base_right_count,sp.flex_duration_minutes
  into v_default_flex_count,v_default_flex_duration
  from public.student_semester_plans sp
  cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
  where sp.student_id=p_student_id
    and sp.student_type_snapshot='flex'::public.student_type
    and sp.flex_base_right_count is not null
    and sp.flex_duration_minutes is not null
    and bounds.starts_on<v_next_start
  order by bounds.starts_on desc
  limit 1;

  select count(*)::integer into v_regular_schedule_count
  from public.regular_schedule_slots rs
  where rs.student_id=p_student_id and rs.branch_id=v_branch_id
    and rs.starts_on<=v_next_end
    and (rs.ends_on is null or rs.ends_on>=v_next_start);

  select a.teacher_id,tp.display_name,
         (a.starts_on<=v_next_start and (a.ends_on is null or a.ends_on>=v_next_end))
  into v_teacher_id,v_teacher_name,v_teacher_assignment_covers_semester
  from public.teacher_student_assignments a
  join public.profiles tp on tp.id=a.teacher_id
  where a.student_id=p_student_id and a.branch_id=v_branch_id
    and a.starts_on<=v_next_start and (a.ends_on is null or a.ends_on>=v_next_start)
  order by a.starts_on desc
  limit 1;

  return jsonb_build_object(
    'studentId',p_student_id,
    'currentStudentType',v_student_type,
    'currentSemesterId',v_current_semester_id,
    'currentSemesterCode',v_current_code,
    'currentSemesterStartsOn',v_current_start,
    'currentSemesterEndsOn',v_current_end,
    'nextSemesterId',v_next_semester_id,
    'nextSemesterCode',v_next_code,
    'nextSemesterStartsOn',v_next_start,
    'nextSemesterEndsOn',v_next_end,
    'nextPlanId',case when v_plan.id is null then null else v_plan.id end,
    'nextPlanStatus',case when v_plan.id is null then null else v_plan.status end,
    'plannedStudentType',v_planned_type,
    'flexBaseRightCount',v_flex_count,
    'flexDurationMinutes',v_flex_duration,
    'defaultFlexBaseRightCount',coalesce(v_default_flex_count,4),
    'defaultFlexDurationMinutes',coalesce(v_default_flex_duration,30),
    'regularScheduleCount',v_regular_schedule_count,
    'teacherId',v_teacher_id,
    'teacherName',v_teacher_name,
    'teacherAssignmentCoversSemester',coalesce(v_teacher_assignment_covers_semester,false),
    'withdrawalDate',v_withdrawal_date,
    'canChange',v_today<v_next_start and (v_withdrawal_date is null or v_withdrawal_date>v_next_end)
  );
end;
$$;

revoke execute on function public.get_next_semester_student_type_plan(uuid) from public, anon;
grant execute on function public.get_next_semester_student_type_plan(uuid) to authenticated;

create or replace function public.set_next_semester_student_type(
  p_student_id uuid,
  p_target_type public.student_type,
  p_flex_base_right_count integer default null,
  p_flex_duration_minutes integer default null,
  p_regular_schedules jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_actor_branch_id uuid;
  v_branch_id uuid;
  v_current_type public.student_type;
  v_status public.student_status;
  v_profile_active boolean;
  v_withdrawal_date date;
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_current_semester_id uuid;
  v_current_end date;
  v_next_semester_id uuid;
  v_next_code text;
  v_next_start date;
  v_next_end date;
  v_plan public.student_semester_plans%rowtype;
  v_previous_planned_type public.student_type;
  v_previous_flex_count integer;
  v_previous_flex_duration integer;
  v_cleanup jsonb;
  v_activation jsonb;
  v_regular_schedule_count integer := 0;
  v_created_regular_schedule_count integer := 0;
  v_teacher_id uuid;
  v_teacher_withdrawal_date date;
  v_item jsonb;
  v_weekday integer;
  v_start_time time;
  v_duration integer;
  v_signature text;
  v_seen_signatures text[] := '{}'::text[];
  v_slot_id uuid;
  v_plan_id uuid;
  v_changed boolean := true;
begin
  if v_actor_id is null then raise exception using errcode='P0001',message='FORESTRING_AUTH_REQUIRED'; end if;
  perform private.require_effective_actor(v_actor_id);

  select p.role,p.branch_id into v_actor_role,v_actor_branch_id
  from public.profiles p where p.id=v_actor_id and p.is_active=true;
  if not found or v_actor_role not in ('master'::public.user_role,'manager'::public.user_role) then
    raise exception using errcode='P0001',message='FORESTRING_STAFF_REQUIRED';
  end if;

  select p.branch_id,s.student_type,s.status,p.is_active,s.withdrawal_date
  into v_branch_id,v_current_type,v_status,v_profile_active,v_withdrawal_date
  from public.students s join public.profiles p on p.id=s.id
  where s.id=p_student_id
  for update of s,p;
  if not found then raise exception using errcode='P0001',message='FORESTRING_STUDENT_NOT_FOUND'; end if;
  if not v_profile_active or v_status<>'active'::public.student_status then
    raise exception using errcode='P0001',message='FORESTRING_ACTIVE_STUDENT_REQUIRED';
  end if;
  if v_branch_id is null then raise exception using errcode='P0001',message='FORESTRING_STUDENT_BRANCH_REQUIRED'; end if;
  if v_actor_role='manager'::public.user_role and v_actor_branch_id is distinct from v_branch_id then
    raise exception using errcode='P0001',message='FORESTRING_MANAGER_BRANCH_FORBIDDEN';
  end if;

  select sem.id,bounds.ends_on into v_current_semester_id,v_current_end
  from public.semesters sem
  cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) bounds
  where v_today between bounds.starts_on and bounds.ends_on
  order by bounds.starts_on desc limit 1;
  if v_current_semester_id is null then raise exception using errcode='P0001',message='FORESTRING_CURRENT_SEMESTER_NOT_FOUND'; end if;

  select sem.id,sem.code,bounds.starts_on,bounds.ends_on
  into v_next_semester_id,v_next_code,v_next_start,v_next_end
  from public.semesters sem
  cross join lateral private.get_effective_semester_bounds(v_branch_id,sem.id) bounds
  where bounds.starts_on=v_current_end+1
  order by bounds.starts_on limit 1;
  if v_next_semester_id is null then raise exception using errcode='P0001',message='FORESTRING_NEXT_SEMESTER_NOT_FOUND'; end if;
  if v_today>=v_next_start then raise exception using errcode='P0001',message='FORESTRING_NEXT_TYPE_CHANGE_AFTER_SEMESTER_START'; end if;
  if v_withdrawal_date is not null and v_withdrawal_date<=v_next_end then
    raise exception using errcode='P0001',message='FORESTRING_NEXT_TYPE_CHANGE_WITHDRAWAL_CONFLICT';
  end if;

  if p_target_type is null then raise exception using errcode='P0001',message='FORESTRING_TARGET_STUDENT_TYPE_REQUIRED'; end if;

  if p_target_type='flex'::public.student_type then
    if p_flex_base_right_count is null or p_flex_base_right_count<=0 then
      raise exception using errcode='P0001',message='FORESTRING_INVALID_FLEX_RIGHT_COUNT';
    end if;
    if p_flex_duration_minutes is null or p_flex_duration_minutes<=0 or p_flex_duration_minutes>720 or mod(p_flex_duration_minutes,15)<>0 then
      raise exception using errcode='P0001',message='FORESTRING_INVALID_FLEX_DURATION';
    end if;
  end if;

  select * into v_plan
  from public.student_semester_plans sp
  where sp.student_id=p_student_id and sp.semester_id=v_next_semester_id
  for update;

  if found then
    v_plan_id:=v_plan.id;
    v_previous_planned_type:=v_plan.student_type_snapshot;
    v_previous_flex_count:=v_plan.flex_base_right_count;
    v_previous_flex_duration:=v_plan.flex_duration_minutes;
  else
    v_previous_planned_type:=v_current_type;
  end if;

  select count(*)::integer into v_regular_schedule_count
  from public.regular_schedule_slots rs
  where rs.student_id=p_student_id and rs.branch_id=v_branch_id
    and rs.starts_on<=v_next_end
    and (rs.ends_on is null or rs.ends_on>=v_next_start);

  if found
     and v_plan.status='active'::public.student_semester_plan_status
     and v_previous_planned_type=p_target_type
     and (
       (p_target_type='regular'::public.student_type and v_regular_schedule_count>0)
       or
       (p_target_type='flex'::public.student_type
         and v_previous_flex_count=p_flex_base_right_count
         and v_previous_flex_duration=p_flex_duration_minutes)
     ) then
    return jsonb_build_object(
      'changed',false,'studentId',p_student_id,'currentStudentType',v_current_type,
      'plannedStudentType',p_target_type,'nextSemesterId',v_next_semester_id,
      'nextSemesterCode',v_next_code,'nextSemesterStartsOn',v_next_start,
      'regularScheduleCount',v_regular_schedule_count,
      'flexBaseRightCount',v_plan.flex_base_right_count,
      'flexDurationMinutes',v_plan.flex_duration_minutes
    );
  end if;

  v_cleanup:=private.clear_future_student_type_materialization(p_student_id,v_next_start);

  if v_plan_id is null then
    insert into public.student_semester_plans(
      student_id,semester_id,branch_id,student_type_snapshot,
      flex_base_right_count,flex_duration_minutes,status,created_by,updated_by
    ) values (
      p_student_id,v_next_semester_id,v_branch_id,p_target_type,
      case when p_target_type='flex'::public.student_type then p_flex_base_right_count else null end,
      case when p_target_type='flex'::public.student_type then p_flex_duration_minutes else null end,
      'planned'::public.student_semester_plan_status,v_actor_id,v_actor_id
    ) returning id into v_plan_id;
  else
    update public.student_semester_plans sp
    set student_type_snapshot=p_target_type,
        flex_base_right_count=case when p_target_type='flex'::public.student_type then p_flex_base_right_count else null end,
        flex_duration_minutes=case when p_target_type='flex'::public.student_type then p_flex_duration_minutes else null end,
        status='planned'::public.student_semester_plan_status,
        updated_by=v_actor_id
    where sp.id=v_plan_id;
  end if;

  if p_target_type='regular'::public.student_type then
    select count(*)::integer into v_regular_schedule_count
    from public.regular_schedule_slots rs
    where rs.student_id=p_student_id and rs.branch_id=v_branch_id
      and rs.starts_on<=v_next_end
      and (rs.ends_on is null or rs.ends_on>=v_next_start);

    if v_regular_schedule_count=0 then
      if p_regular_schedules is null or jsonb_typeof(p_regular_schedules)<>'array' or jsonb_array_length(p_regular_schedules)=0 then
        raise exception using errcode='P0001',message='FORESTRING_NEXT_REGULAR_SCHEDULES_REQUIRED';
      end if;

      select a.teacher_id,t.withdrawal_date
      into v_teacher_id,v_teacher_withdrawal_date
      from public.teacher_student_assignments a
      join public.teachers t on t.id=a.teacher_id
      join public.profiles tp on tp.id=a.teacher_id
      where a.student_id=p_student_id and a.branch_id=v_branch_id
        and a.starts_on<=v_next_start
        and (a.ends_on is null or a.ends_on>=v_next_end)
        and tp.is_active=true and tp.branch_id=v_branch_id
      order by a.starts_on desc limit 1;

      if v_teacher_id is null then
        raise exception using errcode='P0001',message='FORESTRING_NEXT_REGULAR_TEACHER_ASSIGNMENT_REQUIRED';
      end if;
      if v_teacher_withdrawal_date is not null and v_teacher_withdrawal_date<=v_next_end then
        raise exception using errcode='P0001',message='FORESTRING_ASSIGNMENT_AFTER_TEACHER_WITHDRAWAL';
      end if;

      for v_item in select value from jsonb_array_elements(p_regular_schedules)
      loop
        begin
          v_weekday:=(v_item->>'weekday')::integer;
          v_start_time:=(v_item->>'startTime')::time;
          v_duration:=(v_item->>'durationMinutes')::integer;
        exception when others then
          raise exception using errcode='P0001',message='FORESTRING_INVALID_REGULAR_SCHEDULE';
        end;

        if v_weekday not between 1 and 7 then raise exception using errcode='P0001',message='FORESTRING_INVALID_WEEKDAY'; end if;
        if extract(second from v_start_time)<>0 or mod(extract(minute from v_start_time)::integer,15)<>0 then
          raise exception using errcode='P0001',message='FORESTRING_REGULAR_START_NOT_15_MINUTE_ALIGNED';
        end if;
        if v_duration<=0 or v_duration>720 or mod(v_duration,15)<>0 then
          raise exception using errcode='P0001',message='FORESTRING_INVALID_REGULAR_DURATION';
        end if;
        if extract(hour from v_start_time)::integer*60+extract(minute from v_start_time)::integer+v_duration>1440 then
          raise exception using errcode='P0001',message='FORESTRING_REGULAR_LESSON_CROSSES_MIDNIGHT';
        end if;

        v_signature:=v_weekday::text||'|'||v_start_time::text||'|'||v_duration::text;
        if v_signature=any(v_seen_signatures) then
          raise exception using errcode='P0001',message='FORESTRING_DUPLICATE_REGULAR_SCHEDULE';
        end if;
        v_seen_signatures:=array_append(v_seen_signatures,v_signature);

        insert into public.regular_schedule_slots(student_id,branch_id,starts_on,ends_on,created_by)
        values(p_student_id,v_branch_id,v_next_start,null,v_actor_id)
        returning id into v_slot_id;

        insert into public.lesson_series(
          student_id,teacher_id,weekday,start_time,duration_minutes,
          effective_from,effective_until,branch_id,schedule_slot_id
        ) values (
          p_student_id,v_teacher_id,v_weekday,v_start_time,v_duration,
          v_next_start,null,v_branch_id,v_slot_id
        );

        v_created_regular_schedule_count:=v_created_regular_schedule_count+1;
      end loop;

      v_regular_schedule_count:=v_created_regular_schedule_count;
    end if;

    v_activation:=public.activate_student_semester_plan(v_plan_id);
  else
    v_activation:=public.activate_student_semester_plan(v_plan_id);
  end if;

  insert into public.audit_events(
    subject_profile_id,branch_id,semester_id,event_type,effective_on,actor_id,details
  ) values (
    p_student_id,v_branch_id,v_next_semester_id,'STUDENT_NEXT_SEMESTER_TYPE_PLANNED',v_next_start,v_actor_id,
    jsonb_build_object(
      'currentStudentType',v_current_type,
      'previousPlannedType',v_previous_planned_type,
      'plannedStudentType',p_target_type,
      'previousFlexBaseRightCount',v_previous_flex_count,
      'previousFlexDurationMinutes',v_previous_flex_duration,
      'flexBaseRightCount',case when p_target_type='flex'::public.student_type then p_flex_base_right_count else null end,
      'flexDurationMinutes',case when p_target_type='flex'::public.student_type then p_flex_duration_minutes else null end,
      'regularScheduleCount',v_regular_schedule_count,
      'createdRegularScheduleCount',v_created_regular_schedule_count,
      'cleanup',v_cleanup,
      'activation',v_activation
    )
  );

  return jsonb_build_object(
    'changed',v_changed,
    'studentId',p_student_id,
    'currentStudentType',v_current_type,
    'previousPlannedType',v_previous_planned_type,
    'plannedStudentType',p_target_type,
    'nextSemesterId',v_next_semester_id,
    'nextSemesterCode',v_next_code,
    'nextSemesterStartsOn',v_next_start,
    'regularScheduleCount',v_regular_schedule_count,
    'createdRegularScheduleCount',v_created_regular_schedule_count,
    'flexBaseRightCount',case when p_target_type='flex'::public.student_type then p_flex_base_right_count else null end,
    'flexDurationMinutes',case when p_target_type='flex'::public.student_type then p_flex_duration_minutes else null end,
    'cleanup',v_cleanup,
    'activation',v_activation
  );
end;
$$;

revoke execute on function public.set_next_semester_student_type(uuid,public.student_type,integer,integer,jsonb) from public, anon;
grant execute on function public.set_next_semester_student_type(uuid,public.student_type,integer,integer,jsonb) to authenticated;

alter function public.transition_student_semester(uuid,uuid) rename to transition_student_semester_core;
revoke execute on function public.transition_student_semester_core(uuid,uuid) from public, anon, authenticated;

create or replace function public.transition_student_semester(p_source_plan_id uuid,p_target_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
  v_student_id uuid;
  v_target_type public.student_type;
  v_target_start date;
  v_closed_series_count integer := 0;
  v_closed_slot_count integer := 0;
  v_deleted_future_series_count integer := 0;
  v_tombstoned_future_series_count integer := 0;
  v_deleted_future_slot_count integer := 0;
  v_tombstoned_future_slot_count integer := 0;
begin
  v_result:=public.transition_student_semester_core(p_source_plan_id,p_target_plan_id);
  v_student_id:=(v_result->>'studentId')::uuid;
  v_target_type:=(v_result->>'studentType')::public.student_type;
  v_target_start:=(v_result->>'effectiveOn')::date;

  if v_target_type='flex'::public.student_type then
    if exists (
      select 1
      from public.lesson_rights r
      join public.lessons l on l.lesson_right_id=r.id
      join public.student_semester_plans sp on sp.student_id=r.student_id and sp.semester_id=r.source_semester_id
      cross join lateral private.get_effective_semester_bounds(sp.branch_id,sp.semester_id) bounds
      where r.student_id=v_student_id
        and r.origin='regular_base'::public.lesson_right_origin
        and bounds.starts_on>=v_target_start
    ) then
      raise exception using errcode='P0001',message='FORESTRING_FLEX_TRANSITION_HAS_FUTURE_REGULAR_MATERIALIZATION';
    end if;

    update public.lesson_series ls
    set effective_until=v_target_start-1
    where ls.student_id=v_student_id
      and ls.effective_from<v_target_start
      and (ls.effective_until is null or ls.effective_until>=v_target_start);
    get diagnostics v_closed_series_count=row_count;

    update public.regular_schedule_slots rs
    set ends_on=v_target_start-1
    where rs.student_id=v_student_id
      and rs.starts_on<v_target_start
      and (rs.ends_on is null or rs.ends_on>=v_target_start);
    get diagnostics v_closed_slot_count=row_count;

    delete from public.lesson_series ls
    where ls.student_id=v_student_id
      and ls.effective_from>=v_target_start
      and not exists(select 1 from public.lessons l where l.series_id=ls.id)
      and not exists(select 1 from public.lesson_rebooking_credits c where c.source_series_id=ls.id);
    get diagnostics v_deleted_future_series_count=row_count;

    update public.lesson_series ls
    set effective_until=ls.effective_from
    where ls.student_id=v_student_id
      and ls.effective_from>=v_target_start
      and (ls.effective_until is null or ls.effective_until>ls.effective_from);
    get diagnostics v_tombstoned_future_series_count=row_count;

    delete from public.regular_schedule_slots rs
    where rs.student_id=v_student_id
      and rs.starts_on>=v_target_start
      and not exists(select 1 from public.lesson_rights r where r.schedule_slot_id=rs.id)
      and not exists(select 1 from public.lesson_series ls where ls.schedule_slot_id=rs.id);
    get diagnostics v_deleted_future_slot_count=row_count;

    update public.regular_schedule_slots rs
    set ends_on=rs.starts_on
    where rs.student_id=v_student_id
      and rs.starts_on>=v_target_start
      and (rs.ends_on is null or rs.ends_on>rs.starts_on);
    get diagnostics v_tombstoned_future_slot_count=row_count;

    v_result:=v_result||jsonb_build_object(
      'flexScheduleCleanup',jsonb_build_object(
        'closedSeriesCount',v_closed_series_count,
        'closedSlotCount',v_closed_slot_count,
        'deletedFutureSeriesCount',v_deleted_future_series_count,
        'tombstonedFutureSeriesCount',v_tombstoned_future_series_count,
        'deletedFutureSlotCount',v_deleted_future_slot_count,
        'tombstonedFutureSlotCount',v_tombstoned_future_slot_count
      )
    );
  end if;

  return v_result;
end;
$$;

revoke execute on function public.transition_student_semester(uuid,uuid) from public, anon;
grant execute on function public.transition_student_semester(uuid,uuid) to authenticated;
