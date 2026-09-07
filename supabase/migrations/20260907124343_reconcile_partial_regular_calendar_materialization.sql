create or replace function private.rebuild_future_regular_semester(
  p_semester_id uuid,
  p_branch_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_today date := (pg_catalog.now() at time zone 'Asia/Seoul')::date;
  v_start date;
  v_end date;
  v_effective_end date;
  v_plan record;
  v_slot record;
  v_right public.lesson_rights%rowtype;
  v_candidate record;
  v_target_count integer;
  v_final_count integer;
  v_seq integer;
  v_original_date date;
  v_default_following boolean;
  v_slot_overlaps boolean;
  v_reconciled integer := 0;
  v_preserved integer := 0;
  v_created integer := 0;
  v_deleted integer := 0;
begin
  select e.starts_on, e.ends_on
  into v_start, v_end
  from private.get_effective_semester_bounds(p_branch_id, p_semester_id) e;

  if not found then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.student_semester_plans sp
    where sp.semester_id = p_semester_id
      and sp.branch_id = p_branch_id
      and sp.status = 'active'::public.student_semester_plan_status
      and sp.student_type_snapshot = 'regular'::public.student_type
  ) then
    return 0;
  end if;

  if v_start <= v_today then
    raise exception using
      errcode='P0001',
      message='FORESTRING_CALENDAR_REBUILD_REQUIRES_FUTURE_SEMESTER';
  end if;

  for v_plan in
    select sp.id, sp.student_id, s.withdrawal_date
    from public.student_semester_plans sp
    join public.students s on s.id = sp.student_id
    where sp.semester_id = p_semester_id
      and sp.branch_id = p_branch_id
      and sp.status = 'active'::public.student_semester_plan_status
      and sp.student_type_snapshot = 'regular'::public.student_type
    order by sp.student_id
    for update of sp
  loop
    v_effective_end := v_end;
    if v_plan.withdrawal_date is not null then
      v_effective_end := least(v_effective_end, v_plan.withdrawal_date - 1);
    end if;

    if v_effective_end < v_start then
      raise exception using
        errcode='P0001',
        message='FORESTRING_CALENDAR_CHANGE_REMOVES_ACTIVE_PLAN_WINDOW',
        detail='plan_id=' || v_plan.id::text;
    end if;

    for v_slot in
      select rs.id, rs.starts_on, rs.ends_on
      from public.regular_schedule_slots rs
      where rs.student_id = v_plan.student_id
        and rs.branch_id = p_branch_id
        and (
          (
            rs.starts_on <= v_effective_end
            and (rs.ends_on is null or rs.ends_on >= v_start)
          )
          or exists (
            select 1
            from public.lesson_rights r
            where r.student_id = v_plan.student_id
              and r.branch_id = p_branch_id
              and r.source_semester_id = p_semester_id
              and r.schedule_slot_id = rs.id
              and r.origin = 'regular_base'::public.lesson_right_origin
          )
        )
      order by rs.starts_on, rs.id
    loop
      v_slot_overlaps :=
        v_slot.starts_on <= v_effective_end
        and (v_slot.ends_on is null or v_slot.ends_on >= v_start);

      with raw_candidates as (
        select
          d::date as lesson_date,
          ls.id as series_id,
          ls.teacher_id,
          ls.weekday,
          ls.start_time,
          ls.duration_minutes,
          (d::date + ls.start_time) at time zone 'Asia/Seoul' as starts_at
        from pg_catalog.generate_series(
          greatest(v_start, v_slot.starts_on)::timestamp,
          least(
            v_effective_end,
            coalesce(v_slot.ends_on, v_effective_end)
          )::timestamp,
          interval '1 day'
        ) d
        join public.lesson_series ls
          on ls.schedule_slot_id = v_slot.id
         and ls.student_id = v_plan.student_id
         and ls.branch_id = p_branch_id
         and d::date >= ls.effective_from
         and (ls.effective_until is null or d::date <= ls.effective_until)
         and extract(isodow from d::date)::integer = ls.weekday
        where not exists (
          select 1
          from public.closure_periods cp
          where cp.branch_id = p_branch_id
            and cp.semester_id = p_semester_id
            and cp.closure_kind = 'instructional_break'::public.closure_kind
            and d::date between cp.starts_on and cp.ends_on
        )
      )
      select count(*)::integer
      into v_target_count
      from raw_candidates;

      if v_slot_overlaps and v_target_count = 0 then
        raise exception using
          errcode='P0001',
          message='FORESTRING_REGULAR_SLOT_NO_OCCURRENCES',
          detail='schedule_slot_id=' || v_slot.id::text;
      end if;

      if v_target_count > 4 then
        raise exception using
          errcode='P0001',
          message='FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES',
          detail='schedule_slot_id=' || v_slot.id::text || ', candidate_count=' || v_target_count::text;
      end if;

      for v_right in
        select r.*
        from public.lesson_rights r
        where r.student_id = v_plan.student_id
          and r.branch_id = p_branch_id
          and r.source_semester_id = p_semester_id
          and r.schedule_slot_id = v_slot.id
          and r.origin = 'regular_base'::public.lesson_right_origin
          and r.sequence_no > v_target_count
        order by r.sequence_no desc, r.id
        for update
      loop
        select
          count(*) = 1
          and bool_and(l.lesson_type = 'regular'::public.lesson_type)
          and bool_and(l.status = 'scheduled'::public.lesson_status)
          and bool_and(l.rescheduled_by is null)
          and bool_and(l.canceled_at is null)
          and not exists (
            select 1
            from public.lesson_cancellation_events ce
            where ce.lesson_right_id = v_right.id
          )
          and not exists (
            select 1
            from public.lesson_rights child
            where child.source_right_id = v_right.id
          )
          and not exists (
            select 1
            from public.lessons ml
            where ml.manual_makeup_right_id = v_right.id
          )
          and not exists (
            select 1
            from public.lesson_rebooking_credits c
            join public.lessons sl on sl.id = c.source_lesson_id
            where sl.lesson_right_id = v_right.id
          )
        into v_default_following
        from public.lessons l
        where l.lesson_right_id = v_right.id;

        v_default_following :=
          coalesce(v_default_following, false)
          and v_right.status = 'reserved'::public.lesson_right_status;

        if not v_default_following then
          raise exception using
            errcode='P0001',
            message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',
            detail='right_id=' || v_right.id::text;
        end if;

        delete from public.lessons l
        where l.lesson_right_id = v_right.id;

        delete from public.lesson_rights r
        where r.id = v_right.id;

        v_deleted := v_deleted + 1;
      end loop;

      if not v_slot_overlaps then
        continue;
      end if;

      for v_seq in 1..v_target_count
      loop
        with raw_candidates as (
          select
            d::date as lesson_date,
            ls.id as series_id,
            ls.teacher_id,
            ls.weekday,
            ls.start_time,
            ls.duration_minutes,
            (d::date + ls.start_time) at time zone 'Asia/Seoul' as starts_at
          from pg_catalog.generate_series(
            greatest(v_start, v_slot.starts_on)::timestamp,
            least(
              v_effective_end,
              coalesce(v_slot.ends_on, v_effective_end)
            )::timestamp,
            interval '1 day'
          ) d
          join public.lesson_series ls
            on ls.schedule_slot_id = v_slot.id
           and ls.student_id = v_plan.student_id
           and ls.branch_id = p_branch_id
           and d::date >= ls.effective_from
           and (ls.effective_until is null or d::date <= ls.effective_until)
           and extract(isodow from d::date)::integer = ls.weekday
          where not exists (
            select 1
            from public.closure_periods cp
            where cp.branch_id = p_branch_id
              and cp.semester_id = p_semester_id
              and cp.closure_kind = 'instructional_break'::public.closure_kind
              and d::date between cp.starts_on and cp.ends_on
          )
        ), numbered as (
          select
            row_number() over(order by rc.starts_at, rc.series_id)::integer as sequence_no,
            rc.lesson_date,
            rc.series_id,
            rc.teacher_id,
            rc.weekday,
            rc.start_time,
            rc.duration_minutes,
            rc.starts_at,
            rc.starts_at + pg_catalog.make_interval(mins => rc.duration_minutes) as ends_at
          from raw_candidates rc
        )
        select *
        into v_candidate
        from numbered
        where sequence_no = v_seq;

        if not found then
          raise exception using
            errcode='P0001',
            message='FORESTRING_REGULAR_RECONCILIATION_COUNT_MISMATCH',
            detail='schedule_slot_id=' || v_slot.id::text || ', sequence=' || v_seq::text;
        end if;

        select r.*
        into v_right
        from public.lesson_rights r
        where r.student_id = v_plan.student_id
          and r.branch_id = p_branch_id
          and r.source_semester_id = p_semester_id
          and r.schedule_slot_id = v_slot.id
          and r.origin = 'regular_base'::public.lesson_right_origin
          and r.sequence_no = v_seq
        for update;

        if found then
          select
            count(*) = 1
            and bool_and(l.lesson_type = 'regular'::public.lesson_type)
            and bool_and(l.status = 'scheduled'::public.lesson_status)
            and bool_and(l.rescheduled_by is null)
            and bool_and(l.canceled_at is null)
            and not exists (
              select 1
              from public.lesson_cancellation_events ce
              where ce.lesson_right_id = v_right.id
            )
            and not exists (
              select 1
              from public.lesson_rights child
              where child.source_right_id = v_right.id
            )
            and not exists (
              select 1
              from public.lessons ml
              where ml.manual_makeup_right_id = v_right.id
            )
            and not exists (
              select 1
              from public.lesson_rebooking_credits c
              join public.lessons sl on sl.id = c.source_lesson_id
              where sl.lesson_right_id = v_right.id
            )
          into v_default_following
          from public.lessons l
          where l.lesson_right_id = v_right.id;

          v_default_following :=
            coalesce(v_default_following, false)
            and v_right.status = 'reserved'::public.lesson_right_status;

          if v_default_following then
            if not exists (
              select 1
              from private.teacher_work_hours_for_date(
                v_candidate.teacher_id,
                v_candidate.lesson_date
              ) wh
              where wh.teacher_id = v_candidate.teacher_id
                and wh.weekday = v_candidate.weekday
                and wh.start_time <= v_candidate.start_time
                and wh.end_time >= (v_candidate.ends_at at time zone 'Asia/Seoul')::time
            ) then
              raise exception using
                errcode='P0001',
                message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',
                detail='date=' || v_candidate.lesson_date::text;
            end if;

            if exists (
              select 1
              from public.blocked_periods bp
              where bp.teacher_id = v_candidate.teacher_id
                and tstzrange(bp.starts_at, bp.ends_at, '[)')
                    && tstzrange(v_candidate.starts_at, v_candidate.ends_at, '[)')
            ) then
              raise exception using
                errcode='P0001',
                message='FORESTRING_REGULAR_RECONCILIATION_BLOCKED',
                detail='starts_at=' || v_candidate.starts_at::text;
            end if;

            update public.lesson_rights
            set duration_minutes = v_candidate.duration_minutes
            where id = v_right.id;

            begin
              update public.lessons
              set
                series_id = v_candidate.series_id,
                teacher_id = v_candidate.teacher_id,
                occurrence_at = v_candidate.starts_at,
                starts_at = v_candidate.starts_at,
                duration_minutes = v_candidate.duration_minutes
              where lesson_right_id = v_right.id;
            exception
              when exclusion_violation then
                raise exception using
                  errcode='P0001',
                  message='FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT',
                  detail='right_id=' || v_right.id::text || ', starts_at=' || v_candidate.starts_at::text;
            end;

            v_reconciled := v_reconciled + 1;
          else
            select (l.occurrence_at at time zone 'Asia/Seoul')::date
            into v_original_date
            from public.lessons l
            where l.lesson_right_id = v_right.id
              and l.lesson_type = 'regular'::public.lesson_type
              and l.occurrence_at is not null
            order by l.occurrence_at, l.id
            limit 1;

            if not found
               or v_original_date is distinct from v_candidate.lesson_date then
              raise exception using
                errcode='P0001',
                message='FORESTRING_CALENDAR_CHANGE_TOUCHES_USED_REGULAR_RIGHT',
                detail='right_id=' || v_right.id::text
                  || ', original=' || coalesce(v_original_date::text, 'null')
                  || ', target=' || v_candidate.lesson_date::text;
            end if;

            v_preserved := v_preserved + 1;
          end if;
        else
          if not exists (
            select 1
            from private.teacher_work_hours_for_date(
              v_candidate.teacher_id,
              v_candidate.lesson_date
            ) wh
            where wh.teacher_id = v_candidate.teacher_id
              and wh.weekday = v_candidate.weekday
              and wh.start_time <= v_candidate.start_time
              and wh.end_time >= (v_candidate.ends_at at time zone 'Asia/Seoul')::time
          ) then
            raise exception using
              errcode='P0001',
              message='FORESTRING_REGULAR_OCCURRENCE_OUTSIDE_WORK_HOURS',
              detail='date=' || v_candidate.lesson_date::text;
          end if;

          if exists (
            select 1
            from public.blocked_periods bp
            where bp.teacher_id = v_candidate.teacher_id
              and tstzrange(bp.starts_at, bp.ends_at, '[)')
                  && tstzrange(v_candidate.starts_at, v_candidate.ends_at, '[)')
          ) then
            raise exception using
              errcode='P0001',
              message='FORESTRING_REGULAR_RECONCILIATION_BLOCKED',
              detail='starts_at=' || v_candidate.starts_at::text;
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
          ) values (
            v_plan.student_id,
            p_branch_id,
            p_semester_id,
            p_semester_id,
            v_slot.id,
            null,
            'regular_base'::public.lesson_right_origin,
            v_seq,
            v_candidate.duration_minutes,
            'reserved'::public.lesson_right_status,
            0,
            auth.uid(),
            pg_catalog.now()
          )
          returning * into v_right;

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
              v_candidate.series_id,
              v_plan.student_id,
              v_candidate.teacher_id,
              v_candidate.starts_at,
              v_candidate.starts_at,
              v_candidate.duration_minutes,
              'regular'::public.lesson_type,
              'scheduled'::public.lesson_status,
              v_right.id
            );
          exception
            when exclusion_violation then
              raise exception using
                errcode='P0001',
                message='FORESTRING_REGULAR_RECONCILIATION_TIME_CONFLICT',
                detail='right_id=' || v_right.id::text || ', starts_at=' || v_candidate.starts_at::text;
          end;

          v_created := v_created + 1;
        end if;
      end loop;

      select count(*)::integer
      into v_final_count
      from public.lesson_rights r
      where r.student_id = v_plan.student_id
        and r.branch_id = p_branch_id
        and r.source_semester_id = p_semester_id
        and r.schedule_slot_id = v_slot.id
        and r.origin = 'regular_base'::public.lesson_right_origin;

      if v_final_count <> v_target_count
         or exists (
           select 1
           from pg_catalog.generate_series(1, v_target_count) expected(sequence_no)
           where not exists (
             select 1
             from public.lesson_rights r
             where r.student_id = v_plan.student_id
               and r.branch_id = p_branch_id
               and r.source_semester_id = p_semester_id
               and r.schedule_slot_id = v_slot.id
               and r.origin = 'regular_base'::public.lesson_right_origin
               and r.sequence_no = expected.sequence_no
           )
         ) then
        raise exception using
          errcode='P0001',
          message='FORESTRING_REGULAR_RECONCILIATION_SERIES_MAPPING_INCOMPLETE',
          detail='schedule_slot_id=' || v_slot.id::text
            || ', expected=' || v_target_count::text
            || ', actual=' || v_final_count::text;
      end if;
    end loop;
  end loop;

  insert into public.audit_events(
    branch_id,
    semester_id,
    event_type,
    effective_on,
    actor_id,
    details
  ) values (
    p_branch_id,
    p_semester_id,
    'FUTURE_SEMESTER_RECONCILED',
    v_start,
    auth.uid(),
    jsonb_build_object(
      'reconciledLessonCount', v_reconciled,
      'preservedUsedRightCount', v_preserved,
      'createdRightCount', v_created,
      'deletedRightCount', v_deleted
    )
  );

  return v_reconciled + v_created + v_deleted;
