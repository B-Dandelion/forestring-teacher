create or replace function private.calendar_semester_is_materialized(
  p_semester_id uuid,
  p_branch_id uuid default null::uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_branch record;
  v_start date;
  v_has_materialized boolean;
begin
  if exists (
    select 1 from public.student_semester_plans sp
    where sp.semester_id=p_semester_id
      and sp.status='completed'::public.student_semester_plan_status
      and (p_branch_id is null or sp.branch_id=p_branch_id)
  ) then return true; end if;

  for v_branch in
    select b.id from public.branches b
    where p_branch_id is null or b.id=p_branch_id
  loop
    select exists(
      select 1 from public.student_semester_plans sp
      where sp.semester_id=p_semester_id and sp.branch_id=v_branch.id
        and sp.status in ('active'::public.student_semester_plan_status,'completed'::public.student_semester_plan_status)
    ) or exists(
      select 1 from public.lesson_rights r
      where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
        and r.branch_id=v_branch.id
    ) or exists(
      select 1 from public.lesson_rebooking_credits c
      where (c.source_semester_id=p_semester_id or c.usable_semester_id=p_semester_id)
        and coalesce(c.branch_id,(select p.branch_id from public.profiles p where p.id=c.student_id))=v_branch.id
    ) into v_has_materialized;

    if not v_has_materialized then continue; end if;

    select e.starts_on into v_start
    from private.get_effective_semester_bounds(v_branch.id,p_semester_id) e;

    if not found or v_start <= v_today then return true; end if;
  end loop;

  -- Future regular lessons are reconciled by deferred calendar triggers.
  -- Keep non-regular entitlements conservative until their booking-window
  -- semantics are explicitly reconciled as well.
  if exists (
    select 1 from public.lesson_rebooking_credits c
    where (c.source_semester_id=p_semester_id or c.usable_semester_id=p_semester_id)
      and (p_branch_id is null or coalesce(c.branch_id,(select p.branch_id from public.profiles p where p.id=c.student_id))=p_branch_id)
  ) then return true; end if;

  if exists (
    select 1 from public.lesson_rights r
    where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
      and (p_branch_id is null or r.branch_id=p_branch_id)
      and r.origin='flex_base'::public.lesson_right_origin
      and (
        r.status <> 'available'::public.lesson_right_status
        or exists(select 1 from public.lesson_rights child where child.source_right_id=r.id)
        or exists(select 1 from public.lessons l where l.lesson_right_id=r.id)
      )
  ) then return true; end if;

  if exists (
    select 1 from public.lesson_rights r
    where (r.source_semester_id=p_semester_id or r.usable_semester_id=p_semester_id)
      and (p_branch_id is null or r.branch_id=p_branch_id)
      and r.origin='carryover'::public.lesson_right_origin
  ) then return true; end if;

  return false;
end;
$function$;

create or replace function private.rebuild_future_regular_semester(
  p_semester_id uuid,
  p_branch_id uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_start date;
  v_end date;
  v_plan record;
  v_slot record;
  v_right record;
  v_candidate record;
  v_original record;
  v_slot_count integer;
  v_right_count integer;
  v_candidate_count integer;
  v_reconciled integer := 0;
  v_preserved integer := 0;
  v_default_following boolean;
begin
  select e.starts_on,e.ends_on into v_start,v_end
  from private.get_effective_semester_bounds(p_branch_id,p_semester_id) e;
  if not found then raise exception using errcode='P0001',message='FORESTRING_SEMESTER_NOT_FOUND'; end if;

  if not exists (
    select 1 from public.student_semester_plans sp
    where sp.semester_id=p_semester_id and sp.branch_id=p_branch_id
      and sp.status='active'::public.student_semester_plan_status
      and sp.student_type_snapshot='regular'::public.student_type
  ) then return 0; end if;

  if v_start <= v_today then
    raise exception using errcode='P0001',message='FORESTRING_CALENDAR_REBUILD_REQUIRES_FUTURE_SEMESTER';
  end if;

  for v_plan in
    select sp.id,sp.student_id
    from public.student_semester_plans sp
    where sp.semester_id=p_semester_id and sp.branch_id=p_branch_id
      and sp.status='active'::public.student_semester_plan_status
      and sp.student_type_snapshot='regular'::public.student_type
    order by sp.student_id
    for update
  loop
    select count(*)::integer into v_slot_count
    from public.regular_schedule_slots rs
    where rs.student_id=v_plan.student_id
      and rs.branch_id=p_branch_id
      and rs.starts_on<=v_end
      and (rs.ends_on is null or rs.ends_on>=v_start);

    if v_slot_count=0 then
      raise exception using errcode='P0001',message='FORESTRING_REGULAR_PLAN_REQUIRES_SCHEDULE_SLOT',detail='plan_id='||v_plan.id::text;
    end if;

    -- If the new calendar would change which logical slots belong to the
    -- semester, do not guess how to rewrite used entitlements.
    select count(distinct r.schedule_slot_id)::integer into v_right_count
    from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.branch_id=p_branch_id
      and r.source_semester_id=p_semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    if v_right_count <> v_slot_count then
      raise exception using errcode='P0001',message='FORESTRING_CALENDAR_CHANGE_ALTERS_SLOT_MEMBERSHIP',detail='plan_id='||v_plan.id::text;
    end if;

    for v_slot in
      select rs.id
      from public.regular_schedule_slots rs
      where rs.student_id=v_plan.student_id
        and rs.branch_id=p_branch_id
        and rs.starts_on<=v_end
        and (rs.ends_on is null or rs.ends_on>=v_start)
      order by rs.id
    loop
      select count(*)::integer into v_right_count
      from public.lesson_rights r
      where r.student_id=v_plan.student_id
        and r.branch_id=p_branch_id
        and r.source_semester_id=p_semester_id
        and r.schedule_slot_id=v_slot.id
        and r.origin='regular_base'::public.lesson_right_origin;

      if v_right_count <> 4 then
        raise exception using errcode='P0001',message='FORESTRING_ACTIVE_PLAN_MATERIALIZATION_INCOMPLETE',detail='schedule_slot_id='||v_slot.id::text||', right_count='||v_right_count::text;
      end if;

      select count(*)::integer into v_candidate_count
      from (
        with teaching_dates as (
          select d::date lesson_date
          from pg_catalog.generate_series(v_start::timestamp,v_end::timestamp,interval '1 day') d
          where not exists (
            select 1 from public.closure_periods cp
            where cp.branch_id=p_branch_id
              and cp.semester_id=p_semester_id
              and cp.closure_kind='instructional_break'::public.closure_kind
              and d::date between cp.starts_on and cp.ends_on
          )
        )
        select td.lesson_date,ls.id
        from teaching_dates td
        join public.lesson_series ls
          on ls.schedule_slot_id=v_slot.id
         and ls.student_id=v_plan.student_id
         and ls.branch_id=p_branch_id
         and td.lesson_date>=ls.effective_from
         and (ls.effective_until is null or td.lesson_date<=ls.effective_until)
         and extract(isodow from td.lesson_date)::integer=ls.weekday
        join public.regular_schedule_slots rs on rs.id=v_slot.id
        where td.lesson_date>=rs.starts_on
          and (rs.ends_on is null or td.lesson_date<=rs.ends_on)
      ) q;

      if v_candidate_count<>4 then
        raise exception using errcode='P0001',message='FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES',detail='schedule_slot_id='||v_slot.id::text||', candidate_count='||v_candidate_count::text;
      end if;

      for v_right in
        select r.*
        from public.lesson_rights r
        where r.student_id=v_plan.student_id
          and r.branch_id=p_branch_id
          and r.source_semester_id=p_semester_id
          and r.schedule_slot_id=v_slot.id
          and r.origin='regular_base'::public.lesson_right_origin
        order by r.sequence_no
        for update
      loop
        select q.* into v_candidate
        from (
          with teaching_dates as (
            select d::date lesson_date
            from pg_catalog.generate_series(v_start::timestamp,v_end::timestamp,interval '1 day') d
            where not exists (
              select 1 from public.closure_periods cp
              where cp.branch_id=p_branch_id
                and cp.semester_id=p_semester_id
                and cp.closure_kind='instructional_break'::public.closure_kind
                and d::date between cp.starts_on and cp.ends_on
            )
          ), raw as (
            select td.lesson_date,ls.id series_id,ls.teacher_id,ls.weekday,ls.start_time,ls.duration_minutes,
                   (td.lesson_date+ls.start_time) at time zone 'Asia/Seoul' starts_at
            from teaching_dates td
            join public.lesson_series ls
              on ls.schedule_slot_id=v_slot.id
             and ls.student_id=v_plan.student_id
             and ls.branch_id=p_branch_id
             and td.lesson_date>=ls.effective_from
             and (ls.effective_until is null or td.lesson_date<=ls.effective_until)
             and extract(isodow from td.lesson_date)::integer=ls.weekday
            join public.regular_schedule_slots rs on rs.id=v_slot.id
            where td.lesson_date>=rs.starts_on
              and (rs.ends_on is null or td.lesson_date<=rs.ends_on)
          )
          select row_number() over(order by raw.starts_at,raw.series_id)::integer sequence_no,
                 raw.*,raw.starts_at+pg_catalog.make_interval(mins=>raw.duration_minutes) ends_at
          from raw
        ) q
        where q.sequence_no=v_right.sequence_no;

        if not found then
          raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH',detail='right_id='||v_right.id::text;
        end if;

        select
          count(*)=1
          and bool_and(l.lesson_type='regular'::public.lesson_type)
          and bool_and(l.status='scheduled'::public.lesson_status)
          and bool_and(l.rescheduled_by is null)
          and bool_and(l.canceled_at is null)
          and not exists(select 1 from public.lesson_cancellation_events ce where ce.lesson_right_id=v_right.id)
          and not exists(select 1 from public.lesson_rights child where child.source_right_id=v_right.id)
          and not exists(select 1 from public.lessons ml where ml.manual_makeup_right_id=v_right.id)
          and not exists(select 1 from public.lesson_rebooking_credits c join public.lessons sl on sl.id=c.source_lesson_id where sl.lesson_right_id=v_right.id)
        into v_default_following
        from public.lessons l
        where l.lesson_right_id=v_right.id;

        v_default_following := coalesce(v_default_following,false)
          and v_right.status='reserved'::public.lesson_right_status;

        if v_default_following then
          if exists (
            select 1 from public.closure_periods cp
            where cp.branch_id=p_branch_id
              and cp.semester_id=p_semester_id
              and cp.closure_kind='ordinary'::public.closure_kind
              and v_candidate.lesson_date between cp.starts_on and cp.ends_on
          ) then
            raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_ON_CLOSURE',detail='date='||v_candidate.lesson_date::text;
          end if;

          if not exists (
            select 1 from public.teacher_work_hours wh
            where wh.teacher_id=v_candidate.teacher_id
              and wh.weekday=v_candidate.weekday
              and wh.start_time<=v_candidate.start_time
              and wh.end_time>=(v_candidate.ends_at at time zone 'Asia/Seoul')::time
          ) then
            raise exception using errcode='P0001',message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',detail='date='||v_candidate.lesson_date::text;
          end if;

          if exists (
            select 1 from public.blocked_periods bp
            where bp.teacher_id=v_candidate.teacher_id
              and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_candidate.starts_at,v_candidate.ends_at,'[)')
          ) then
            raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_BLOCKED',detail='starts_at='||v_candidate.starts_at::text;
          end if;

          update public.lesson_rights
          set duration_minutes=v_candidate.duration_minutes
          where id=v_right.id;

          begin
            update public.lessons
            set series_id=v_candidate.series_id,
                teacher_id=v_candidate.teacher_id,
                occurrence_at=v_candidate.starts_at,
                starts_at=v_candidate.starts_at,
                duration_minutes=v_candidate.duration_minutes
            where lesson_right_id=v_right.id;
          exception when exclusion_violation then
            raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT',detail='right_id='||v_right.id::text||', starts_at='||v_candidate.starts_at::text;
          end;

          v_reconciled:=v_reconciled+1;
        else
          select l.id,l.occurrence_at,(l.occurrence_at at time zone 'Asia/Seoul')::date occurrence_date
          into v_original
          from public.lessons l
          where l.lesson_right_id=v_right.id
            and l.lesson_type='regular'::public.lesson_type
            and l.occurrence_at is not null
          order by l.occurrence_at,l.id
          limit 1;

          if not found then
            raise exception using errcode='P0001',message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',detail='right_id='||v_right.id::text||', reason=no_original_occurrence';
          end if;

          if v_original.occurrence_date<v_start or v_original.occurrence_date>v_end
             or exists (
               select 1 from public.closure_periods cp
               where cp.branch_id=p_branch_id
                 and cp.semester_id=p_semester_id
                 and cp.closure_kind='instructional_break'::public.closure_kind
                 and v_original.occurrence_date between cp.starts_on and cp.ends_on
             ) then
            raise exception using errcode='P0001',message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',detail='right_id='||v_right.id::text||', occurrence_date='||v_original.occurrence_date::text;
          end if;

          v_preserved:=v_preserved+1;
        end if;
      end loop;
    end loop;
  end loop;

  insert into public.audit_events(branch_id,semester_id,event_type,effective_on,actor_id,details)
  values(p_branch_id,p_semester_id,'FUTURE_SEMESTER_RECONCILED',v_start,auth.uid(),jsonb_build_object('reconciledLessonCount',v_reconciled,'preservedUsedRightCount',v_preserved));

  return v_reconciled;
end;
$function$;

revoke all on function private.rebuild_future_regular_semester(uuid,uuid) from public,anon,authenticated;
