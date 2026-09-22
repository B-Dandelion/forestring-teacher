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
  v_series record;
  v_right record;
  v_candidate record;
  v_anchor_date date;
  v_original_date date;
  v_slot_count integer;
  v_distinct_right_slots integer;
  v_right_count integer;
  v_series_right_count integer;
  v_series_candidate_count integer;
  v_series_ordinal integer;
  v_processed_rights integer;
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

    select count(distinct r.schedule_slot_id)::integer into v_distinct_right_slots
    from public.lesson_rights r
    where r.student_id=v_plan.student_id
      and r.branch_id=p_branch_id
      and r.source_semester_id=p_semester_id
      and r.origin='regular_base'::public.lesson_right_origin;

    if v_slot_count=0 then
      raise exception using errcode='P0001',message='FORESTRING_REGULAR_PLAN_REQUIRES_SCHEDULE_SLOT',detail='plan_id='||v_plan.id::text;
    end if;

    if v_distinct_right_slots<>v_slot_count then
      raise exception using errcode='P0001',message='FORESTRING_CALENDAR_CHANGE_ALTERS_SLOT_MEMBERSHIP',detail='plan_id='||v_plan.id::text;
    end if;

    for v_slot in
      select rs.id,rs.starts_on,rs.ends_on
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

      if v_right_count<>4 then
        raise exception using errcode='P0001',message='FORESTRING_ACTIVE_PLAN_MATERIALIZATION_INCOMPLETE',detail='schedule_slot_id='||v_slot.id::text||', right_count='||v_right_count::text;
      end if;

      v_processed_rights:=0;

      for v_series in
        select ls.*
        from public.lesson_series ls
        where ls.schedule_slot_id=v_slot.id
          and ls.student_id=v_plan.student_id
          and ls.branch_id=p_branch_id
          and ls.effective_from<=v_end
          and (ls.effective_until is null or ls.effective_until>=v_start)
        order by ls.effective_from,ls.id
      loop
        select count(*)::integer into v_series_right_count
        from public.lesson_rights r
        where r.student_id=v_plan.student_id
          and r.branch_id=p_branch_id
          and r.source_semester_id=p_semester_id
          and r.schedule_slot_id=v_slot.id
          and r.origin='regular_base'::public.lesson_right_origin
          and exists (
            select 1
            from public.lessons l
            where l.lesson_right_id=r.id
              and l.lesson_type='regular'::public.lesson_type
              and (
                case
                  when r.status='reserved'::public.lesson_right_status
                   and l.status='scheduled'::public.lesson_status
                   and l.rescheduled_by is null
                   and l.canceled_at is null
                   and not exists(select 1 from public.lesson_cancellation_events ce where ce.lesson_right_id=r.id)
                  then (l.starts_at at time zone 'Asia/Seoul')::date
                  else (l.occurrence_at at time zone 'Asia/Seoul')::date
                end
              ) between v_series.effective_from and coalesce(v_series.effective_until,date '9999-12-31')
          );

        if v_series_right_count=0 then continue; end if;

        select count(*)::integer into v_series_candidate_count
        from pg_catalog.generate_series(
          greatest(v_start,v_slot.starts_on,v_series.effective_from)::timestamp,
          least(v_end,coalesce(v_slot.ends_on,v_end),coalesce(v_series.effective_until,v_end))::timestamp,
          interval '1 day'
        ) d
        where extract(isodow from d::date)::integer=v_series.weekday
          and not exists (
            select 1 from public.closure_periods cp
            where cp.branch_id=p_branch_id
              and cp.semester_id=p_semester_id
              and cp.closure_kind='instructional_break'::public.closure_kind
              and d::date between cp.starts_on and cp.ends_on
          );

        if v_series_candidate_count<v_series_right_count then
          raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH',detail='schedule_slot_id='||v_slot.id::text||', series_id='||v_series.id::text||', rights='||v_series_right_count::text||', candidates='||v_series_candidate_count::text;
        end if;

        v_series_ordinal:=0;

        for v_right in
          select r.*
          from public.lesson_rights r
          where r.student_id=v_plan.student_id
            and r.branch_id=p_branch_id
            and r.source_semester_id=p_semester_id
            and r.schedule_slot_id=v_slot.id
            and r.origin='regular_base'::public.lesson_right_origin
            and exists (
              select 1
              from public.lessons l
              where l.lesson_right_id=r.id
                and l.lesson_type='regular'::public.lesson_type
                and (
                  case
                    when r.status='reserved'::public.lesson_right_status
                     and l.status='scheduled'::public.lesson_status
                     and l.rescheduled_by is null
                     and l.canceled_at is null
                     and not exists(select 1 from public.lesson_cancellation_events ce where ce.lesson_right_id=r.id)
                    then (l.starts_at at time zone 'Asia/Seoul')::date
                    else (l.occurrence_at at time zone 'Asia/Seoul')::date
                  end
                ) between v_series.effective_from and coalesce(v_series.effective_until,date '9999-12-31')
            )
          order by r.sequence_no,r.id
          for update
        loop
          v_series_ordinal:=v_series_ordinal+1;
          v_processed_rights:=v_processed_rights+1;

          select d::date lesson_date,
                 (d::date+v_series.start_time) at time zone 'Asia/Seoul' starts_at,
                 ((d::date+v_series.start_time) at time zone 'Asia/Seoul')+pg_catalog.make_interval(mins=>v_series.duration_minutes) ends_at
          into v_candidate
          from pg_catalog.generate_series(
            greatest(v_start,v_slot.starts_on,v_series.effective_from)::timestamp,
            least(v_end,coalesce(v_slot.ends_on,v_end),coalesce(v_series.effective_until,v_end))::timestamp,
            interval '1 day'
          ) d
          where extract(isodow from d::date)::integer=v_series.weekday
            and not exists (
              select 1 from public.closure_periods cp
              where cp.branch_id=p_branch_id
                and cp.semester_id=p_semester_id
                and cp.closure_kind='instructional_break'::public.closure_kind
                and d::date between cp.starts_on and cp.ends_on
            )
          order by d::date
          offset v_series_ordinal-1
          limit 1;

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

          v_default_following:=coalesce(v_default_following,false)
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
              where wh.teacher_id=v_series.teacher_id
                and wh.weekday=v_series.weekday
                and wh.start_time<=v_series.start_time
                and wh.end_time>=(v_candidate.ends_at at time zone 'Asia/Seoul')::time
            ) then
              raise exception using errcode='P0001',message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',detail='date='||v_candidate.lesson_date::text;
            end if;

            if exists (
              select 1 from public.blocked_periods bp
              where bp.teacher_id=v_series.teacher_id
                and tstzrange(bp.starts_at,bp.ends_at,'[)') && tstzrange(v_candidate.starts_at,v_candidate.ends_at,'[)')
            ) then
              raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_BLOCKED',detail='starts_at='||v_candidate.starts_at::text;
            end if;

            update public.lesson_rights set duration_minutes=v_series.duration_minutes where id=v_right.id;

            begin
              update public.lessons
              set series_id=v_series.id,
                  teacher_id=v_series.teacher_id,
                  occurrence_at=v_candidate.starts_at,
                  starts_at=v_candidate.starts_at,
                  duration_minutes=v_series.duration_minutes
              where lesson_right_id=v_right.id;
            exception when exclusion_violation then
              raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT',detail='right_id='||v_right.id::text||', starts_at='||v_candidate.starts_at::text;
            end;

            v_reconciled:=v_reconciled+1;
          else
            select (l.occurrence_at at time zone 'Asia/Seoul')::date
            into v_original_date
            from public.lessons l
            where l.lesson_right_id=v_right.id
              and l.lesson_type='regular'::public.lesson_type
              and l.occurrence_at is not null
            order by l.occurrence_at,l.id
            limit 1;

            if not found or v_original_date is distinct from v_candidate.lesson_date then
              raise exception using errcode='P0001',message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',detail='right_id='||v_right.id::text||', original='||coalesce(v_original_date::text,'null')||', target='||v_candidate.lesson_date::text;
            end if;

            v_preserved:=v_preserved+1;
          end if;
        end loop;
      end loop;

      if v_processed_rights<>4 then
        raise exception using errcode='P0001',message='FORESTRING_REGULAR_RECONCILIATION_SERIES_MAPPING_INCOMPLETE',detail='schedule_slot_id='||v_slot.id::text||', processed='||v_processed_rights::text;
      end if;
    end loop;
  end loop;

  insert into public.audit_events(branch_id,semester_id,event_type,effective_on,actor_id,details)
  values(p_branch_id,p_semester_id,'FUTURE_SEMESTER_RECONCILED',v_start,auth.uid(),jsonb_build_object('reconciledLessonCount',v_reconciled,'preservedUsedRightCount',v_preserved));

  return v_reconciled;
end;
$function$;

revoke all on function private.rebuild_future_regular_semester(uuid,uuid) from public,anon,authenticated;