end;
$function$;

create or replace function public.apply_semester_calendar_batch(
  p_changes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_item jsonb;
  v_semester_id uuid;
  v_code text;
  v_starts_on date;
  v_ends_on date;
  v_existing public.semesters%rowtype;
  v_changed_ids uuid[] := array[]::uuid[];
  v_date_changed_ids uuid[] := array[]::uuid[];
  v_changed_count integer := 0;
  v_stage_base date;
  v_stage_index integer := 0;
  v_branch record;
begin
  select a.actor_id, a.actor_role
  into v_actor_id, v_actor_role
  from private.require_calendar_actor(null, true) a;

  if p_changes is null
     or jsonb_typeof(p_changes) <> 'array'
     or jsonb_array_length(p_changes) = 0 then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_BATCH_REQUIRED';
  end if;

  if exists (
    select 1
    from (
      select value ->> 'semesterId' as semester_id_text, count(*) as item_count
      from jsonb_array_elements(p_changes)
      group by value ->> 'semesterId'
    ) duplicate
    where duplicate.semester_id_text is null
       or duplicate.semester_id_text = ''
       or duplicate.item_count > 1
  ) then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_BATCH_DUPLICATE_OR_MISSING_ID';
  end if;

  for v_item in select value from jsonb_array_elements(p_changes)
  loop
    begin
      v_semester_id := (v_item ->> 'semesterId')::uuid;
      v_starts_on := (v_item ->> 'startsOn')::date;
      v_ends_on := (v_item ->> 'endsOn')::date;
    exception when others then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_SEMESTER_BATCH_ITEM';
    end;

    v_code := nullif(btrim(coalesce(v_item ->> 'code', '')), '');
    if v_code is null then raise exception using errcode='P0001', message='FORESTRING_SEMESTER_CODE_REQUIRED'; end if;
    if v_starts_on > v_ends_on then raise exception using errcode='P0001', message='FORESTRING_INVALID_SEMESTER_RANGE'; end if;
    if (v_ends_on - v_starts_on + 1) < 28 or mod(v_ends_on - v_starts_on + 1, 7) <> 0 then
      raise exception using errcode='P0001', message='FORESTRING_INVALID_SEMESTER_WEEK_STRUCTURE';
    end if;

    select * into v_existing from public.semesters s where s.id = v_semester_id for update;
    if not found then raise exception using errcode='P0001', message='FORESTRING_SEMESTER_NOT_FOUND'; end if;

    if (v_existing.starts_on is distinct from v_starts_on or v_existing.ends_on is distinct from v_ends_on)
       and private.calendar_semester_is_materialized(v_existing.id, null) then
      raise exception using errcode='P0001', message='FORESTRING_MATERIALIZED_SEMESTER_DATES_IMMUTABLE';
    end if;

    if v_existing.code is distinct from v_code
       or v_existing.starts_on is distinct from v_starts_on
       or v_existing.ends_on is distinct from v_ends_on then
      v_changed_ids := array_append(v_changed_ids, v_semester_id);
      v_changed_count := v_changed_count + 1;
    end if;

    if v_existing.starts_on is distinct from v_starts_on
       or v_existing.ends_on is distinct from v_ends_on then
      v_date_changed_ids := array_append(v_date_changed_ids, v_semester_id);
    end if;
  end loop;

  if v_changed_count = 0 then
    return jsonb_build_object('changed', false, 'changedCount', 0);
  end if;

  select coalesce(max(s.ends_on), (pg_catalog.now() at time zone 'Asia/Seoul')::date) + 3650
  into v_stage_base from public.semesters s;

  for v_item in select value from jsonb_array_elements(p_changes)
  loop
    v_semester_id := (v_item ->> 'semesterId')::uuid;
    if not (v_semester_id = any(v_changed_ids)) then continue; end if;
    update public.semesters
    set code='__FORESTRING_STAGE__'||v_semester_id::text,
        starts_on=v_stage_base+(v_stage_index*35),
        ends_on=v_stage_base+(v_stage_index*35)+27
    where id=v_semester_id;
    v_stage_index:=v_stage_index+1;
  end loop;

  for v_item in select value from jsonb_array_elements(p_changes)
  loop
    v_semester_id := (v_item ->> 'semesterId')::uuid;
    if not (v_semester_id = any(v_changed_ids)) then continue; end if;
    v_code:=btrim(v_item ->> 'code');
    v_starts_on:=(v_item ->> 'startsOn')::date;
    v_ends_on:=(v_item ->> 'endsOn')::date;
    begin
      update public.semesters set code=v_code,starts_on=v_starts_on,ends_on=v_ends_on where id=v_semester_id;
    exception
      when unique_violation then raise exception using errcode='P0001', message='FORESTRING_SEMESTER_CODE_ALREADY_EXISTS';
      when exclusion_violation then raise exception using errcode='P0001', message='FORESTRING_SEMESTER_OVERLAP';
    end;
  end loop;

  if not private.global_semester_calendar_is_contiguous() then
    raise exception using errcode='P0001', message='FORESTRING_SEMESTER_CALENDAR_NOT_CONTIGUOUS';
  end if;

  for v_branch in select b.id from public.branches b
  loop
    if not private.branch_semester_calendar_is_contiguous(v_branch.id) then
      raise exception using errcode='P0001', message='FORESTRING_BRANCH_SEMESTER_CALENDAR_NOT_CONTIGUOUS', detail='branch_id='||v_branch.id::text;
    end if;
  end loop;

  if exists (
    select 1 from public.branch_semester_overrides o join public.semesters s on s.id=o.semester_id
    where o.starts_on=s.starts_on and o.ends_on=s.ends_on
  ) then
    raise exception using errcode='P0001', message='FORESTRING_REDUNDANT_SEMESTER_OVERRIDE';
  end if;

  if exists (
    select 1
    from public.closure_periods cp
    cross join lateral private.get_effective_semester_bounds(cp.branch_id,cp.semester_id) e
    where cp.semester_id is not null and (cp.starts_on<e.starts_on or cp.ends_on>e.ends_on)
  ) then
    raise exception using errcode='P0001', message='FORESTRING_EXISTING_CLOSURE_OUTSIDE_EFFECTIVE_SEMESTER';
  end if;

  foreach v_semester_id in array v_date_changed_ids
  loop
    for v_branch in
      select b.id from public.branches b
      where not exists (
        select 1 from public.branch_semester_overrides o
        where o.branch_id=b.id and o.semester_id=v_semester_id
      )
    loop
      perform private.rebuild_future_regular_semester(v_semester_id,v_branch.id);
    end loop;
  end loop;

  insert into public.audit_events(event_type,actor_id,details)
  values('SEMESTER_CALENDAR_BATCH_UPDATED',v_actor_id,jsonb_build_object('changedCount',v_changed_count,'changes',p_changes));

  return jsonb_build_object('changed',true,'changedCount',v_changed_count);
end;
$function$;
