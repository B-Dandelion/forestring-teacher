-- Replay-safe convergence for the partial-first-semester activation change.
--
-- Production received the partial-semester behavior during incident response
-- before its original SQL was fully captured in Git. On a fresh replay the
-- function can therefore still be in the older "exactly four occurrences per
-- slot" form when this migration runs.
--
-- Important: 20260825083025 replaced activate_student_semester_plan() and no
-- longer contains the older "BUILD RIGHTS + LESSONS" section comment. Do not
-- use that comment as a patch anchor. Patch the concrete validation block
-- instead, then assert the intended behavior.

do $mig$
declare
  v_def text;
  v_new text;
  v_marker text := 'select count(*)::integer into v_expected_right_count';
begin
  select pg_get_functiondef('public.activate_student_semester_plan(uuid)'::regprocedure)
  into v_def;

  if position('v_slot_count * 4;' in v_def) > 0 then
    v_new := replace(
      v_def,
      'v_slot_count * 4;',
      $replacement$v_slot_count * 4;

  with teaching_dates as (
    select d::date as lesson_date
    from pg_catalog.generate_series(
      v_semester_start::timestamp,
      v_semester_end::timestamp,
      interval '1 day'
    ) d
    where not exists (
      select 1
      from public.closure_periods cp
      where cp.branch_id = v_plan.branch_id
        and cp.semester_id = v_plan.semester_id
        and cp.closure_kind = 'instructional_break'::public.closure_kind
        and d::date between cp.starts_on and cp.ends_on
    )
  ), candidate_rows as (
    select rs.id as schedule_slot_id, td.lesson_date, ls.id as series_id
    from public.regular_schedule_slots rs
    join teaching_dates td
      on td.lesson_date >= rs.starts_on
     and (rs.ends_on is null or td.lesson_date <= rs.ends_on)
    join public.lesson_series ls
      on ls.schedule_slot_id = rs.id
     and ls.student_id = v_plan.student_id
     and ls.branch_id = v_plan.branch_id
     and td.lesson_date >= ls.effective_from
     and (ls.effective_until is null or td.lesson_date <= ls.effective_until)
     and extract(isodow from td.lesson_date)::integer = ls.weekday
    where rs.student_id = v_plan.student_id
      and rs.branch_id = v_plan.branch_id
      and rs.starts_on <= v_semester_end
      and (rs.ends_on is null or rs.ends_on >= v_semester_start)
  )
  select count(*)::integer into v_expected_right_count
  from candidate_rows;

  if v_expected_right_count = 0 then
    raise exception using errcode='P0001', message='FORESTRING_REGULAR_PLAN_HAS_NO_OCCURRENCES';
  end if;$replacement$
    );

    if v_new = v_def then
      raise exception 'FORESTRING_REPLAY_PARTIAL_EXPECTED_COUNT_PATCH_FAILED';
    end if;
    v_def := v_new;

    v_new := replace(
      v_def,
      $old$    if v_candidate_count <> 4 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES',
        detail='schedule_slot_id='||v_slot.id::text||', candidate_count='||v_candidate_count::text;
    end if;$old$,
      $new$    if v_candidate_count = 0 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_NO_OCCURRENCES',
        detail='schedule_slot_id='||v_slot.id::text;
    end if;

    if v_candidate_count > 4 then
      raise exception using
        errcode='P0001',
        message='FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES',
        detail='schedule_slot_id=' || v_slot.id::text || ', candidate_count=' || v_candidate_count::text;
    end if;$new$
    );

    if v_new = v_def then
      raise exception 'FORESTRING_REPLAY_PARTIAL_SLOT_GUARD_PATCH_FAILED';
    end if;

    execute v_new;
  end if;

  select pg_get_functiondef('public.activate_student_semester_plan(uuid)'::regprocedure)
  into v_def;

  if position(v_marker in v_def) = 0
     or position('FORESTRING_REGULAR_SLOT_TOO_MANY_OCCURRENCES' in v_def) = 0
     or position('FORESTRING_REGULAR_SLOT_NO_OCCURRENCES' in v_def) = 0
     or position('FORESTRING_REGULAR_SLOT_NOT_FOUR_OCCURRENCES' in v_def) > 0 then
    raise exception 'FORESTRING_PARTIAL_REGULAR_ACTIVATION_NOT_ENFORCED';
  end if;
end;
$mig$;
